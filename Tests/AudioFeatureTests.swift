import CoreAudio
import Foundation
import Testing

@Suite("Audio enhancements: limiter, independent controls, and input policy")
struct AudioFeatureTests {
    private func limited(_ input: [Float], channels: Int, gain: Float,
                         limiter: inout PeakLimiter) -> [Float] {
        var output = [Float](repeating: 0, count: input.count)
        input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                withUnsafeMutablePointer(to: &limiter) { state in
                    _ = TapMix.mix(input: source.baseAddress!, inputLayout: .init(channels: channels, count: input.count),
                        output: destination.baseAddress!, outputLayout: .init(channels: channels, count: input.count),
                        gain: .init(current: gain, target: gain, ramp: 1), limiter: state)
                }
            }
        }
        return output
    }

    @Test("quiet stereo is amplified exactly; limiting preserves stereo balance")
    func stereoBoost() {
        var limiter = PeakLimiter()
        #expect(limited([0.1, -0.05, 0.2, -0.1], channels: 2, gain: 2, limiter: &limiter) == [0.2, -0.1, 0.4, -0.2])
        let output = limited([0.9, 0.45, -0.9, -0.45], channels: 2, gain: 2, limiter: &limiter)
        #expect(output.allSatisfy { abs($0) <= PeakLimiter.ceiling + 1e-6 })
        #expect(abs(output[0] - 0.98) < 1e-6)
        #expect(abs(output[1] / output[0] - 0.5) < 1e-6)
        #expect(abs(output[3] / output[2] - 0.5) < 1e-6)
    }

    @Test("boosted sine stays within ceiling across buffer boundaries")
    func boostedWave() {
        let input = (0..<24_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000)) * 0.9 }
        var limiter = PeakLimiter()
        var largest: Float = 0
        for start in stride(from: 0, to: input.count, by: 256) {
            let slice = Array(input[start..<min(start + 256, input.count)])
            let output = limited(slice, channels: 1, gain: 2, limiter: &limiter)
            largest = max(largest, output.map(abs).max() ?? 0)
        }
        #expect(largest > 0.97 && largest <= PeakLimiter.ceiling + 1e-6)
        #expect(limiter.reduction < 1)
    }

    @Test("limiter recovers smoothly and contains nonfinite samples")
    func releaseAndNonfinite() {
        var limiter = PeakLimiter(sampleRate: 1000)
        _ = limited([1], channels: 1, gain: 2, limiter: &limiter)
        let quiet = limited([Float](repeating: 0.1, count: 1200), channels: 1, gain: 2, limiter: &limiter)
        #expect(quiet.first! < quiet.last!)
        #expect(abs(quiet.last! - 0.2) < 1e-5)
        #expect(limited([.nan, .infinity], channels: 2, gain: 2, limiter: &limiter) == [0, 0])
    }

    @Test("software master gain and mute combine without overwriting app choices")
    func independentControls() {
        let original = AppVolume(volume: 1.84, isMuted: false, outputDeviceUIDs: ["monitor"])
        let reduced = TapControlState(app: original, output: .init(volume: 0.5, isMuted: false))
        #expect(reduced.requiresTap && !reduced.isMuted)
        #expect(reduced.outputGain == 0.125)
        #expect(reduced.app == original)
        #expect(TapControlState(app: original, output: .init(volume: 0.5, isMuted: true)).isMuted)
        #expect(TapControlState(app: AppVolume(isMuted: true), output: SoftwareOutputLevel()).isMuted)
        #expect(!TapControlState(app: AppVolume(), output: SoftwareOutputLevel()).requiresTap)
        #expect(TapControlState(app: AppVolume(), output: .init(volume: 0.5)).requiresTap)
        #expect(TapControlState(app: AppVolume(), output: .init(isMuted: true)).requiresTap)
    }

    @Test("enhancements opt in independently; boosted app and device settings survive reload")
    func persistentChoices() throws {
        let suite = "LevelsAudioFeatures-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AudioFeaturePreferences(defaults: defaults)
        #expect(!prefs.softwareOutputEnabled && !prefs.keepMacMicrophone)
        let apps = VolumeStore(defaults: defaults)
        let original = ["app": AppVolume(volume: 1.84, isMuted: true, outputDeviceUIDs: ["headphones"])]
        apps.save(original)
        let deviceStore = SoftwareOutputStore(defaults: defaults)
        deviceStore.save(["monitor": .init(volume: 0.6, isMuted: true), "other": SoftwareOutputLevel()])
        prefs.softwareOutputEnabled = true
        prefs.keepMacMicrophone = true
        #expect(AudioFeaturePreferences(defaults: defaults).softwareOutputEnabled)
        #expect(AudioFeaturePreferences(defaults: defaults).keepMacMicrophone)
        #expect(deviceStore.load() == ["monitor": .init(volume: 0.6, isMuted: true)])
        #expect(apps.load() == original)
        prefs.softwareOutputEnabled = false
        #expect(deviceStore.load()["monitor"]?.isMuted == true && apps.load() == original)
    }

    private func device(_ id: UInt32, transport: UInt32) -> AudioDevice {
        AudioDevice(id: id, uid: "\(id)", name: "Device \(id)", transport: transport, outputDataSource: 0, inputDataSource: 0)
    }

    @Test("Bluetooth quality preference chooses only built-in input, never replaces USB input")
    func microphonePolicy() {
        let headset = device(1, transport: kAudioDeviceTransportTypeBluetooth)
        let builtin = device(2, transport: kAudioDeviceTransportTypeBuiltIn)
        let usb = device(3, transport: kAudioDeviceTransportTypeUSB)
        let available = [headset, usb, builtin]
        #expect(BluetoothInputPolicy.preferredInput(enabled: true, bluetoothOutput: true, current: headset, available: available) == builtin)
        #expect(BluetoothInputPolicy.preferredInput(enabled: false, bluetoothOutput: true, current: headset, available: available) == nil)
        #expect(BluetoothInputPolicy.preferredInput(enabled: true, bluetoothOutput: false, current: headset, available: available) == nil)
        #expect(BluetoothInputPolicy.preferredInput(enabled: true, bluetoothOutput: true, current: usb, available: available) == nil)
        #expect(BluetoothInputPolicy.preferredInput(enabled: true, bluetoothOutput: true, current: builtin, available: available) == nil)
        #expect(BluetoothInputPolicy.preferredInput(enabled: true, bluetoothOutput: true, current: headset, available: [headset, usb]) == nil)
    }

    @Test("software control applies only to fixed HDMI/DisplayPort endpoints")
    func fixedOutputs() {
        for transport in [kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort] {
            #expect(SoftwareOutputPolicy.supports(transport: transport, hardwareVolume: false))
            #expect(!SoftwareOutputPolicy.supports(transport: transport, hardwareVolume: true))
        }
        #expect(!SoftwareOutputPolicy.supports(transport: kAudioDeviceTransportTypeBuiltIn, hardwareVolume: false))
        #expect(!SoftwareOutputPolicy.supports(transport: kAudioDeviceTransportTypeBluetooth, hardwareVolume: false))
    }

    @Test("media decoding ignores unrelated keys, distinguishes releases and repeats")
    func mediaPackets() {
        for key in [VolumeKey.up, .down, .mute] {
            #expect(VolumeKey.decode(subtype: 8, data1: (key.rawValue << 16) | 0x0a00)?.key == key)
            #expect(VolumeKey.decode(subtype: 8, data1: (key.rawValue << 16) | 0x0a01)?.pressed == true)
            #expect(VolumeKey.decode(subtype: 8, data1: (key.rawValue << 16) | 0x0b00)?.pressed == false)
        }
        #expect(VolumeKey.decode(subtype: 8, data1: (16 << 16) | 0x0a00) == nil)
        #expect(VolumeKey.decode(subtype: 9, data1: 0x0a00) == nil)
        #expect(VolumeKey.decode(subtype: 8, data1: 0x0c00) == nil)
    }
}

