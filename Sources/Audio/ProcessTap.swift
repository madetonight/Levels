import AudioToolbox
import CoreAudio
import Foundation
import os
import Synchronization

/// Owns the Core Audio plumbing that gives Fader control over one app's volume:
/// a process tap that mutes the app's native output, an aggregate device wrapping
/// the real output device, and an IO proc that re-renders the tapped audio with gain.
///
/// Threading: setup and teardown run on the main actor; `volume` and `isMuted` are
/// read lock-free by the real-time HAL IO thread. Aligned Float32/Bool loads and
/// stores are atomic on Apple silicon, so no locking is needed for these.
final class ProcessTap: SleepManagedAudioTap, @unchecked Sendable {
    let activity = AudioSignalActivity()
    private let monitorOnly: Bool
    private let intercepting = Atomic<Bool>(false)
    private let lastCallback = Atomic<UInt64>(0)
    private let readyToHandoff = Atomic<Bool>(false)
    private var activatedAt: UInt64 = 0
    @MainActor private var handoffTask: Task<Void, Never>?

    static let logger = Logger(subsystem: "com.joseluna.levels", category: "ProcessTap")
    /// Fader never needs exclusive hardware access, and its audio IO must not
    /// keep the CPU awake while the rest of the machine is idle.
    private static func configureHALPowerPolicy() {
        try? AudioObjectID.system.write(kAudioHardwarePropertySleepingIsAllowed, value: UInt32(1))
        try? AudioObjectID.system.write(kAudioHardwarePropertyHogModeIsAllowed, value: UInt32(0))
    }

    #if RENDER_SHOTS
    private let simulateStall = Atomic<Bool>(false)
    private let renderedBuffers = Atomic<Int>(0)
    private let lastRenderedPeak = Atomic<Float>(0)
    var handoffDiagnostics: (intercepting: Bool, buffers: Int, peak: Float) {
        (intercepting.load(ordering: .acquiring), renderedBuffers.load(ordering: .relaxed), lastRenderedPeak.load(ordering: .relaxed))
    }
    func simulateIOStallForTesting(_ enabled: Bool = true) { simulateStall.store(enabled, ordering: .relaxed) }
    var activityDiagnostics: String { "tap=\(tapID) aggregate=\(aggregateID) float32=\(_isFloat32) received=\(activity.hasReceivedAudio)" }
    #endif

    /// Slider position, 0.0...2.0. Read by the RT thread every buffer and
    /// run through `taperedGain` before it reaches the samples — the stored
    /// value stays linear position so the UI and VolumeStore keep their
    /// 0...2 slider semantics (unity remains at 1).
    private nonisolated(unsafe) var _volume: Float
    private nonisolated(unsafe) var _outputGain: Float
    private nonisolated(unsafe) var _limiter = PeakLimiter()
    /// Mute flag. Read by the RT thread every buffer.
    private nonisolated(unsafe) var _isMuted: Bool
    /// Gain ramped towards `_volume` per frame to avoid clicks. RT thread only.
    private nonisolated(unsafe) var _currentGain: Float
    /// Per-frame ramp coefficient for ~30 ms exponential gain smoothing.
    /// Computed from the device sample rate in activate(); the render never
    /// runs before that, so the placeholder is inert.
    private nonisolated(unsafe) var _rampCoefficient: Float = 0
    /// The gain path assumes Float32 PCM. Verified at activation; on any other
    /// format the render falls back to bit-exact passthrough instead of
    /// reinterpreting foreign bytes as floats.
    private nonisolated(unsafe) var _isFloat32 = true

    var tapID = AudioObjectID.unknown
    var aggregateID = AudioObjectID.unknown
    var procID: AudioDeviceIOProcID?
    var tapDescription: CATapDescription?
    private let ioQueue = DispatchQueue(label: "com.joseluna.levels.io", qos: .userInitiated)

    let processObjectIDs: [AudioObjectID]

