import AudioToolbox
import CoreAudio
import Foundation
import Observation
import os

/// Reads and writes the default device's main volume and mute for one
/// direction, staying in sync with changes made elsewhere (volume keys,
/// Control Center). Input gain is absent or read-only on plenty of devices
/// (pro interfaces put it on a hardware knob) — `canSetVolume`/`canMute`
/// tell the UI when to disable the controls.
@MainActor
@Observable
final class SystemVolumeController {
    private static let logger = Logger(subsystem: "com.joseluna.levels", category: "SystemVolume")

    let direction: AudioDirection

    private(set) var volume: Float = 1.0
    private(set) var isMuted = false
    private(set) var deviceName = ""
    private(set) var canSetVolume = true
    private(set) var canMute = true
    private(set) var softwareEnabled: Bool
    private(set) var softwareActive = false
    private(set) var supportsSoftwareVolume = false
    private(set) var deviceUID = ""
    @ObservationIgnored var onSoftwareChange: (() -> Void)?
    @ObservationIgnored private let preferences: AudioFeaturePreferences
    @ObservationIgnored private let softwareStore: SoftwareOutputStore
    @ObservationIgnored private var softwareLevels: [String: SoftwareOutputLevel]
    @ObservationIgnored private var hardwareVolume = false
    @ObservationIgnored private var hardwareMute = false

    @ObservationIgnored private var endpoint: VolumeEndpoint
    @ObservationIgnored private var defaultDeviceListener: HALListener?
    @ObservationIgnored private var deviceListeners: [HALListener] = []

    init(direction: AudioDirection = .output, defaults: UserDefaults = .standard) {
        self.direction = direction
        preferences = AudioFeaturePreferences(defaults: defaults)
        softwareStore = SoftwareOutputStore(defaults: defaults)
        softwareEnabled = direction == .output && preferences.softwareOutputEnabled
        softwareLevels = softwareStore.load()
        endpoint = VolumeEndpoint(deviceID: .unknown, scope: direction.scope)
    }

    #if RENDER_SHOTS
        /// Render harness only: publish slider state without a HAL device.
        func seedForRender(volume: Float, isMuted: Bool, deviceName: String,
                           canSetVolume: Bool = true, canMute: Bool = true) {
            self.volume = volume
            self.isMuted = isMuted
            self.deviceName = deviceName
            self.canSetVolume = canSetVolume
            self.canMute = canMute
        }
    #endif

    func start() {
        installDefaultDeviceListener()
        attachToDefaultDevice()
    }

    /// Replaces both the system and device listeners after Core Audio reset;
    /// their registrations and the endpoint object ID are no longer valid.
    func recoverAfterServiceRestart() {
        defaultDeviceListener = nil
        deviceListeners.removeAll()
        endpoint.deviceID = .unknown
        installDefaultDeviceListener()
        attachToDefaultDevice()
    }

    private func installDefaultDeviceListener() {
        defaultDeviceListener = AudioObjectID.system.listen(direction.defaultDeviceSelector) {
            Task { @MainActor [weak self] in self?.attachToDefaultDevice() }
        }
    }

    func setVolume(_ value: Float) {
        if softwareActive {
            var level = softwareLevels[deviceUID] ?? SoftwareOutputLevel()
            level.volume = value.isFinite ? max(0, min(1, value)) : 1
            saveSoftwareLevel(level)
            return
        }
        if let applied = endpoint.writeVolume(value) {
            volume = applied
        } else {
            readBack() // keep published state honest when the HAL write fails
        }
    }

    func toggleMute() {
        if softwareActive {
            var level = softwareLevels[deviceUID] ?? SoftwareOutputLevel()
            // Some fixed-volume outputs still expose a native mute control.
            // Reflect that state and clear it only on an explicit unmute.
            level.isMuted = !isMuted
            if hardwareMute, endpoint.writeMute(level.isMuted) == nil {
                readBack()
                return
            }
            saveSoftwareLevel(level)
            return
        }
        if let muted = endpoint.writeMute(!isMuted) {
            isMuted = muted
        } else {
            readBack()
        }
    }

    /// Rebinds listeners after sleep/wake even if HAL omitted the expected
    /// default-device notification.
    func resync() {
        attachToDefaultDevice()
    }

    func setSoftwareEnabled(_ enabled: Bool) {
        guard direction == .output else { return }
        softwareEnabled = enabled
        preferences.softwareOutputEnabled = enabled
        attachToDefaultDevice()
        onSoftwareChange?()
    }

    /// Per-device settings never overwrite any per-app gain, mute, or route.
    func softwareLevel(for device: AudioDevice) -> SoftwareOutputLevel {
        guard softwareEnabled, SoftwareOutputPolicy.supports(transport: device.transport,
            hardwareVolume: device.id.isSettable(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                               scope: kAudioDevicePropertyScopeOutput)) else { return SoftwareOutputLevel() }
        return softwareLevels[device.uid] ?? SoftwareOutputLevel()
    }

    private func saveSoftwareLevel(_ level: SoftwareOutputLevel) {
        softwareLevels[deviceUID] = level.isNeutral ? nil : level
        softwareStore.save(softwareLevels)
        readBack()
        onSoftwareChange?()
    }

    // MARK: - Private

    private func attachToDefaultDevice() {
        guard let next = try? AudioObjectID.readDefaultDevice(direction), next.isValid else {
            endpoint.deviceID = .unknown
            deviceUID = ""
            deviceName = ""
            softwareActive = false
            supportsSoftwareVolume = false
            canSetVolume = false
            canMute = false
            deviceListeners.removeAll()
            onSoftwareChange?()
            return
        }
        endpoint.deviceID = next
        deviceUID = (try? next.readDeviceUID()) ?? ""
        deviceName = (try? next.readString(kAudioObjectPropertyName)) ?? ""
        hardwareVolume = next.isSettable(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                       scope: direction.scope)
        hardwareMute = next.isSettable(kAudioDevicePropertyMute, scope: direction.scope)
        var transport: UInt32 = 0
        try? next.read(kAudioDevicePropertyTransportType, into: &transport)
        supportsSoftwareVolume = direction == .output && SoftwareOutputPolicy.supports(transport: transport, hardwareVolume: hardwareVolume)
        softwareActive = softwareEnabled && supportsSoftwareVolume && !deviceUID.isEmpty
        canSetVolume = hardwareVolume || softwareActive
        canMute = hardwareMute || softwareActive

        deviceListeners = [
            next.listen(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                        scope: direction.scope) {
                Task { @MainActor [weak self] in self?.readBack() }
            },
            next.listen(kAudioDevicePropertyMute, scope: direction.scope) {
                Task { @MainActor [weak self] in self?.readBack() }
            },
        ]
        readBack()
    }

    private func readBack() {
        if softwareActive {
            let level = softwareLevels[deviceUID] ?? SoftwareOutputLevel()
            volume = level.volume
            isMuted = level.isMuted || (endpoint.readMute() ?? false)
            return
        }
        if let value = endpoint.readVolume() {
            volume = value
        } else {
            volume = 1 // no stale software attenuation after returning to native playback
        }
        if let muted = endpoint.readMute() {
            isMuted = muted
        } else {
            isMuted = false
        }
    }
}