@Suite("Playback status and independent reset")
struct PlaybackAndResetTests {
    @Test("Digital silence is Idle even while an output stream is running")
    func signalActivity() {
        let activity = AudioSignalActivity()
        let base: UInt64 = 1_000_000_000
        [Float](repeating: 0, count: 256).withUnsafeBufferPointer {
            activity.observe($0.baseAddress!, count: $0.count, now: base)
        }
        #expect(activity.hasReceivedAudio)
        #expect(!activity.isPlaying(now: base))
        [Float.nan, .infinity, 0.00001].withUnsafeBufferPointer {
            activity.observe($0.baseAddress!, count: $0.count, now: base)
        }
        #expect(!activity.isPlaying(now: base))
        [Float(0), 0.002, -0.01].withUnsafeBufferPointer {
            activity.observe($0.baseAddress!, count: $0.count, now: base)
        }
        #expect(activity.isPlaying(now: base + 199_000_000))
        #expect(!activity.isPlaying(now: base + 201_000_000))
        #expect(!activity.isPlaying(now: base - 1))
    }

    @Test("Helper replacement retains one Idle row without keeping stale HAL IDs; quitting removes it")
    func helperChurn() {
        var presence = PlaybackPresence()
        let playing = AudioApp(id: 12, bundleID: "browser", name: "Browser", objectIDs: [1], isPlaying: true, isRecording: false, isPlaybackMeasured: true)
        #expect(presence.reconcile([playing], runningBundles: ["browser"], now: 0).count == 1)
        let gap = presence.reconcile([], runningBundles: ["browser"], now: 1)
        #expect(gap.count == 1 && !gap[0].isPlaying && gap[0].objectIDs.isEmpty)
        #expect(presence.recentlyPlaying.contains("browser"))
        let replacement = AudioApp(id: 12, bundleID: "browser", name: "Browser", objectIDs: [2], isPlaying: true, isRecording: false)
        #expect(presence.reconcile([replacement], runningBundles: ["browser"], now: 2)[0].objectIDs == [2])
        #expect(presence.reconcile([], runningBundles: [], now: 2.1).isEmpty)
        #expect(presence.recentlyPlaying.isEmpty)
    }