    /// A resolved output device: the UID names the aggregate's sub-device, the
    /// object ID catches a device that died and re-published under the same
    /// UID — the aggregate stays bound to the corpse and the tapped app would
    /// otherwise sit muted with nobody re-rendering it.
    struct Output: Equatable {
        let uid: String
        let id: AudioObjectID
    }

    /// The output devices this tap's aggregate fans out to, clock first. The
    /// aggregate pins them at activation, so a route or default change is
    /// honoured by rebuilding the tap, not mutating it — this records the
    /// current pins.
    private(set) var activatedOutputs: [Output] = []

    var volume: Float {
        get { _volume }
        set { _volume = VolumeTaper.clampedPosition(newValue) }
    }

    var outputGain: Float {
        get { _outputGain }
        set { _outputGain = newValue.isFinite ? max(0, min(1, newValue)) : 1 }
    }

    var isMuted: Bool {
        get { _isMuted }
        set { _isMuted = newValue }
    }

    init(processObjectIDs: [AudioObjectID], volume: Float = 1.0, isMuted: Bool = false, outputGain: Float = 1, monitorOnly: Bool = false) {
        self.monitorOnly = monitorOnly
        if !monitorOnly { Self.configureHALPowerPolicy() }
        self.processObjectIDs = processObjectIDs
        _volume = VolumeTaper.clampedPosition(volume)
        _outputGain = max(0, min(1, outputGain))
        _isMuted = isMuted
        _currentGain = VolumeTaper.gain(position: _volume) * _outputGain
    }

    /// Builds the tap → aggregate → IO proc chain. The first UID is the clock
    /// (and main) sub-device; any others stack on with drift compensation, so
    /// the app fans out to several devices at once.
    func activate(outputs: [Output]) throws {
        guard !aggregateID.isValid else { return }
        guard !outputs.isEmpty else { return }
        guard !processObjectIDs.isEmpty else { return }
        let clockUID = outputs.first?.uid ?? ""
        activatedOutputs = outputs

        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        // Capture access can succeed while TCC supplies only silence. Never
        // suppress native playback until real samples and a writable output
        // have been observed on our IO path.
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = "\(AudioDevice.plumbingNamePrefix) tap #\(processObjectIDs.first ?? 0)"

        var tap = AudioObjectID.unknown
        try checked(AudioHardwareCreateProcessTap(description, &tap), "create process tap")
        (tapID, tapDescription) = (tap, description)

        var aggregateDescription: [String: Any] = [
            // The plumbing prefix keeps it out of AudioDeviceMonitor's list.
            kAudioAggregateDeviceNameKey: "\(AudioDevice.plumbingNamePrefix) aggregate #\(processObjectIDs.first ?? 0)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: clockUID,
            kAudioAggregateDeviceClockDeviceKey: clockUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: outputs.map {
                [kAudioSubDeviceUIDKey: $0.uid, kAudioSubDeviceDriftCompensationKey: $0.uid != clockUID]
            },
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        if outputs.count > 1 {
            aggregateDescription[kAudioAggregateDeviceIsStackedKey] = true
        }

        var aggregate = AudioObjectID.unknown
        try checked(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate),
                    "create aggregate device")
        aggregateID = aggregate

        var sampleRate: Float64 = 48000
        try? aggregateID.read(kAudioDevicePropertyNominalSampleRate, into: &sampleRate)
        _rampCoefficient = 1 - exp(-1 / (Float(sampleRate) * 0.030))
        _limiter = PeakLimiter(sampleRate: sampleRate)

        var format = AudioStreamBasicDescription()
        try tapID.read(kAudioTapPropertyFormat, into: &format)
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
              format.mBitsPerChannel == 32 else {
            throw HALError.operation(kAudioHardwareUnsupportedOperationError, "validate tap PCM format")
        }
        _isFloat32 = true
        activatedAt = DispatchTime.now().uptimeNanoseconds

        var proc: AudioDeviceIOProcID?
        try checked(
            // @Sendable strips inferred @MainActor isolation: the HAL invokes
            // this block on its real-time IO thread, and an isolated closure
            // would trap in dispatch_assert_queue. unowned(unsafe) avoids
            // per-buffer refcount traffic; it is safe because teardown destroys
            // the IO proc (blocking until the callback exits) before deinit.
            AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID,
                                               ioQueue) { @Sendable [unowned(unsafe) self] _, input, _, output, _ in
                render(input, into: output)
            },
            "create IO proc"
        )
        procID = proc
        try checked(AudioDeviceStart(aggregateID, procID), "start aggregate device")

