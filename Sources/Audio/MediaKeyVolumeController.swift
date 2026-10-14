import AppKit
import ApplicationServices
import Observation

/// Intercepts only volume media keys, only for the explicitly enabled fixed
/// digital output. All other keys and all hardware-volume devices pass through.
@MainActor @Observable
final class MediaKeyVolumeController {
    private(set) var needsPermission = false
    private(set) var unavailable = false
    @ObservationIgnored private let volume: SystemVolumeController
    @ObservationIgnored private var eventTap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private let hud = VolumeKeyHUD()

    init(volume: SystemVolumeController) { self.volume = volume }

    func start() {
        guard !started else { return }
        started = true
        observeVolume()
        activeObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        refresh()
    }

    func suspend() { suspended = true; removeTap(); hud.hide() }
    func resume() { suspended = false; refresh() }

    func requestPermission() {
        // Called only from the user's menu/button action, never at startup.
        // Value of kAXTrustedCheckOptionPrompt; importing its legacy mutable
        // C global conflicts with Swift 6 strict concurrency.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }

    private func observeVolume() {
        withObservationTracking { _ = volume.softwareActive } onChange: { [weak self] in
            Task { @MainActor in self?.refresh(); self?.observeVolume() }
        }
    }

    private func refresh() {
        guard started, !suspended, volume.softwareActive else {
            removeTap(); needsPermission = false; unavailable = false
            return
        }
        guard eventTap == nil else { return }
        needsPermission = !AXIsProcessTrusted()
        guard !needsPermission else { unavailable = false; return }
        // NX_SYSDEFINED (14), subtype 8: documented media-key packet layout.
        let mask = CGEventMask(1) << 14
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consumed = MainActor.assumeIsolated {
                    let controller = Unmanaged<MediaKeyVolumeController>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = controller.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                        return false
                    }
                    guard controller.volume.softwareActive, !controller.suspended,
                        let native = NSEvent(cgEvent: event), native.type == .systemDefined,
                        let packet = VolumeKey.decode(subtype: Int(native.subtype.rawValue), data1: native.data1)
                    else { return false }
                    if packet.pressed { controller.handle(packet.key, fine: native.modifierFlags.contains([.shift, .option])) }
                    return true
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: context), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                unavailable = true
                return
            }
        eventTap = tap
        self.source = source
        unavailable = false
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(_ key: VolumeKey, fine: Bool) {
        let step: Float = fine ? 1 / 64 : 1 / 16
        switch key {
        case .mute: volume.toggleMute()
        case .up, .down:
            if volume.isMuted { volume.toggleMute() }
            volume.setVolume(volume.volume + (key == .up ? step : -step))
        }
        hud.show(name: volume.deviceName, value: volume.volume, muted: volume.isMuted)
    }

    private func removeTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        source = nil; eventTap = nil
    }

    isolated deinit {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        removeTap()
        hud.hide()
    }
}

/// Transient, nonactivating HUD. No main app window is introduced.
@MainActor private final class VolumeKeyHUD {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(name: String, value: Float, muted: Bool) {
        dismissal?.cancel()
        let panel = panel ?? makePanel()
        let content = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 250, height: 88))
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 18
        content.layer?.masksToBounds = true
        let icon = NSImageView(frame: NSRect(x: 18, y: 31, width: 28, height: 28))
        icon.image = NSImage(systemSymbolName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityDescription: muted ? "Muted" : "Volume")
        content.addSubview(icon)
        let title = NSTextField(labelWithString: name)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 58, y: 58, width: 174, height: 16)
        content.addSubview(title)
        let label = NSTextField(labelWithString: muted ? "Muted" : "\(Int((value * 100).rounded()))%")
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.frame = NSRect(x: 58, y: 32, width: 174, height: 24)
        content.addSubview(label)
        let bar = NSLevelIndicator(frame: NSRect(x: 58, y: 15, width: 174, height: 10))
        bar.levelIndicatorStyle = .continuousCapacity
        bar.minValue = 0; bar.maxValue = 1; bar.warningValue = 2; bar.criticalValue = 3
        bar.doubleValue = muted ? 0 : Double(value)
        content.addSubview(bar)
        panel.contentView = content
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 125, y: frame.minY + 90))
        }
        panel.orderFrontRegardless()
        dismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            self?.panel?.orderOut(nil)
        }
    }

    func hide() { dismissal?.cancel(); panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 88),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityLabel("Output volume")
        self.panel = panel
        return panel
    }
}
