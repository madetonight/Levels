import AppKit
import Observation
import ServiceManagement
import SwiftUI

enum MixerLayout {
    static let width: CGFloat = 296
    static let height: CGFloat = 500
    static let tabsWidth: CGFloat = 190
    static let appSliderWidth: CGFloat = 170
    static let systemSliderWidth: CGFloat = 200
    static let levelWidth: CGFloat = 40
    static let actionWidth: CGFloat = 28
    static let controlGap: CGFloat = 4
    static let panelInset: CGFloat = 12

    @MainActor static var outputFont: NSFont { .systemFont(ofSize: 11, weight: .regular) }
    @MainActor static func outputButtonSize(title: String) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: outputFont]
        let titleWidth = ceil((title as NSString).size(withAttributes: attributes).width)
        // Native title insets plus disclosure arrow; keep the button snug.
        let chrome: CGFloat = 30
        let available = width - panelInset * 2 - actionWidth * 2 - controlGap * 3 - 10
        let buttonWidth = min(available, max(72, titleWidth + chrome))
        let textBounds = (title as NSString).boundingRect(
            with: CGSize(width: buttonWidth - chrome, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        return CGSize(width: buttonWidth, height: max(20, ceil(textBounds.height) + 6))
    }
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
    var settingsError: String?
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ObservationIgnored private var settingsWindow: NSWindow?
    @ObservationIgnored var onShowSettings: (() -> Void)?

    init(engine: MixerEngine, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        updates = AppUpdateController(defaults: defaults)
        appearance = MixerAppearance(rawValue: defaults.string(forKey: "LevelsMixerAppearance") ?? "") ?? .system
        surface = MixerSurface(rawValue: defaults.string(forKey: "LevelsMixerSurface") ?? "") ?? .mesh
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
        add("Settings…", to: menu, action: #selector(showSettings), key: ",")
        menu.addItem(.separator())
        let updatesMenu = NSMenu(title: "Updates")
        updatesMenu.autoenablesItems = false
        add("Check for Updates…", to: updatesMenu, action: #selector(checkForUpdates))
        updatesMenu.items.last?.isEnabled = updates.canCheckForUpdates
        if let version = updates.availableVersion {
            add("Install Levels \(version)…", to: updatesMenu, action: #selector(checkForUpdates))
        }
        add("Automatically check for updates", to: updatesMenu, action: #selector(toggleAutomaticUpdates), checked: updates.automaticallyChecks)
        if !updates.isConfigured {
            updatesMenu.addItem(.separator())
            let waiting = updatesMenu.addItem(withTitle: "Waiting for first published update", action: nil, keyEquivalent: "")
            waiting.isEnabled = false
        }
        let updatesItem = menu.addItem(withTitle: updates.hasUpdateAvailable ? "Updates · Available" : "Updates", action: nil, keyEquivalent: "")
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

    @objc func showSettings() {
        onShowSettings?()
        let window = prepareSettingsWindow()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    /// Creating the settings window does not show it; only showSettings does.
    func prepareSettingsWindow() -> NSWindow {
        if let settingsWindow { return settingsWindow }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Levels Settings"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.contentViewController = NSHostingController(rootView: settingsContent)
        window.setContentSize(NSSize(width: 480, height: 580))
        if !window.setFrameUsingName("LevelsSettingsWindow") { window.center() }
        window.setFrameAutosaveName("LevelsSettingsWindow")
        settingsWindow = window
        return window
    }

    var settingsContent: some View {
        LevelsSettingsView().environment(engine).environment(self)
    }

    @objc private func checkForUpdates() { updates.checkForUpdates() }
    @objc private func toggleAutomaticUpdates() { updates.setAutomaticChecks(!updates.automaticallyChecks) }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsError = nil
        } catch {
            settingsError = "Couldn’t change launch at login. Try again in System Settings."
        }
    }

    func confirmReset() {
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

/// Standard Mac preferences, opened on demand from either Options entry point.
private struct LevelsSettingsView: View {
    @Environment(MixerEngine.self) private var engine
    @Environment(MixerOptions.self) private var options

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { options.launchAtLogin },
                    set: { options.setLaunchAtLogin($0) }))
            }
            Section("Devices") {
                devicePicker(engine.deviceMonitor, title: "Output device")
                Toggle("Mute output", isOn: muteBinding(engine.systemVolume))
                    .disabled(!engine.isStarted || !engine.systemVolume.canMute)
                devicePicker(engine.inputDeviceMonitor, title: "Input device")
                Toggle("Mute microphone", isOn: muteBinding(engine.inputVolume))
                    .disabled(!engine.isStarted || !engine.inputVolume.canMute)
            }
            Section("Audio") {
                Toggle("Software volume for HDMI / DisplayPort", isOn: Binding(
                    get: { engine.systemVolume.softwareEnabled },
                    set: { engine.systemVolume.setSoftwareEnabled($0) }))
                Text("Use Levels to adjust fixed-volume monitor outputs. Levels must stay running.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Keep Mac microphone with Bluetooth", isOn: Binding(
                    get: { engine.keepMacMicrophone }, set: { engine.setKeepMacMicrophone($0) }))
                Text("Prefer the Mac microphone to avoid headset call mode. A selected USB microphone stays selected.")
                    .font(.caption).foregroundStyle(.secondary)
                if engine.volumeKeys.needsPermission {
                    Button("Enable volume keys…") { engine.volumeKeys.requestPermission() }
                    Text("Allow Levels in Accessibility to use volume keys with a fixed-volume monitor.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if engine.volumeKeys.unavailable {
                    Text("Volume keys are unavailable. The master slider still works.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("App volumes") {
                HStack {
                    Text("Default reset level")
                    Spacer()
                    Text("\(Int((engine.appResetLevel * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { Double(engine.appResetLevel) },
                    set: { engine.setAppResetLevel(Float($0)) }), in: 0...2, step: 0.01)
                    .accessibilityLabel("Default app reset level")
                Text("Each app's Reset button restores this level, keeping its mute and output. The default is 100%.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset all app volumes…") { options.confirmReset() }
                Text("Restore original app levels, mute states, and output routes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = options.settingsError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped).padding(12)
        .fontDesign(.default)
        .frame(width: 480, height: 580)
        .preferredColorScheme(options.appearance.colorScheme)
    }

    private func muteBinding(_ controller: SystemVolumeController) -> Binding<Bool> {
        Binding(get: { controller.isMuted }, set: { value in
            if value != controller.isMuted { controller.toggleMute() }
        })
    }

    private func devicePicker(_ monitor: AudioDeviceMonitor, title: String) -> some View {
        Picker(title, selection: Binding(get: { monitor.defaultDeviceID }, set: { id in
            guard let device = monitor.devices.first(where: { $0.id == id }) else { return }
            if monitor.direction == .input { engine.selectInput(device) }
            else { monitor.setDefault(device) }
        })) {
            if monitor.devices.isEmpty { Text("No device available").tag(monitor.defaultDeviceID) }
            ForEach(monitor.devices) { device in Text(device.name).tag(device.id) }
        }.disabled(!engine.isStarted || monitor.devices.isEmpty)
    }
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
        button.setAccessibilityLabel(options.updates.hasUpdateAvailable ? "Levels options, update available" : "Levels options")
        button.toolTip = options.updates.availableVersion.map { "Options · Levels \($0) update available" } ?? "Options"
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
    @State private var otherAppsExpanded = false
    private var appearance: MixerAppearance { options.appearance }
    private var surface: MixerSurface { options.surface }
    private var settingsError: String? { options.settingsError }

    #if RENDER_SHOTS
    init(renderTab: String = "Output", renderOtherAppsExpanded: Bool = false) {
        _tab = State(initialValue: MixerTab(rawValue: renderTab) ?? .outputs)
        _otherAppsExpanded = State(initialValue: renderOtherAppsExpanded)
    }
    #endif

    private var appSections: OutputAppSections {
        OutputAppSections(apps: engine.processMonitor.apps,
                          recentlyPlaying: engine.processMonitor.recentlyPlaying)
    }

    private var masterDeviceSymbol: String {
        guard tab == .outputs else { return "mic" }
        let monitor = engine.deviceMonitor
        guard let device = monitor.devices.first(where: { $0.id == monitor.defaultDeviceID }) else { return "hifispeaker" }
        if device.isBluetooth { return "headphones" }
        return DeviceSymbol.wired(transport: device.transport, dataSource: device.outputDataSource, direction: .output)
    }

    private var scheme: ColorScheme { appearance.colorScheme ?? systemScheme }
    private var palette: MixerPalette { MixerPalette(dark: scheme == .dark) }
    private var glassTint: Color { palette.dark ? Color.black.opacity(0.25) : .clear }

    var body: some View {
        decoratedPanel
            // SwiftUI's default system design uses San Francisco on macOS.
            .font(.system(size: 11.5, design: .default))
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
            header.padding(.bottom, 10)
            tabs.padding(.bottom, 12)
            systemCard.padding(.bottom, 10)
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
        .padding(.horizontal, MixerLayout.panelInset).padding(.top, 12).padding(.bottom, 10)
        .frame(width: MixerLayout.width, height: MixerLayout.height)
        .foregroundStyle(palette.text)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: 16, weight: .regular)).frame(width: 19)
                .accessibilityHidden(true)
            Text("Levels").font(.system(size: 19, weight: .semibold)).tracking(-0.8)
            Spacer()
            optionsMenu
        }
    }

    private var optionsMenu: some View {
        MixerOptionsButton(options: options, color: NSColor(palette.secondary))
            .frame(width: 28, height: 28)
            .overlay(alignment: .topTrailing) {
                if options.updates.hasUpdateAvailable {
                    Circle().fill(.white).frame(width: 5, height: 5)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.5))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }

    private var systemCard: some View {
        let controller = tab == .input ? engine.inputVolume : engine.systemVolume
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tab == .input ? "Microphone gain" : "Master volume")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(palette.secondary)
                    HStack(spacing: 9) {
                        Image(systemName: masterDeviceSymbol)
                            .font(.system(size: 15)).frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        Text(controller.deviceName.isEmpty ? "No device available" : controller.deviceName)
                            .font(.system(size: 11.5, weight: .medium, design: .default)).lineLimit(1)
                            .contextMenu {
                                Button(controller.isMuted ? "Unmute device" : "Mute device") { controller.toggleMute() }
                                    .disabled(!controller.canMute || !engine.isStarted)
                            }
                            .help("Device selection and mute controls are in Settings.")
                    }
                }
                Spacer(minLength: 4)
            }
            HStack(alignment: .center, spacing: 0) {
                MixerVolumeSlider(value: Binding(get: { controller.volume }, set: { controller.setVolume($0) }),
                                  palette: palette, label: tab == .input ? "Microphone gain" : "Master volume")
                    .frame(width: MixerLayout.systemSliderWidth)
                    .disabled(!controller.canSetVolume || !engine.isStarted)
                    .opacity(controller.isMuted ? 0.5 : 1)
                Text("\(Int((controller.volume * 100).rounded()))%")
                    .font(.system(size: 15, weight: .semibold, design: .default)).monospacedDigit()
                    .frame(width: MixerLayout.levelWidth, alignment: .trailing)
                    .foregroundStyle(controller.isMuted ? palette.secondary : palette.text)
                Color.clear.frame(width: MixerLayout.actionWidth + MixerLayout.controlGap, height: 20)
                    .accessibilityHidden(true)
            }
            if engine.isStarted, !controller.canSetVolume {
                Text("Volume is controlled on this device.")
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
            }
        }
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
                        .frame(maxWidth: .infinity).frame(height: 24)
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
        let sections = appSections
        return VStack(alignment: .leading, spacing: 8) {
            if engine.multiOutput.isActive {
                emptyState("Multiple outputs active", subtitle: "Per-app volume resumes when you return to a single output.", icon: "speaker.wave.2")
            } else if sections.primary.isEmpty && sections.other.isEmpty {
                emptyState("Ready when you press play",
                           subtitle: "Play music or a video. Its app will appear here.",
                           icon: "waveform")
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sections.primary, id: \.bundleID) { app in AppLevelRow(app: app, palette: palette) }
                        if !sections.other.isEmpty {
                            DisclosureGroup(isExpanded: $otherAppsExpanded) {
                                VStack(spacing: 4) {
                                    ForEach(sections.other, id: \.bundleID) { app in
                                        AppLevelRow(app: app, palette: palette)
                                    }
                                }.padding(.top, 4)
                            } label: {
                                Text("Other apps")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(palette.secondary)
                            }
                            .tint(palette.secondary)
                            .padding(.top, sections.primary.isEmpty ? 0 : 4)
                        }
                    }.padding(.vertical, 1)
                }.scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                }.scrollIndicators(.hidden).frame(maxHeight: .infinity)
            }
            if let error = monitor.selectionError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func deviceRows(_ monitor: AudioDeviceMonitor) -> some View {
        VStack(spacing: 6) {
            ForEach(monitor.devices) { device in
                Button {
                    if monitor.direction == .input { engine.selectInput(device) }
                    else { monitor.setDefault(device) }
                } label: {
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                HStack(alignment: .center, spacing: 8) {
                    Text(app.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                        .layoutPriority(1)
                    HStack(spacing: 5) {
                        Circle().fill(palette.fill.opacity(volume.isMuted ? 0.35 : 0.65)).frame(width: 4, height: 4)
                        Text(error != nil ? (engine.isRecovering(app.bundleID) ? "Reconnecting" : "Not applied") : (volume.isMuted ? "Muted" : (volume.volume == 0 ? "Silent" : (app.isPlaying ? "Playing" : "Idle"))))
                            .font(.system(size: 10)).foregroundStyle(error != nil ? Color.orange : palette.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 3)
            }
            HStack(spacing: MixerLayout.controlGap) {
                MixerVolumeSlider(value: Binding(get: { engine.volume(for: app).volume }, set: { engine.setVolume($0, for: app) }),
                                  palette: palette, label: "\(app.name) volume", maximum: VolumeTaper.maximumPosition)
                    .frame(width: MixerLayout.appSliderWidth)
                    .opacity(volume.isMuted ? 0.5 : 1)
                    .help("0–200%. Boost above 100% uses a peak limiter to prevent digital clipping.")
                Spacer(minLength: 4)
                Text("\(Int((volume.volume * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                    .frame(width: MixerLayout.levelWidth, alignment: .trailing)
                    .foregroundStyle(volume.volume > 1 ? Color.orange : palette.secondary)
                Color.clear.frame(width: MixerLayout.actionWidth, height: 20)
                    .accessibilityHidden(true)
            }
            HStack(spacing: MixerLayout.controlGap) {
                outputSelector.padding(.leading, 6)
                Spacer(minLength: 4)
                Button { engine.toggleMute(for: app) } label: {
                    Image(systemName: volume.isMuted ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 13)).frame(width: MixerLayout.actionWidth, height: 28)
                        .foregroundStyle(palette.secondary)
                        .background(volume.isMuted ? palette.button : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(volume.isMuted ? "Unmute" : "Mute") \(app.name)")
                    .help("\(volume.isMuted ? "Unmute" : "Mute") \(app.name)")
                Button { engine.resetLevel(for: app) } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.secondary)
                        .frame(width: MixerLayout.actionWidth, height: 28)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("Reset \(app.name) to \(Int((engine.appResetLevel * 100).rounded())) percent")
                    .help("Restore this app's level to \(Int((engine.appResetLevel * 100).rounded()))%. Mute and output stay unchanged.")
            }
            if let error, !engine.needsAudioCapturePermission {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .contextMenu {
            Button("Reset level to \(Int((engine.appResetLevel * 100).rounded()))%") { engine.resetLevel(for: app) }
            Button("Restore original volume and output") { engine.reset(app) }
        }
    }

    private var outputSelector: some View {
        let selectedUID = engine.routeUIDs(for: app).first ?? ""
        let devices = engine.deviceMonitor.devices
        let unavailable = !selectedUID.isEmpty && !devices.contains { $0.uid == selectedUID }
        let systemName = devices.first { $0.id == engine.deviceMonitor.defaultDeviceID }?.name ?? "System default"
        let selectedName = devices.first { $0.uid == selectedUID }?.name ?? systemName
        let outputDescription = unavailable ? "Selected device unavailable · using \(systemName)"
            : (selectedUID.isEmpty ? "System default · \(selectedName)" : selectedName)
        let size = MixerLayout.outputButtonSize(title: selectedName)
        return AppOutputButton(selection: Binding(
                get: { engine.routeUIDs(for: app).first ?? "" },
                set: { uid in
                    if uid.isEmpty { engine.setOutput(nil, for: app) }
                    else if let device = engine.deviceMonitor.devices.first(where: { $0.uid == uid }) {
                        engine.setOutput(device, for: app)
                    }
                }
            ), devices: devices, systemName: systemName, title: selectedName,
            label: "Output for \(app.name)", detail: outputDescription)
        .frame(width: size.width, height: size.height)
        .background(palette.button.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.line.opacity(0.7), lineWidth: 0.5))
        .disabled(!engine.isStarted)
        .accessibilityLabel("Output for \(app.name), \(outputDescription)")
        .help("\(outputDescription). Choose where \(app.name) plays.")
    }
}

/// The space below the slider shows the selected device's name. The native
/// pull-down retains full menu names, checkmarks, keyboard navigation and focus.
private struct AppOutputButton: NSViewRepresentable {
    @Binding var selection: String
    let devices: [AudioDevice]
    let systemName: String
    let title: String
    let label: String
    let detail: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.controlSize = .mini
        button.font = MixerLayout.outputFont
        button.bezelStyle = .rounded
        // The system's rounded bezel keeps a large glass silhouette even for
        // mini controls. SwiftUI supplies a thin, fixed-height button surface;
        // AppKit still owns the popup menu, selection, focus and keyboard input.
        button.isBordered = false
        button.focusRingType = .exterior
        button.cell?.usesSingleLineMode = false
        button.cell?.wraps = true
        button.cell?.lineBreakMode = .byWordWrapping
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        var choices = [("", "\(systemName) · System default")]
        choices += devices.map { ($0.uid, $0.name) }
        if !selection.isEmpty && !devices.contains(where: { $0.uid == selection }) {
            choices.append((selection, "Unavailable · using \(systemName)"))
        }
        let previous = button.itemArray.dropFirst().map { (($0.representedObject as? String) ?? "", $0.title) }
        if previous.count != choices.count || zip(previous, choices).contains(where: { $0.0 != $1.0 || $0.1 != $1.1 }) {
            button.removeAllItems()
            // The first item labels the button and stays out of its menu.
            // NSPopUpButton's addItem removes an existing equal title. Build
            // with a distinct header before assigning the selected name.
            button.addItem(withTitle: "Output")
            for (uid, name) in choices {
                button.addItem(withTitle: name)
                button.lastItem?.representedObject = uid
            }
        }
        if button.item(at: 0)?.title != title { button.item(at: 0)?.title = title }
        if button.indexOfSelectedItem != 0 { button.selectItem(at: 0) }
        for item in button.itemArray {
            let state: NSControl.StateValue = (item.representedObject as? String) == selection ? .on : .off
            if item.state != state { item.state = state }
        }
        button.isEnabled = isEnabled
        button.toolTip = detail
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(detail)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSPopUpButton, context: Context) -> CGSize? {
        MixerLayout.outputButtonSize(title: title)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: AppOutputButton
        init(_ parent: AppOutputButton) { self.parent = parent }
        @objc func changed(_ button: NSPopUpButton) {
            guard let uid = button.selectedItem?.representedObject as? String else { return }
            parent.selection = uid
        }
    }
}

/// A native NSSlider retains tracking, keyboard increments and VoiceOver;
/// its cell draws only the approved sage track and mint thumb.
private struct MixerVolumeSlider: NSViewRepresentable {
    @Binding var value: Float
    let palette: MixerPalette
    let label: String
    var maximum: Float = 1
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: 0, maxValue: Double(maximum),
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.cell = SageSliderCell()
        slider.minValue = 0
        slider.maxValue = Double(maximum)
        slider.altIncrementValue = 0.01
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.focusRingType = .exterior
        slider.setAccessibilityLabel(label)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.maxValue = Double(maximum)
        if slider.floatValue != value { slider.floatValue = value }
        if slider.isEnabled != isEnabled { slider.isEnabled = isEnabled }
        slider.setAccessibilityLabel(label)
        slider.setAccessibilityValueDescription("\(Int((value * 100).rounded())) percent\(value > 1 ? ", boost with limiter" : "")")
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
        @objc func changed(_ slider: NSSlider) {
            let value = slider.floatValue
            parent.value = parent.maximum > 1 && abs(value - 1) < 0.015 ? 1 : value
        }
    }
    final class SageSliderCell: NSSliderCell {
        var track = NSColor.gray
        var fill = NSColor.labelColor
        var thumb = NSColor.white
        override func drawBar(inside rect: NSRect, flipped: Bool) {
            let bar = NSRect(x: rect.minX + 6, y: rect.midY - 1.59, width: max(0, rect.width - 12), height: 3.18)
            (isEnabled ? track : track.withAlphaComponent(0.12)).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.59, yRadius: 1.59).fill()
            let progress = CGFloat((doubleValue - minValue) / max(0.001, maxValue - minValue))
            let filled = NSRect(x: bar.minX, y: bar.minY, width: bar.width * min(1, max(0, progress)), height: bar.height)
            (isEnabled ? fill : fill.withAlphaComponent(0.35)).setFill()
            NSBezierPath(roundedRect: filled, xRadius: 1.59, yRadius: 1.59).fill()
            if maxValue > 1 {
                let unityX = bar.minX + bar.width * CGFloat((1 - minValue) / (maxValue - minValue))
                if doubleValue > 1 {
                    NSColor.systemOrange.withAlphaComponent(isEnabled ? 1 : 0.35).setFill()
                    NSBezierPath(roundedRect: NSRect(x: unityX, y: bar.minY,
                        width: max(0, filled.maxX - unityX), height: bar.height), xRadius: 1.59, yRadius: 1.59).fill()
                }
                fill.withAlphaComponent(0.65).setFill()
                NSBezierPath(rect: NSRect(x: unityX - 0.5, y: bar.minY - 2, width: 1, height: 7)).fill()
            }
        }
        override func knobRect(flipped: Bool) -> NSRect {
            let native = super.knobRect(flipped: flipped)
            return NSRect(x: native.midX - 6.36, y: native.midY - 6.36, width: 12.72, height: 12.72)
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