    @Test("Pauses update the status immediately but retain a row briefly; ordering never follows activity")
    func stableRows() {
        var presence = PlaybackPresence()
        let a = AudioApp(id: 1, bundleID: "a", name: "Alpha", objectIDs: [1], isPlaying: false, isRecording: false)
        let z = AudioApp(id: 2, bundleID: "z", name: "Zulu", objectIDs: [2], isPlaying: true, isRecording: false)
        #expect(presence.reconcile([z,a], runningBundles: ["a","z"], now: 0).map(\.bundleID) == ["a","z"])
        let idle = AudioApp(id: 2, bundleID: "z", name: "Zulu", objectIDs: [2], isPlaying: false, isRecording: false)
        #expect(!presence.reconcile([idle,a], runningBundles: ["a","z"], now: 1).last!.isPlaying)
        #expect(presence.recentlyPlaying.contains("z"))
        _ = presence.reconcile([idle,a], runningBundles: ["a","z"], now: 5)
        #expect(!presence.recentlyPlaying.contains("z"))
    }

    @Test("Reset level defaults to unity, persists, and only changes one app's level")
    func independentReset() throws {
        let suite = "LevelsReset-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AudioFeaturePreferences(defaults: defaults)
        #expect(preferences.appResetLevel == 1)
        preferences.appResetLevel = 0.72
        #expect(AudioFeaturePreferences(defaults: defaults).appResetLevel == 0.72)
        let original = AppVolume(volume: 1.8, isMuted: true, outputDeviceUIDs: ["headphones"])
        let reset = original.resettingLevel(to: preferences.appResetLevel)
        #expect(reset.volume == 0.72 && reset.isMuted && reset.outputDeviceUIDs == ["headphones"])
        #expect(original.volume == 1.8)
        preferences.appResetLevel = .nan
        #expect(preferences.appResetLevel == 1)
        preferences.appResetLevel = 999
        #expect(preferences.appResetLevel == 2)
    }
}
