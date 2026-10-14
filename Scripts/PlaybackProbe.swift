// Native verification source, never included in the Levels application target.
// Plays a very quiet tone, digital silence, then a tone on the existing output.
import AppKit
import AVFoundation
import Synchronization

@main enum PlaybackProbe {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.finishLaunching()
        let continuous = CommandLine.arguments.contains("--continuous")
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let beginning = Atomic<UInt64>(0)
        let node = AVAudioSourceNode(format: format) { @Sendable _, time, frames, buffers in
            let base = beginning.load(ordering: .relaxed)
            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = base == 0 ? 0 : Double(now - base) / 1_000_000_000
            let tone = continuous || elapsed < 4 || elapsed >= 7
            let data = UnsafeMutableAudioBufferListPointer(buffers)
            for frame in 0..<Int(frames) {
                let sample = tone ? Float(sin((time.pointee.mSampleTime + Double(frame)) * 2 * .pi * 440 / 48000)) * 0.002 : 0
                for buffer in data {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        beginning.store(DispatchTime.now().uptimeNanoseconds, ordering: .relaxed)
        let finish = ProcessInfo.processInfo.systemUptime + (continuous ? 25 : 10)
        print("Probe started", ProcessInfo.processInfo.systemUptime)
        fflush(stdout)
        while ProcessInfo.processInfo.systemUptime < finish {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        print("Probe stopped", ProcessInfo.processInfo.systemUptime)
        fflush(stdout)
        engine.stop()
    }
}
