// Hardware regression harness. Never part of the shipping app target.
import AppKit
import CoreAudio

enum RenderHarness {
    static let isActive = false
    @MainActor static func demoIcon(forBundleID: String) -> NSImage? { nil }
}
@main @MainActor enum AudioHandoffHarness {
    static func pause(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            var proof: [String: Any] = [:]
            do {
                let monitor = AudioProcessMonitor()
                monitor.start()
                for _ in 0..<20 {
                    if monitor.apps.contains(where: { $0.bundleID == "com.joseluna.levels.playback-probe" }) { break }
                    try await pause(0.5)
                }
                guard let app = monitor.apps.first(where: { $0.bundleID == "com.joseluna.levels.playback-probe" }) else { throw NSError(domain: "No probe process", code: 1) }
                let id = try AudioObjectID.readDefaultOutputDevice()
                let outputs = [ProcessTap.Output(uid: try id.readDeviceUID(), id: id)]
                if CommandLine.arguments.contains("--auto-recovery") {
                    let domain = "com.joseluna.levels-recovery-test.\(UUID().uuidString)"
                    let defaults = UserDefaults(suiteName: domain)!
                    defer { defaults.removePersistentDomain(forName: domain) }
                    let engine = MixerEngine(defaults: defaults)
                    engine.start()
                    engine.setVolume(0.75, for: app)
                    try await pause(1.5)
                    guard let initial = engine.tapLifecycle.taps[app.bundleID] else { throw NSError(domain: "Missing initial tap", code: 2) }
                    proof["initialAdjustment"] = initial.handoffDiagnostics.intercepting && initial.handoffDiagnostics.peak > 0
                    initial.simulateIOStallForTesting()
                    try await pause(6.5)
                    let replacement = engine.tapLifecycle.taps[app.bundleID]
                    proof["reconnectedWithoutUserAction"] = replacement != nil && replacement !== initial && replacement!.handoffDiagnostics.intercepting && replacement!.handoffDiagnostics.peak > 0
                    proof["failedTapReleased"] = !initial.tapID.isValid
                    proof["recoveryErrorCleared"] = engine.tapErrors[app.bundleID] == nil && !engine.isRecovering(app.bundleID)
                    proof["savedControlsPreserved"] = engine.volume(for: app).volume == 0.75 && !engine.volume(for: app).isMuted && replacement?.activatedOutputs == outputs
                    engine.fadeOutAndStop()
                    let checks = ["initialAdjustment", "reconnectedWithoutUserAction", "failedTapReleased", "recoveryErrorCleared", "savedControlsPreserved"]
                    proof["passed"] = checks.allSatisfy { proof[$0] as? Bool == true }
                } else {
                let tap = ProcessTap(processObjectIDs: app.objectIDs, volume: 0.75)
                try tap.activate(outputs: outputs)
                proof["nativeBeforeHandoff"] = tap.tapDescription?.muteBehavior == .unmuted
                var failedOpen = false
                tap.beginHandoff { _ in failedOpen = true }
                if CommandLine.arguments.contains("--idle-resume") {
                    try await pause(1.5)
                    proof["initialAdjustment"] = tap.handoffDiagnostics.intercepting && tap.handoffDiagnostics.peak > 0
                    for _ in 0..<30 {
                        if !app.objectIDs.contains(where: { $0.readProcessIsRunningOutput() }) { break }
                        try await pause(0.2)
                    }
                    proof["enginePaused"] = !app.objectIDs.contains(where: { $0.readProcessIsRunningOutput() })
                    // Force absent callbacks even if the driver keeps clocking.
                    tap.simulateIOStallForTesting()
                    try await pause(2.6)
                    proof["idleIsNotAnError"] = !failedOpen && tap.tapID.isValid && !tap.handoffDiagnostics.intercepting
                    tap.simulateIOStallForTesting(false)
                    for _ in 0..<30 {
                        if app.objectIDs.contains(where: { $0.readProcessIsRunningOutput() }) { break }
                        try await pause(0.2)
                    }
                    try await pause(1)
                    proof["resumeReappliedLevel"] = tap.handoffDiagnostics.intercepting && tap.handoffDiagnostics.peak > 0 && tap.volume == 0.75
                    proof["routeAndMutePreserved"] = tap.activatedOutputs == outputs && !tap.isMuted
                    tap.invalidate()
                    let checks = ["nativeBeforeHandoff", "initialAdjustment", "enginePaused", "idleIsNotAnError", "resumeReappliedLevel", "routeAndMutePreserved"]
                    proof["passed"] = checks.allSatisfy { proof[$0] as? Bool == true }
                } else {
                    try await pause(3)
                    let adjusted = tap.handoffDiagnostics
                    proof["adjustedAudio"] = adjusted.intercepting && adjusted.buffers > 0 && adjusted.peak > 0
                    proof["adjustedPeak"] = adjusted.peak
                    tap.simulateIOStallForTesting()
                    try await pause(2.6)
                    proof["stalledIOReleased"] = failedOpen && !tap.tapID.isValid && !tap.handoffDiagnostics.intercepting
                    let fresh = ProcessTap(processObjectIDs: app.objectIDs, volume: 0.75, isMuted: true)
                    try fresh.activate(outputs: outputs)
                    fresh.beginHandoff { _ in }
                    try await pause(1)
                    proof["explicitMute"] = fresh.handoffDiagnostics.intercepting && fresh.handoffDiagnostics.peak == 0
                    fresh.isMuted = false
                    try await pause(0.3)
                    proof["unmuteResumed"] = fresh.handoffDiagnostics.peak > 0
                    fresh.invalidate()
                    proof["nativeAfterRelease"] = !fresh.tapID.isValid && !fresh.handoffDiagnostics.intercepting
                    let meter = ProcessTap(processObjectIDs: app.objectIDs, monitorOnly: true)
                    try meter.activate(outputs: outputs)
                    try await pause(0.5)
                    proof["passiveNeverMutes"] = meter.tapDescription?.muteBehavior == .unmuted && !meter.handoffDiagnostics.intercepting && meter.activity.isPlaying(now: DispatchTime.now().uptimeNanoseconds)
                    meter.invalidate()
                    let checks = ["nativeBeforeHandoff", "adjustedAudio", "stalledIOReleased", "explicitMute", "unmuteResumed", "nativeAfterRelease", "passiveNeverMutes"]
                    proof["passed"] = checks.allSatisfy { proof[$0] as? Bool == true }
                }
                }
                monitor.setMeteringVisible(false)
            } catch { proof["error"] = error.localizedDescription; proof["passed"] = false }
            let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Levels-audio-handoff.json")
            print(String(data: try! JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys]), encoding: .utf8)!)
            print("Proof:", path.path)
            try? JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]).write(to: path)
            NSApp.terminate(nil)
        }
        NSApp.run()
    }
}
