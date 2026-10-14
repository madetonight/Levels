import AppKit
import CoreAudio
import QuartzCore
import ServiceManagement
import SwiftUI

private final class UpdateDotView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@main
enum LevelsApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = LevelsDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class LevelsDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let engine = MixerEngine()
    private lazy var options = MixerOptions(engine: engine)
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var presentationSession: AnyObject?
    private let closeTransition = PopoverCloseTransition()
    private var outsideClickMonitor: Any?
    private var isShowingOptionsMenu = false
    private var updateDot: NSView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("Levels menu bar app")
        options.onShowSettings = { [weak self] in
            guard let self else { return }
            self.stopClickAwayMonitoring()
            self.closeTransition.cancel()
            self.popover.animates = false
            self.popover.close()
            self.endPresentationSession()
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "LevelsMixer"
        statusItem = item
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "Levels volume mixer")
            button.image?.isTemplate = true
            if button.image == nil {
                item.length = NSStatusItem.variableLength
                button.title = "Levels"
            }
            button.setAccessibilityLabel("Levels volume mixer")
            button.setAccessibilityIdentifier("com.joseluna.levels.mixer")
            button.toolTip = "Levels · Volume mixer"
            if #available(macOS 27.0, *) {
                item.expandedInterfaceDelegate = self
                // Left clicks retain native expanded-interface handling.
                // Request a separate action for secondary clicks only.
                button.target = self
                button.action = #selector(showContextMenu)
                button.sendAction(on: [.rightMouseUp])
            } else {
                button.target = self
                button.action = #selector(togglePopover)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
        }
        popover.behavior = .transient
        // Opening remains native. Closing uses a cancellable deadline,
        // never an animation-completion callback.
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        let hosting = NSHostingController(rootView: MixerView().environment(engine).environment(options))
        hosting.sizingOptions = []
        hosting.view.frame.size = NSSize(width: MixerLayout.width, height: MixerLayout.height)
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: MixerLayout.width, height: MixerLayout.height)
        options.updates.onAvailabilityChange = { [weak self] in self?.refreshUpdateIndicator() }
        refreshUpdateIndicator()
        options.updates.start()

        // Keep the menu responsive even if Core Audio is temporarily unavailable.
        Task.detached(priority: .userInitiated) { [engine] in
            _ = try? AudioObjectID.readDefaultOutputDevice()
            await MainActor.run { engine.start() }
        }
        // Do not open or activate a status item hidden by a menu bar manager.
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }

    private func refreshUpdateIndicator() {
        guard let button = statusItem?.button else { return }
        // Keep the status item itself and its image unchanged for menu-bar
        // managers. A tiny noninteractive dot is attached inside its bounds.
        if options.updates.hasUpdateAvailable {
            if updateDot == nil {
                let dot = UpdateDotView(frame: .zero)
                dot.wantsLayer = true
                dot.layer?.backgroundColor = NSColor.white.cgColor
                dot.layer?.cornerRadius = 2
                dot.layer?.borderWidth = 0.5
                dot.layer?.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor
                dot.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(dot)
                updateDot = dot
                NSLayoutConstraint.activate([
                    dot.widthAnchor.constraint(equalToConstant: 4), dot.heightAnchor.constraint(equalToConstant: 4),
                    dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -3),
                    dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 3)
                ])
            }
            button.toolTip = "Levels · Update available"
            button.setAccessibilityLabel("Levels volume mixer, update available")
        } else {
            updateDot?.removeFromSuperview()
            updateDot = nil
            button.toolTip = "Levels · Volume mixer"
            button.setAccessibilityLabel("Levels volume mixer")
        }
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if closeTransition.isClosing {
            showPopover()
        } else if popover.isShown {
            requestPopoverClose()
        } else {
            showPopover()
        }
    }

    private func showPopover(session: AnyObject? = nil) {
        guard let button = statusItem?.button else { return }
        if closeTransition.isClosing {
            closeTransition.cancel()
            popover.animates = false
            popover.close()
        }
        if let session { presentationSession = session }
        guard !popover.isShown else { return }
        // macOS 27 hosts items in MenuBarAgent: legacy button-window geometry
        // is not a valid test of whether Thaw has revealed an item.
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.alphaValue = 1
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidShow(_ notification: Notification) {
        engine.processMonitor.setMeteringVisible(true)
        stopClickAwayMonitoring()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            // AppKit delivers event monitors on the main thread. Handle the
            // current presentation directly, without a queued stale close.
            MainActor.assumeIsolated {
                guard let self, let window = self.popover.contentViewController?.view.window,
                      !window.frame.contains(NSEvent.mouseLocation) else { return }
                self.requestPopoverClose()
            }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        requestPopoverClose()
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              popover.contentViewController?.view.window != nil else { return true }
        requestPopoverClose()
        return false
    }

    private func requestPopoverClose() {
        guard popover.isShown, !closeTransition.isClosing else { return }
        stopClickAwayMonitoring()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let window = popover.contentViewController?.view.window else {
            popover.animates = false
            popover.close()
            return
        }
        closeTransition.begin {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 0
            }
        } close: { [weak self, weak window] in
            guard let self else { return }
            self.popover.animates = false
            self.popover.close()
            window?.alphaValue = 1
        }
        // Release menu tracking now, not after the fade. Cancelling can call
        // didEnd synchronously; the closing guard makes that callback harmless.
        endPresentationSession()
    }

    private func stopClickAwayMonitoring() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func endPresentationSession() {
        let session = presentationSession
        presentationSession = nil
        if #available(macOS 27.0, *),
           let session = session as? NSStatusItemExpandedInterfaceSession {
            session.cancel()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        engine.processMonitor.setMeteringVisible(false)
        stopClickAwayMonitoring()
        closeTransition.cancel()
        endPresentationSession()
    }

    @objc private func showContextMenu() {
        guard let item = statusItem, !isShowingOptionsMenu else { return }
        isShowingOptionsMenu = true
        stopClickAwayMonitoring()
        closeTransition.cancel()
        if popover.isShown {
            popover.animates = false
            popover.close()
        }
        endPresentationSession()
        item.menu = options.makeMenu()
        // Never leave a menu assigned: it suppresses expanded-interface
        // callbacks on macOS 27 and would replace normal mixer opening.
        defer {
            item.menu = nil
            isShowingOptionsMenu = false
        }
        item.button?.performClick(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopClickAwayMonitoring()
        closeTransition.cancel()
        engine.fadeOutAndStop()
        engine.multiOutput.shutdown()
    }
}

@available(macOS 27.0, *)
extension LevelsDelegate: @preconcurrency NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        if let event = NSApp.currentEvent, event.type == .rightMouseDown || event.type == .rightMouseUp {
            presentationSession = session
            showContextMenu()
            return
        }
        showPopover(session: session)
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        requestPopoverClose()
    }
}
