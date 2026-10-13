import AppKit
import Observation
import ServiceManagement
import SwiftUI

enum MixerLayout {
    static let width: CGFloat = 320
    static let height: CGFloat = 560
    static let tabsWidth: CGFloat = 200
}

private enum MixerTab: String, CaseIterable {
    case outputs = "Output", input = "Input"
}

private enum MixerAppearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private enum MixerSurface: String, CaseIterable {
    case mesh = "Sage mesh", glass = "Transparent Liquid Glass"
    // Preserve stored values while using simpler names in the interface.
    var title: String { self == .mesh ? "Solid" : "Liquid Glass" }
}

/// Both menu entry points use this controller and the same native menu builder.
@MainActor @Observable
final class MixerOptions: NSObject {
    private let engine: MixerEngine
    private let defaults: UserDefaults
    let updates: AppUpdateController
    fileprivate var appearance: MixerAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "LevelsMixerAppearance") }
    }
    fileprivate var surface: MixerSurface {
        didSet { defaults.set(surface.rawValue, forKey: "LevelsMixerSurface") }
    }
    var showIdleApps: Bool {
        didSet { defaults.set(showIdleApps, forKey: "LevelsShowInactiveAudioApps") }
    }
    var settingsError: String?

    init(engine: MixerEngine, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        updates = AppUpdateController(defaults: defaults)
        appearance = MixerAppearance(rawValue: defaults.string(forKey: "LevelsMixerAppearance") ?? "") ?? .system
        surface = MixerSurface(rawValue: defaults.string(forKey: "LevelsMixerSurface") ?? "") ?? .mesh
        showIdleApps = defaults.bool(forKey: "LevelsShowInactiveAudioApps")
        super.init()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Levels options")
        menu.autoenablesItems = false
        let appearances = NSMenu(title: "Appearance")
        // Existing System preferences continue following macOS until a color
        // is selected. The visible menu contains only the four requested choices.
        let selectedColor: MixerAppearance = appearance == .system
            ? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
            : appearance
        for choice in [MixerAppearance.dark, .light] {
            add(choice.rawValue, to: appearances, action: #selector(selectAppearance),
                checked: choice == selectedColor, value: choice.rawValue)
        }
        appearances.addItem(.separator())
        for choice in MixerSurface.allCases {
            add(choice.title, to: appearances, action: #selector(selectSurface),
                checked: choice == surface, value: choice.rawValue)
        }
        let appearanceItem = menu.addItem(withTitle: "Appearance", action: nil, keyEquivalent: "")
        appearanceItem.submenu = appearances
        menu.addItem(.separator())
        add("Launch at login", to: menu, action: #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled)
        add("Show inactive audio apps", to: menu, action: #selector(toggleInactiveApps), checked: showIdleApps)
        menu.addItem(.separator())
        add("Reset all app volumes…", to: menu, action: #selector(confirmReset))
        let updatesMenu = NSMenu(title: "Updates")
        updatesMenu.autoenablesItems = false
        add("Check for Updates…", to: updatesMenu, action: #selector(checkForUpdates))
        updatesMenu.items.last?.isEnabled = updates.canCheckForUpdates
        add("Automatically check for updates", to: updatesMenu, action: #selector(toggleAutomaticUpdates), checked: updates.automaticallyChecks)
        if !updates.isConfigured {
            updatesMenu.addItem(.separator())
            let waiting = updatesMenu.addItem(withTitle: "Waiting for first published update", action: nil, keyEquivalent: "")
            waiting.isEnabled = false
        }
        let updatesItem = menu.addItem(withTitle: "Updates", action: nil, keyEquivalent: "")
        updatesItem.submenu = updatesMenu
        add("About Levels", to: menu, action: #selector(showAbout))
        menu.addItem(.separator())
        add("Quit Levels", to: menu, action: #selector(quit), key: "q")
        return menu
    }

    private func add(_ title: String, to menu: NSMenu, action: Selector, checked: Bool = false,
                     value: String? = nil, key: String = "") {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = checked ? .on : .off
        item.representedObject = value
    }

    @objc private func selectAppearance(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String, let choice = MixerAppearance(rawValue: value) else { return }
        appearance = choice
    }

    @objc private func selectSurface(_ item: NSMenuItem) {
        guard let value = item.representedObject as? String, let choice = MixerSurface(rawValue: value) else { return }
        surface = choice
    }

    @objc private func toggleInactiveApps() { showIdleApps.toggle() }
    @objc private func checkForUpdates() { updates.checkForUpdates() }
    @objc private func toggleAutomaticUpdates() { updates.setAutomaticChecks(!updates.automaticallyChecks) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            settingsError = nil
        } catch {
            settingsError = "Couldn’t change launch at login. Try again in System Settings."
        }
    }

    @objc private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset all app volumes?"
        alert.informativeText = "Apps will return to their original volume. Muted apps may become audible."
        alert.addButton(withTitle: "Reset volumes")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { engine.resetAllVolumes() }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        alert.messageText = version.isEmpty ? "Levels" : "Levels · \(version)"
        alert.informativeText = "An open-source audio engine volume mixer designed for you.\n\nBuilt by heyjoseluna.\nInspired by Ahmed Gagan.\n\nAudio is processed locally and is never saved or uploaded."
        alert.addButton(withTitle: "Done")
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

private struct MixerOptionsButton: NSViewRepresentable {
    let options: MixerOptions
    let color: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(options: options) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Levels options")!,
                              target: context.coordinator, action: #selector(Coordinator.showMenu))
        button.isBordered = false
        button.image?.isTemplate = true
        button.image = button.image?.withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        button.setAccessibilityLabel("Levels options")
        button.toolTip = "Options"
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.options = options
        button.contentTintColor = color
    }

    @MainActor final class Coordinator: NSObject {
        var options: MixerOptions
        init(options: MixerOptions) { self.options = options }
        @objc func showMenu(_ button: NSButton) {
            options.makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        }
    }
}

/// The approved mint/sage scale; dark uses the same 950 tone mixed with black.
private struct MixerPalette {
    let dark: Bool
    var base: Color { Color(hex: dark ? 0x171D1A : 0xF8FCFA) }
    var text: Color { Color(hex: dark ? 0xFDFFFE : 0x3D4B45) }
    var secondary: Color { Color(hex: dark ? 0xCEDCD6 : 0x3D4B45) }
    var fill: Color { Color(hex: dark ? 0xB2C6BD : 0x3D4B45) }
    var track: Color { Color(hex: dark ? 0xE1ECE7 : 0x3D4B45).opacity(dark ? 0.18 : 0.15) }
    var line: Color { Color(hex: dark ? 0xE1ECE7 : 0x3D4B45).opacity(dark ? 0.17 : 0.15) }
    var button: Color { Color(hex: 0xE1ECE7).opacity(dark ? 0.11 : 0.60) }
    var thumb: Color { Color(hex: dark ? 0xEFFFFB : 0xFDFFFE) }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct MixerView: View {
    @Environment(MixerEngine.self) private var engine
    @Environment(MixerOptions.self) private var options
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var tabSelection
    @State private var tab: MixerTab = .outputs
    private var appearance: MixerAppearance { options.appearance }
    private var surface: MixerSurface { options.surface }
    private var settingsError: String? { options.settingsError }

    #if RENDER_SHOTS
    init(renderTab: String = "Output") {
        _tab = State(initialValue: MixerTab(rawValue: renderTab) ?? .outputs)
    }
    #endif

    private var apps: [AudioApp] {
        engine.processMonitor.apps.filter {
            options.showIdleApps || $0.isPlaying || !engine.volume(for: $0).isNeutral
        }.sorted { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var scheme: ColorScheme { appearance.colorScheme ?? systemScheme }
    private var palette: MixerPalette { MixerPalette(dark: scheme == .dark) }
    private var glassTint: Color { palette.dark ? Color.black.opacity(0.25) : .clear }

    var body: some View {
        decoratedPanel
            // SwiftUI's default system design uses San Francisco on macOS.
            .font(.system(size: 12, design: .default))
            .fontDesign(.default)
            .tint(palette.fill)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(appearance.colorScheme)
    }

    private var decoratedPanel: some View {
        Group {
            if surface == .glass, !reduceTransparency {
                if #available(macOS 26.0, *) {
                    panel.background(glassTint)
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    panel.background {
                        ZStack {
                            MixerVisualEffectBackground()
                            glassTint
                        }
                    }
                }
            } else {
                panel.background(MixerMeshBackground(palette: palette, reduceTransparency: reduceTransparency))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(LinearGradient(colors: [
                    Color.white.opacity(palette.dark ? 0.42 : 0.90),
                    palette.fill.opacity(0.10),
                    Color.white.opacity(palette.dark ? 0.10 : 0.30),
                    palette.fill.opacity(0.28)
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header.padding(.bottom, 14)
            tabs.padding(.bottom, 16)
            systemCard.padding(.bottom, 14)
            Rectangle().fill(palette.line).frame(height: 1).padding(.bottom, 12)
            Group {
                if !engine.isStarted {
                    emptyState("Connecting to audio", subtitle: "Waiting for the Mac’s audio system…", icon: "waveform")
                } else {
                    switch tab {
                    case .outputs: outputControls
                    case .input: microphoneControls
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if engine.needsAudioCapturePermission {
                permissionCard.padding(.top, 12)
            }
            if let error = settingsError {
                Text(error).font(.caption).foregroundStyle(.red).padding(.top, 8)
            }
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 14)
        .frame(width: MixerLayout.width, height: MixerLayout.height)
        .foregroundStyle(palette.text)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 17, weight: .regular)).frame(width: 20)
                .accessibilityHidden(true)
            Text("Levels").font(.system(size: 20, weight: .semibold)).tracking(-0.8)
            Spacer()
            optionsMenu
        }
    }

    private var optionsMenu: some View {
        MixerOptionsButton(options: options, color: NSColor(palette.secondary))
            .frame(width: 28, height: 28)
    }

    private var systemCard: some View {
        let controller = tab == .input ? engine.inputVolume : engine.systemVolume
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle(tab == .input ? "MICROPHONE GAIN" : "MASTER VOLUME")
                    HStack(spacing: 8) {
                        Image(systemName: tab == .input ? "mic" : "hifispeaker")
                            .font(.system(size: 15)).accessibilityHidden(true)
                        if tab == .outputs {
                            masterOutputSelector
                        } else {
                            Text(controller.deviceName.isEmpty ? "No device available" : controller.deviceName)
                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int((controller.volume * 100).rounded()))")
                        .font(.system(size: 26, weight: .semibold)).tracking(-1.1)
                    Text("%").font(.system(size: 12))
                }.monospacedDigit().foregroundStyle(controller.isMuted ? palette.secondary : palette.text)
            }
            HStack(spacing: 10) {
                Button { controller.toggleMute() } label: {
                    Image(systemName: tab == .input
                          ? (controller.isMuted ? "mic.slash" : "mic")
                          : (controller.isMuted ? "speaker.slash" : "speaker.wave.1"))
                        .font(.system(size: 16)).frame(width: 26, height: 26)
                        .background(controller.isMuted ? palette.button : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain).foregroundStyle(palette.secondary)
                .disabled(!controller.canMute || !engine.isStarted)
                .accessibilityLabel(controller.isMuted ? "Unmute device" : "Mute device")
                MixerVolumeSlider(value: Binding(get: { controller.volume }, set: { controller.setVolume($0) }),
                                  palette: palette, label: tab == .input ? "Microphone gain" : "Master volume")
                    .disabled(!controller.canSetVolume || !engine.isStarted)
                    .opacity(controller.isMuted ? 0.5 : 1)
                Image(systemName: tab == .input ? "mic" : "speaker.wave.3")
                    .font(.system(size: 16)).foregroundStyle(palette.secondary).accessibilityHidden(true)
            }
            if engine.isStarted, !controller.canSetVolume {
                Text("Volume is controlled on this device.")
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
            }
        }
    }

    private var masterOutputSelector: some View {
        let monitor = engine.deviceMonitor
        return Menu {
            Picker("Output device", selection: Binding(
                get: { monitor.defaultDeviceID },
                set: { id in
                    if let device = monitor.devices.first(where: { $0.id == id }) {
                        monitor.setDefault(device)
                    }
                }
            )) {
                ForEach(monitor.devices) { device in
                    Text(device.name).tag(device.id)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(engine.systemVolume.deviceName.isEmpty ? "No device available" : engine.systemVolume.deviceName)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .foregroundStyle(palette.text)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .disabled(!engine.isStarted || monitor.devices.isEmpty)
        .accessibilityLabel("Master output device")
        .help("Choose the Mac’s default output device")
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(MixerTab.allCases, id: \.self) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 11, weight: tab == item ? .semibold : .medium))
                        .foregroundStyle(tab == item ? palette.text : palette.secondary)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background {
                            if tab == item {
                                Capsule()
                                    .fill(LinearGradient(colors: selectedTabColors,
                                                         startPoint: .top, endPoint: .bottom))
                                    .overlay(Capsule().stroke(Color.white.opacity(palette.dark ? 0.24 : 0.55), lineWidth: 0.7))
                                    .shadow(color: Color.black.opacity(palette.dark ? 0.14 : 0.07), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "selectedMixerTab", in: tabSelection)
                            }
                        }
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
                .accessibilityLabel("\(item.rawValue) section")
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(width: MixerLayout.tabsWidth)
        .modifier(MixerTabGlass(useGlass: surface == .glass, reduceTransparency: reduceTransparency,
                               solidColor: Color(hex: palette.dark ? 0x3D4B45 : 0xE1ECE7), tint: glassTint))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(palette.line, lineWidth: 1))
        .overlay(Capsule().stroke(LinearGradient(colors: [Color.white.opacity(palette.dark ? 0.12 : 0.8), .clear],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 1).padding(1))
        .onMoveCommand { direction in
            let cases = MixerTab.allCases
            guard let index = cases.firstIndex(of: tab) else { return }
            if direction == .left { tab = cases[(index + cases.count - 1) % cases.count] }
            if direction == .right { tab = cases[(index + 1) % cases.count] }
        }
    }

    private var selectedTabColors: [Color] {
        if surface == .glass, !reduceTransparency {
            return palette.dark
                ? [Color.white.opacity(0.16), Color.white.opacity(0.06)]
                : [Color.white.opacity(0.30), Color.white.opacity(0.10)]
        }
        return palette.dark
            ? [Color(hex: 0x72817B), Color(hex: 0x56635D)]
            : [Color(hex: 0xFDFFFE), Color(hex: 0xEEF7F3)]
    }

    private var outputControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = engine.deviceMonitor.selectionError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            appControls
        }
    }

    private var appControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("APPS")
                Spacer()
                Text("\(apps.count) \(apps.count == 1 ? "app" : "apps")")
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
            }
            if engine.multiOutput.isActive {
                emptyState("Multiple outputs active", subtitle: "Per-app volume resumes when you return to a single output.", icon: "speaker.wave.2")
            } else if apps.isEmpty {
                emptyState("Ready when you press play",
                           subtitle: "Play music or a video. Its app will appear here.",
                           icon: "waveform")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(apps, id: \.bundleID) { app in AppLevelRow(app: app, palette: palette) }
                    }.padding(.vertical, 1)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func deviceList(_ monitor: AudioDeviceMonitor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(monitor.direction == .input ? "INPUT DEVICES" : "OUTPUT DEVICES")
            if monitor.devices.isEmpty {
                emptyState("No devices available", subtitle: "Connect a speaker, headphones, or an audio device.", icon: "speaker.slash")
            } else {
                ScrollView {
                    deviceRows(monitor)
                }.frame(maxHeight: .infinity)
            }
            if let error = monitor.selectionError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func deviceRows(_ monitor: AudioDeviceMonitor) -> some View {
        VStack(spacing: 6) {
            ForEach(monitor.devices) { device in
                Button { monitor.setDefault(device) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: device.isBluetooth ? "headphones" : (monitor.direction == .input ? "mic.fill" : "speaker.wave.2.fill"))
                            .foregroundStyle(palette.fill).frame(width: 26)
                        Text(device.name).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        if monitor.defaultDeviceID == device.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.fill)
                        }
                    }
                    .padding(12).contentShape(Rectangle())
                    .background(monitor.defaultDeviceID == device.id ? palette.fill.opacity(0.08) : palette.button.opacity(0.25),
                                in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                .accessibilityLabel("\(device.name)\(monitor.defaultDeviceID == device.id ? ", selected" : "")")
            }
        }
    }

    private var microphoneControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            deviceList(engine.inputDeviceMonitor)
            let recording = engine.processMonitor.apps.filter(\.isRecording)
            if !recording.isEmpty {
                sectionTitle("USING THE MICROPHONE")
                ForEach(recording, id: \.bundleID) { app in
                    Label(app.name, systemImage: "mic.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Allow system audio access", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
            Text("Enable Levels in Privacy & Security → Screen & System Audio Recording, then retry.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Retry") { engine.retryAudioAccess() }
            }.controlSize(.small)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).tracking(1.1).foregroundStyle(palette.secondary)
    }

    private func emptyState(_ title: String, subtitle: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26, weight: .light)).foregroundStyle(palette.fill.opacity(0.65))
            Text(title).font(.system(size: 13, weight: .medium))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.horizontal, 15).padding(.vertical, 24)
    }

}

/// One native clear-glass surface for the entire tab bar. The selection is a
/// translucent highlight so it doesn't introduce another live blur layer.
private struct MixerTabGlass: ViewModifier {
    let useGlass: Bool
    let reduceTransparency: Bool
    let solidColor: Color
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if !useGlass || reduceTransparency {
            content.background(solidColor, in: Capsule())
        } else if #available(macOS 26.0, *) {
            content.background(tint, in: Capsule())
                .glassEffect(.clear, in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .background(tint, in: Capsule())
        }
    }
}

private struct AppLevelRow: View {
    @Environment(MixerEngine.self) private var engine
    let app: AudioApp
    let palette: MixerPalette

    var body: some View {
        let volume = engine.volume(for: app)
        let error = engine.tapErrors[app.bundleID]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(palette.fill.opacity(volume.isMuted ? 0.35 : 0.65)).frame(width: 4, height: 4)
                        Text(error != nil ? "Not applied · retry or reset" : (volume.isMuted ? "Muted" : (app.isPlaying ? "Playing" : "Idle · level remembered")))
                            .font(.system(size: 10)).foregroundStyle(error != nil ? Color.orange : palette.secondary)
                    }
                }
                Spacer(minLength: 3)
                Text("\(Int((volume.volume * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(palette.secondary)
                Button { engine.toggleMute(for: app) } label: {
                    Image(systemName: volume.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 13)).frame(width: 24, height: 24)
                        .foregroundStyle(palette.secondary)
                        .background(volume.isMuted ? palette.button : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                .accessibilityLabel("\(volume.isMuted ? "Unmute" : "Mute") \(app.name)")
            }
            MixerVolumeSlider(value: Binding(get: { engine.volume(for: app).volume }, set: { engine.setVolume($0, for: app) }),
                              palette: palette, label: "\(app.name) volume")
                .padding(.leading, 33).opacity(volume.isMuted ? 0.5 : 1)
            outputSelector.padding(.leading, 33)
            if let error, !engine.needsAudioCapturePermission {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
            }
            Rectangle().fill(palette.line).frame(height: 1).padding(.top, 6)
        }
         .padding(.top, 10)
        .contextMenu {
            Button("Reset \(app.name) to 100%") { engine.reset(app) }
        }
    }

    private var outputSelector: some View {
        let selectedUID = engine.routeUIDs(for: app).first ?? ""
        let devices = engine.deviceMonitor.devices
        let unavailable = !selectedUID.isEmpty && !devices.contains { $0.uid == selectedUID }
        return HStack(spacing: 5) {
            Picker("Output for \(app.name)", selection: Binding(
                get: { engine.routeUIDs(for: app).first ?? "" },
                set: { uid in
                    if uid.isEmpty { engine.setOutput(nil, for: app) }
                    else if let device = engine.deviceMonitor.devices.first(where: { $0.uid == uid }) {
                        engine.setOutput(device, for: app)
                    }
                }
            )) {
                Text("System default").tag("")
                ForEach(devices, id: \.uid) { device in
                    Text(device.name).tag(device.uid)
                }
                if unavailable {
                    Text("Unavailable · using system output").tag(selectedUID)
                }
            }
            .pickerStyle(.menu).labelsHidden().controlSize(.mini)
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!engine.isStarted)
            .accessibilityLabel("Output for \(app.name)")
            .help("Choose where \(app.name) plays. Other apps keep their own output.")
        }
    }
}

