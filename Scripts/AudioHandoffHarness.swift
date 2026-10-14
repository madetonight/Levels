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
                let tap = ProcessTap(processObjectIDs: app.objectIDs, volume: 0.75)
                try tap.activate(outputs: outputs)
                proof["nativeBeforeHandoff"] = tap.tapDescription?.muteBehavior == .unmuted
                var failedOpen = false
                tap.beginHandoff { _ in failedOpen = true }
                try await pause(3)
                let adjusted = tap.handoffDiagnostics
                proof["adjustedAudio"] = adjusted.intercepting && adjusted.buffers > 0 && adjusted.peak > 0
                proof["adjustedPeak"] = adjusted.peak
                tap.simulateIOStallForTesting()
                try await pause(2.5)
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
                monitor.setMeteringVisible(false)
                let checks = ["nativeBeforeHandoff", "adjustedAudio", "stalledIOReleased", "explicitMute", "unmuteResumed", "nativeAfterRelease", "passiveNeverMutes"]
                proof["passed"] = checks.allSatisfy { proof[$0] as? Bool == true }
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