        let processIDs = processObjectIDs.map(String.init).joined(separator: ",")
        Self.logger
            .info("Tap active for processes [\(processIDs, privacy: .public)]: tap \(tap), aggregate \(aggregate)")
    }

    /// Called only for control taps. Monitoring taps stay nonmuting forever.
    /// A dead IO path restores native playback instead of retaining a mute.
    @MainActor
    func beginHandoff(onRecovered: @escaping @MainActor () -> Void = {},
                      onFailure: @escaping @MainActor (ProcessTap) -> Void) {
        guard !monitorOnly, handoffTask == nil else { return }
        handoffTask = Task { @MainActor [weak self] in
            var runningSince: UInt64?
            var interceptedAt: UInt64?
            var reportedRecovery = false
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, tapID.isValid else { return }
                let callback = lastCallback.load(ordering: .acquiring)
                let now = DispatchTime.now().uptimeNanoseconds
                let outputRunning = processObjectIDs.contains { $0.readProcessIsRunningOutput() }
                if outputRunning { if runningSince == nil { runningSince = now } }
                else { runningSince = nil }
                switch TapHandoffPolicy.action(now: now, lastCallback: callback,
                    runningSince: runningSince, isAlive: isAlive) {
                case .recover:
                    invalidate()
                    onFailure(self)
                    return
                case .releaseIdle:
                    // An app is allowed to pause its engine. Restore its native
                    // path quietly and wait for fresh samples before reapplying.
                    readyToHandoff.store(false, ordering: .releasing)
                    interceptedAt = nil
                    if intercepting.load(ordering: .acquiring), let description = tapDescription {
                        description.muteBehavior = .unmuted
                        intercepting.store(false, ordering: .releasing)
                        do { try tapID.writeObjectReference(kAudioTapPropertyDescription, value: description) }
                        catch { invalidate(); onFailure(self); return }
                    }
                    continue
                case .wait: break
                }
                if let began = interceptedAt, !reportedRecovery, now - began >= 3_000_000_000,
                   callback > 0, now - callback < TapHandoffPolicy.timeout {
                    reportedRecovery = true
                    onRecovered()
                }
                guard !intercepting.load(ordering: .acquiring),
                      readyToHandoff.load(ordering: .acquiring), callback > 0,
                      now - callback < TapHandoffPolicy.timeout,
                      activity.isPlaying(now: now), let description = tapDescription else { continue }
                interceptedAt = now
                description.muteBehavior = .mutedWhenTapped
                intercepting.store(true, ordering: .releasing)
                do {
                    try tapID.writeObjectReference(kAudioTapPropertyDescription, value: description)
                } catch {
                    invalidate()
                    onFailure(self)
                    return
                }
            }
        }
    }

    /// Whether the private aggregate still exists HAL-side. Device churn can
    /// kill it under the tap; `.mutedWhenTapped` then leaves the app muted
    /// with nobody re-rendering it, so a dead aggregate means rebuild now.
    @MainActor
    var isAlive: Bool {
        guard aggregateID.isValid else { return false }
        var alive: UInt32 = 0
        guard (try? aggregateID.read(kAudioDevicePropertyDeviceIsAlive, into: &alive)) != nil else { return false }
        return alive != 0
    }

    /// Tears down in the HAL-required order: stop → IO proc → aggregate → tap.
    /// Releasing the tap restores the app's native output.
    @MainActor
    func invalidate() {
        handoffTask?.cancel()
        handoffTask = nil
        intercepting.store(false, ordering: .releasing)
        // Restore native output first, including a driver that stalls teardown.
        if tapID.isValid, let description = tapDescription {
            description.muteBehavior = .unmuted
            try? tapID.writeObjectReference(kAudioTapPropertyDescription, value: description)
        }
        Self.destroy(aggregateID: aggregateID, tapID: tapID, procID: procID)
        procID = nil
        aggregateID = .unknown
        tapID = .unknown
        tapDescription = nil
    }

    deinit {
        // Safe off the main actor: no other reference exists by now, and the
        // HAL calls block until the IO proc has exited.
        Self.destroy(aggregateID: aggregateID, tapID: tapID, procID: procID)
    }

    private static func destroy(aggregateID: AudioObjectID, tapID: AudioObjectID, procID: AudioDeviceIOProcID?) {
        if aggregateID.isValid {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
        }
    }

    // MARK: - Real-time path. No allocation, locks, ObjC, or logging below.

    private func render(_ input: UnsafePointer<AudioBufferList>, into output: UnsafeMutablePointer<AudioBufferList>) {
        #if RENDER_SHOTS
        if simulateStall.load(ordering: .relaxed) { Self.silence(output); return }
        #endif
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        // HAL appends the process tap after physical input streams. Input 0
        // can be a headset microphone: pairing it with output 0 loses audio.
        guard let source = inputs.last, let inData = source.mData,
              source.mDataByteSize > 0 else {
            Self.silence(output)
            return
        }
        let now = DispatchTime.now().uptimeNanoseconds
        activity.observe(inData.assumingMemoryBound(to: Float.self),
            count: Int(source.mDataByteSize) / MemoryLayout<Float>.size, now: now)
        let writable = outputs.contains { $0.mData != nil && $0.mDataByteSize > 0 }
        if monitorOnly || writable { lastCallback.store(now, ordering: .releasing) }
        if writable && activity.isPlaying(now: now) { readyToHandoff.store(true, ordering: .releasing) }
        guard !monitorOnly, intercepting.load(ordering: .acquiring), !_isMuted else {
            Self.silence(output)
            return
        }
        let targetGain = VolumeTaper.gain(position: _volume) * _outputGain
        var gain = _currentGain
        let ramp = _rampCoefficient

        for outBuffer in outputs {
            guard let outData = outBuffer.mData else { continue }
            // One ramp shared across the buffer list; in practice taps deliver
            // a single interleaved buffer, so this is exact.
            gain = withUnsafeMutablePointer(to: &_limiter) { limiter in TapMix.mix(
                input: inData.assumingMemoryBound(to: Float.self),
                inputLayout: TapMix.Layout(channels: Int(source.mNumberChannels),
                                           count: Int(source.mDataByteSize) / MemoryLayout<Float>.size),
                output: outData.assumingMemoryBound(to: Float.self),
                outputLayout: TapMix.Layout(channels: Int(outBuffer.mNumberChannels),
                                            count: Int(outBuffer.mDataByteSize) / MemoryLayout<Float>.size),
                gain: TapMix.Gain(current: gain, target: targetGain, ramp: ramp),
                limiter: targetGain > 1 || gain > 1 || limiter.pointee.isReducing ? limiter : nil
            ) }
        }
        _currentGain = gain
        #if RENDER_SHOTS
        var peak: Float = 0
        for buffer in outputs {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for index in 0..<(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) { peak = max(peak, abs(data[index])) }
        }
        lastRenderedPeak.store(peak, ordering: .relaxed)
        renderedBuffers.wrappingAdd(1, ordering: .relaxed)
        #endif
    }

    private static func silence(_ output: UnsafeMutablePointer<AudioBufferList>) {
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }


}

/// Converts an OSStatus into a thrown HALError with context.
func checked(_ status: OSStatus, _ what: @autoclosure () -> String) throws {
    guard status == noErr else {
        throw HALError.operation(status, what())
    }
}
