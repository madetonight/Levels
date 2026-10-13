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
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let engine = MixerEngine()
        // Exercise menu actions against an isolated preference domain, never
        // the real app's settings, login registration, or audio controls.
        let checkDomain = "com.joseluna.levels-render.options-check.\(UUID().uuidString)"
        let checkDefaults = UserDefaults(suiteName: checkDomain)!
        let checkOptions = MixerOptions(engine: engine, defaults: checkDefaults)
        let firstMenu = checkOptions.makeMenu()
        let appearanceChoices = firstMenu.items.first { $0.title == "Appearance" }!.submenu!
        let darkIndex = appearanceChoices.items.firstIndex { $0.title == "Dark" }!
        appearanceChoices.performActionForItem(at: darkIndex)
        precondition(appearanceChoices.items.map(\.title) == ["Dark", "Light", "", "Solid", "Liquid Glass"])
        precondition(appearanceChoices.items[2].isSeparatorItem)
        precondition(firstMenu.items.allSatisfy { $0.title != "Surface" && $0.title != "Show inactive audio apps" })
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
        checkDefaults.removePersistentDomain(forName: checkDomain)
        print("Shared options actions, persistence, and checkmarks passed")
        engine.processMonitor.seedForRender(apps: [
            AudioApp(id: -101, bundleID: "com.spotify.client", name: "Spotify", objectIDs: [], isPlaying: true, isRecording: false),
            AudioApp(id: -102, bundleID: "com.apple.Safari", name: "Safari", objectIDs: [], isPlaying: true, isRecording: false),
            AudioApp(id: -103, bundleID: "com.hnc.Discord", name: "Discord", objectIDs: [], isPlaying: false, isRecording: false)
        ])
        engine.seedForRender(volumes: ["com.spotify.client": AppVolume(volume: 0.42, outputDeviceUIDs: ["render-headphones"]),
                                      "com.apple.Safari": AppVolume(volume: 0.75, outputDeviceUIDs: ["render-speakers"]),
                                      "com.hnc.Discord": AppVolume(volume: 0.90, isMuted: true)])
        engine.systemVolume.seedForRender(volume: 0.65, isMuted: false, deviceName: "MacBook Pro Speakers")
        engine.inputVolume.seedForRender(volume: 0.45, isMuted: false, deviceName: "MacBook Pro Microphone")
        let speakers = AudioDevice(id: 1, uid: "render-speakers", name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn, outputDataSource: 0, inputDataSource: 0)
        let headphones = AudioDevice(id: 3, uid: "render-headphones", name: "External Headphones", transport: kAudioDeviceTransportTypeUSB, outputDataSource: 0, inputDataSource: 0)
        let microphone = AudioDevice(id: 2, uid: "render-mic", name: "MacBook Pro Microphone", transport: kAudioDeviceTransportTypeBuiltIn, outputDataSource: 0, inputDataSource: 0)
        engine.deviceMonitor.seedForRender(devices: [speakers, headphones], defaultDeviceID: 1)
        engine.inputDeviceMonitor.seedForRender(devices: [microphone], defaultDeviceID: 2)
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
    }
}
