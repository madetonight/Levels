// Compiled only by render-ui.sh, never included in the application target.
import AppKit
import CoreAudio
import SwiftUI

@main
@MainActor
enum RenderHarness {
    static let isActive = true
    static func demoIcon(forBundleID bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let probePath = Bundle.main.object(forInfoDictionaryKey: "LevelsPlaybackProbe") as? String
        let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
            : (Bundle.main.object(forInfoDictionaryKey: "LevelsProbeOutput") as? String ?? "/private/tmp/LevelsNativeRender")
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if probePath != nil || (CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "--probe-playback") {
            application.setActivationPolicy(.accessory)
            Task { @MainActor in
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: probePath ?? CommandLine.arguments[3])
            let monitor = AudioProcessMonitor()
            monitor.start()
            monitor.setMeteringVisible(true)
            try probe.run()
            let start = ProcessInfo.processInfo.systemUptime
            var observed: [[String: Any]] = []
            while ProcessInfo.processInfo.systemUptime - start < 10 {
                try await Task.sleep(for: .milliseconds(200))
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                print("Probe tick", elapsed, monitor.apps.map { "\($0.name):\($0.isPlaying):\($0.isPlaybackMeasured)" }, monitor.activityDiagnostics)
                fflush(stdout)
                if let app = monitor.apps.first(where: { $0.bundleID == "com.joseluna.levels.playback-probe" }) {
                    observed.append(["seconds": elapsed, "playing": app.isPlaying, "measured": app.isPlaybackMeasured,
                        "objects": app.objectIDs, "recent": monitor.recentlyPlaying.contains(app.bundleID), "diagnostics": monitor.activityDiagnostics])
                }
            }
            monitor.setMeteringVisible(false)
            probe.waitUntilExit()
            try JSONSerialization.data(withJSONObject: observed, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("live-playback.json"))
            let tone = observed.filter { let t = $0["seconds"] as! Double; return t > 2 && t < 3.5 }
            let silence = observed.filter { let t = $0["seconds"] as! Double; return t > 5 && t < 6.5 }
            let resumed = observed.filter { ($0["seconds"] as! Double) > 8 }
            let playing: ([String: Any]) -> Bool = { $0["playing"] as! Bool && $0["measured"] as! Bool }
            let passed = !tone.isEmpty && tone.allSatisfy(playing)
                && !silence.isEmpty && silence.allSatisfy { !($0["playing"] as! Bool) && ($0["measured"] as! Bool) }
                && !resumed.isEmpty && resumed.allSatisfy(playing)
            try "Live Core Audio playback: \(passed ? "passed" : "FAILED")\n".write(to: output.appendingPathComponent("live-result.txt"), atomically: true, encoding: .utf8)
            print("Live Core Audio playback: tone → silence on running stream → resumed tone", passed)
            NSApp.terminate(nil)
            }
            application.run()
            return
        }
        // Exercise menu actions against an isolated preference domain, never
        // the real app's settings, login registration, or audio controls.
        let checkDomain = "com.joseluna.levels-render.options-check.\(UUID().uuidString)"
        let checkDefaults = UserDefaults(suiteName: checkDomain)!
        let engine = MixerEngine(defaults: checkDefaults)
        let checkOptions = MixerOptions(engine: engine, defaults: checkDefaults)
        let firstMenu = checkOptions.makeMenu()
        let appearanceChoices = firstMenu.items.first { $0.title == "Appearance" }!.submenu!
        let darkIndex = appearanceChoices.items.firstIndex { $0.title == "Dark" }!
        appearanceChoices.performActionForItem(at: darkIndex)
        precondition(appearanceChoices.items.map(\.title) == ["Dark", "Light", "", "Solid", "Liquid Glass"])
        precondition(appearanceChoices.items[2].isSeparatorItem)
        precondition(firstMenu.items.allSatisfy { $0.title != "Surface" })
        precondition(firstMenu.items.map(\.title) == ["Appearance", "", "Settings…", "", "Updates", "About Levels", "", "Quit Levels"])
        let settingsItem = firstMenu.items.first { $0.title == "Settings…" }!
        precondition(settingsItem.target === checkOptions && settingsItem.action == #selector(MixerOptions.showSettings))
        precondition(settingsItem.keyEquivalent == ",")
        let settingsWindow = checkOptions.prepareSettingsWindow()
        precondition(!settingsWindow.isVisible && settingsWindow.title == "Levels Settings")
        precondition(checkOptions.prepareSettingsWindow() === settingsWindow)
        precondition(!settingsWindow.isReleasedWhenClosed)
        precondition(!checkOptions.showIdleApps)
        checkOptions.showIdleApps = true
        precondition(checkDefaults.bool(forKey: "LevelsShowInactiveAudioApps"))
        precondition(MixerOptions(engine: engine, defaults: checkDefaults).showIdleApps)
        checkOptions.showIdleApps = false
        let surfaceChoices = appearanceChoices
        surfaceChoices.performActionForItem(at: surfaceChoices.items.firstIndex { $0.title == "Liquid Glass" }!)
        let secondMenu = checkOptions.makeMenu()
        precondition(secondMenu.items.first { $0.title == "Appearance" }!.submenu!.items.first { $0.title == "Dark" }!.state == .on)
        precondition(secondMenu.items.first { $0.title == "Appearance" }!.submenu!.items.first { $0.title == "Liquid Glass" }!.state == .on)
        precondition(checkDefaults.string(forKey: "LevelsMixerAppearance") == "Dark")
        precondition(checkDefaults.string(forKey: "LevelsMixerSurface") == "Transparent Liquid Glass")
        let newSurfaces = secondMenu.items.first { $0.title == "Appearance" }!.submenu!
        newSurfaces.performActionForItem(at: newSurfaces.items.firstIndex { $0.title == "Solid" }!)
        let solidMenu = checkOptions.makeMenu()
        precondition(solidMenu.items.first { $0.title == "Appearance" }!.submenu!.items.first { $0.title == "Solid" }!.state == .on)
        precondition(solidMenu.items.first { $0.title == "Appearance" }!.submenu!.items.first { $0.title == "Dark" }!.state == .on)
        precondition(checkDefaults.string(forKey: "LevelsMixerSurface") == "Sage mesh")
        let updateIndex = solidMenu.items.firstIndex { $0.title == "Updates" }!
        precondition(solidMenu.items[updateIndex + 1].title == "About Levels")
        let updatesMenu = solidMenu.items[updateIndex].submenu!
        precondition(updatesMenu.items.contains { $0.title == "Check for Updates…" })
        updatesMenu.performActionForItem(at: updatesMenu.items.firstIndex { $0.title == "Automatically check for updates" }!)
        precondition(checkOptions.makeMenu().items.first { $0.title == "Updates" }!.submenu!.items.first { $0.title == "Automatically check for updates" }!.state == .on)
        precondition(checkDefaults.bool(forKey: "SUEnableAutomaticChecks"))
        precondition(!engine.keepMacMicrophone && !engine.systemVolume.softwareEnabled)
        engine.setKeepMacMicrophone(true)
        precondition(engine.keepMacMicrophone && checkDefaults.bool(forKey: "LevelsKeepMacMicrophone"))
        engine.systemVolume.setSoftwareEnabled(true)
        precondition(engine.systemVolume.softwareEnabled && checkDefaults.bool(forKey: "LevelsSoftwareOutputEnabled"))
        engine.setKeepMacMicrophone(false)
        engine.systemVolume.setSoftwareEnabled(false)
        checkDefaults.removePersistentDomain(forName: checkDomain)
        print("Shared options actions, persistence, and checkmarks passed")
        engine.processMonitor.seedForRender(apps: [
            AudioApp(id: -101, bundleID: "com.spotify.client", name: "Spotify", objectIDs: [], isPlaying: true, isRecording: false),
            AudioApp(id: -102, bundleID: "com.apple.Safari", name: "Safari", objectIDs: [], isPlaying: true, isRecording: false),
            AudioApp(id: -103, bundleID: "com.hnc.Discord", name: "Discord", objectIDs: [], isPlaying: false, isRecording: false)
        ])
        engine.seedForRender(volumes: ["com.spotify.client": AppVolume(volume: 0.42, outputDeviceUIDs: ["render-headphones"]),
                                      "com.apple.Safari": AppVolume(volume: 1.84, outputDeviceUIDs: ["render-speakers"]),
                                      "com.hnc.Discord": AppVolume(volume: 0.90, isMuted: true)])
        engine.systemVolume.seedForRender(volume: 0.65, isMuted: false, deviceName: "MacBook Pro Speakers")
        engine.inputVolume.seedForRender(volume: 0.45, isMuted: false, deviceName: "MacBook Pro Microphone")
        let speakers = AudioDevice(id: 1, uid: "render-speakers", name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn, outputDataSource: 0, inputDataSource: 0)
        let headphones = AudioDevice(id: 3, uid: "render-headphones", name: "External Headphones", transport: kAudioDeviceTransportTypeUSB, outputDataSource: 0, inputDataSource: 0)
        let microphone = AudioDevice(id: 2, uid: "render-mic", name: "MacBook Pro Microphone", transport: kAudioDeviceTransportTypeBuiltIn, outputDataSource: 0, inputDataSource: 0)
        engine.deviceMonitor.seedForRender(devices: [speakers, headphones], defaultDeviceID: 1)
        engine.inputDeviceMonitor.seedForRender(devices: [microphone], defaultDeviceID: 2)
        let colorMenu = checkOptions.makeMenu().items.first { $0.title == "Appearance" }!.submenu!
        colorMenu.performActionForItem(at: colorMenu.items.firstIndex { $0.title == "Light" }!)
        for dark in [true, false] {
            colorMenu.performActionForItem(at: colorMenu.items.firstIndex { $0.title == (dark ? "Dark" : "Light") }!)
            let settingsHosting = NSHostingView(rootView: checkOptions.settingsContent.environment(\.colorScheme, dark ? .dark : .light))
            settingsHosting.frame = NSRect(x: 0, y: 0, width: 480, height: 580)
            let settingsRenderWindow = NSWindow(contentRect: settingsHosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            settingsRenderWindow.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            settingsRenderWindow.contentView = settingsHosting
            settingsHosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            settingsHosting.layoutSubtreeIfNeeded()
            guard let bitmap = settingsHosting.bitmapImageRepForCachingDisplay(in: settingsHosting.bounds) else { fatalError("No Settings bitmap") }
            settingsHosting.cacheDisplay(in: settingsHosting.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("levels-settings-\(dark ? "dark" : "light").png"))
            settingsRenderWindow.contentView = nil
        }
        // A volatile domain isolates rendering from the real app's settings.
        for surface in ["Sage mesh", "Transparent Liquid Glass"] {
            UserDefaults.standard.setVolatileDomain(["LevelsMixerAppearance": "System", "LevelsMixerSurface": surface],
                                                   forName: UserDefaults.argumentDomain)
            for dark in [true, false] {
            for tab in ["Output", "Input"] {
                let view = MixerView(renderTab: tab).environment(engine).environment(MixerOptions(engine: engine))
                    .environment(\.colorScheme, dark ? .dark : .light)
                let hosting = NSHostingView(rootView: view)
                hosting.frame = NSRect(x: 0, y: 0, width: MixerLayout.width, height: MixerLayout.height)
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = hosting
                // Never order the window onto the desktop. Cache the real native view offscreen.
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
                hosting.layoutSubtreeIfNeeded()
                guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { fatalError("No bitmap") }
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
                let name = "levels-\(surface == "Sage mesh" ? "mesh" : "glass")-\(dark ? "dark" : "light")-\(tab.lowercased().replacingOccurrences(of: " ", with: "-")).png"
                try data.write(to: output.appendingPathComponent(name))
                print(name)
                window.contentView = nil
            }
            }
        }
        application.setActivationPolicy(.accessory)
        var settingsOpenCount = 0
        checkOptions.onShowSettings = { settingsOpenCount += 1 }
        let settingsMenu = checkOptions.makeMenu()
        let settingsIndex = settingsMenu.items.firstIndex { $0.title == "Settings…" }!
        for _ in 0..<3 {
            settingsMenu.performActionForItem(at: settingsIndex)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
            precondition(settingsWindow.isVisible)
            precondition(checkOptions.prepareSettingsWindow() === settingsWindow)
            settingsWindow.performClose(nil)
            precondition(!settingsWindow.isVisible)
        }
        precondition(settingsOpenCount == 3)
        print("Settings menu opens the same window, closes, and reopens: 3 cycles passed")
    }
}