/// A native NSSlider retains tracking, keyboard increments and VoiceOver;
/// its cell draws only the approved sage track and mint thumb.
private struct MixerVolumeSlider: NSViewRepresentable {
    @Binding var value: Float
    let palette: MixerPalette
    let label: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: 0, maxValue: 1,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.cell = SageSliderCell()
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.focusRingType = .exterior
        slider.setAccessibilityLabel(label)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        if slider.floatValue != value { slider.floatValue = value }
        if slider.isEnabled != isEnabled { slider.isEnabled = isEnabled }
        slider.setAccessibilityLabel(label)
        if let cell = slider.cell as? SageSliderCell {
            let track = NSColor(palette.track), fill = NSColor(palette.fill), thumb = NSColor(palette.thumb)
            if cell.track != track || cell.fill != fill || cell.thumb != thumb {
                cell.track = track
                cell.fill = fill
                cell.thumb = thumb
                slider.needsDisplay = true
            }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSlider, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 180, height: 20)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: MixerVolumeSlider
        init(_ parent: MixerVolumeSlider) { self.parent = parent }
        @objc func changed(_ slider: NSSlider) { parent.value = slider.floatValue }
    }
    final class SageSliderCell: NSSliderCell {
        var track = NSColor.gray
        var fill = NSColor.labelColor
        var thumb = NSColor.white
        override func drawBar(inside rect: NSRect, flipped: Bool) {
            let bar = NSRect(x: rect.minX + 8, y: rect.midY - 2.5, width: max(0, rect.width - 16), height: 5)
            (isEnabled ? track : track.withAlphaComponent(0.12)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2.5, yRadius: 2.5).fill()
            let progress = CGFloat((doubleValue - minValue) / max(0.001, maxValue - minValue))
            let filled = NSRect(x: bar.minX, y: bar.minY, width: bar.width * min(1, max(0, progress)), height: bar.height)
            (isEnabled ? fill : fill.withAlphaComponent(0.35)).setFill()
            NSBezierPath(roundedRect: filled, xRadius: 2.5, yRadius: 2.5).fill()
        }
        override func knobRect(flipped: Bool) -> NSRect {
            let native = super.knobRect(flipped: flipped)
            return NSRect(x: native.midX - 8, y: native.midY - 8, width: 16, height: 16)
        }
        override func drawKnob(_ rect: NSRect) {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            (isEnabled ? thumb : thumb.withAlphaComponent(0.55)).setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

private struct MixerMeshBackground: View {
    let palette: MixerPalette
    let reduceTransparency: Bool

    var body: some View {
        ZStack {
            palette.base
            if !reduceTransparency {
                Image(palette.dark ? "MixerMeshDark" : "MixerMeshLight")
                    .resizable().interpolation(.high)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct MixerVisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
