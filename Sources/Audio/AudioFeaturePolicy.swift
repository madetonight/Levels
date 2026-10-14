import CoreAudio
import Foundation

struct AudioFeaturePreferences {
    let defaults: UserDefaults
    var appResetLevel: Float {
        get { defaults.object(forKey: "LevelsAppResetLevel") == nil ? 1 : VolumeTaper.clampedPosition(defaults.float(forKey: "LevelsAppResetLevel")) }
        nonmutating set { defaults.set(VolumeTaper.clampedPosition(newValue), forKey: "LevelsAppResetLevel") }
    }
    var softwareOutputEnabled: Bool {
        get { defaults.bool(forKey: "LevelsSoftwareOutputEnabled") }
        nonmutating set { defaults.set(newValue, forKey: "LevelsSoftwareOutputEnabled") }
    }
    var keepMacMicrophone: Bool {
        get { defaults.bool(forKey: "LevelsKeepMacMicrophone") }
        nonmutating set { defaults.set(newValue, forKey: "LevelsKeepMacMicrophone") }
    }
}

struct SoftwareOutputLevel: Codable, Equatable {
    var volume: Float = 1
    var isMuted = false
    var isNeutral: Bool { volume == 1 && !isMuted }
    var gain: Float { isMuted ? 0 : VolumeTaper.gain(position: max(0, min(1, volume))) }
}

struct SoftwareOutputStore {
    let defaults: UserDefaults
    func load() -> [String: SoftwareOutputLevel] {
        let saved = defaults.loadJSON([String: SoftwareOutputLevel].self, forKey: "LevelsSoftwareOutputLevels") ?? [:]
        return saved.mapValues { level in
            var normalized = level
            normalized.volume = level.volume.isFinite ? max(0, min(1, level.volume)) : 1
            return normalized
        }
    }
    func save(_ levels: [String: SoftwareOutputLevel]) {
        defaults.saveJSON(levels.filter { !$0.value.isNeutral }, forKey: "LevelsSoftwareOutputLevels")
    }
}

struct TapControlState {
    let app: AppVolume
    let output: SoftwareOutputLevel
    var requiresTap: Bool { !app.isNeutral || !output.isNeutral }
    var isMuted: Bool { app.isMuted || output.isMuted }
    var outputGain: Float { VolumeTaper.gain(position: max(0, min(1, output.volume))) }
}

enum SoftwareOutputPolicy {
    static func supports(transport: UInt32, hardwareVolume: Bool) -> Bool {
        !hardwareVolume && (transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort)
    }
}

enum BluetoothInputPolicy {
    static func preferredInput(enabled: Bool, bluetoothOutput: Bool,
                               current: AudioDevice?, available: [AudioDevice]) -> AudioDevice? {
        guard enabled, bluetoothOutput, current == nil || current?.isBluetooth == true else { return nil }
        return available.first { $0.transport == kAudioDeviceTransportTypeBuiltIn }
    }
}

enum VolumeKey: Int {
    case up = 0, down = 1, mute = 7
    static func decode(subtype: Int, data1: Int) -> (key: VolumeKey, pressed: Bool)? {
        guard subtype == 8, let key = VolumeKey(rawValue: (data1 >> 16) & 0xffff) else { return nil }
        let state = (data1 >> 8) & 0xff
        guard state == 0x0a || state == 0x0b else { return nil }
        return (key, state == 0x0a)
    }
}
