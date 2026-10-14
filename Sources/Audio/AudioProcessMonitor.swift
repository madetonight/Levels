import AppKit
import CoreAudio
import Observation
import os

/// Watches the HAL's audio process list and publishes the running apps
/// that can play sound. Helper processes (browser media children, Electron
/// renderers) group under their responsible application.
@MainActor
@Observable
final class AudioProcessMonitor {
    private static let logger = Logger(subsystem: "com.joseluna.levels", category: "AudioProcessMonitor")

    private(set) var apps: [AudioApp] = []
    private(set) var recentlyPlaying: Set<String> = []
    @ObservationIgnored var signalSource: ((String) -> AudioSignalActivity?)?
    @ObservationIgnored private var presence = PlaybackPresence()
    @ObservationIgnored private var stateListeners: [AudioObjectID: [HALListener]] = [:]
    @ObservationIgnored private var meters: [String: ProcessTap] = [:]
    @ObservationIgnored private var failedMeters: Set<String> = []
    @ObservationIgnored private var pendingMeters: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var meteringVisible = false
    @ObservationIgnored private var measurementSuspended = false

    /// Passive, nonmuting meters exist only while the mixer is visible. Reuse
    /// samples from a control tap when one already exists.
    func setMeteringVisible(_ visible: Bool) {
        meteringVisible = visible
        failedMeters.removeAll()
        if !visible { clearMeters() }
        refresh()
    }
    func suspendMeasurement() { measurementSuspended = true; clearMeters() }
    func resumeMeasurement() { measurementSuspended = false; refresh() }
    private func clearMeters() {
        for task in pendingMeters.values { task.cancel() }
        pendingMeters.removeAll()
        for meter in meters.values { meter.invalidate() }
        meters.removeAll()
    }


    @ObservationIgnored private var listListener: HALListener?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    #if RENDER_SHOTS
        var activityDiagnostics: String { "active=\(meters.mapValues { $0.activityDiagnostics }) pending=\(pendingMeters.keys) failed=\(failedMeters)" }

        /// Render harness only: publish a demo app list without any HAL contact.
        func seedForRender(apps: [AudioApp]) {
            self.apps = apps
        }
    #endif

    func start() {
        guard pollTask == nil else { return } // idempotent: a second call must not double-listen
        installListListener()
        // Per-process IsRunningOutput flips do NOT arrive in practice
        // (observed on macOS 26), so the playing state is polled. Reading the
        // flags of a few dozen process objects costs microseconds.
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Generous tolerance lets the kernel coalesce the wakeup with
                // other timers — playing-state freshness doesn't need precision.
                do {
                    try await Task.sleep(for: .milliseconds(self?.meteringVisible == true ? 200 : 750), tolerance: .milliseconds(50))
                } catch {
                    break
                }
                guard let self else { break }
                refresh()
            }
        }
        refresh()
    }

    /// Core Audio resets discard client listeners and invalidate process
    /// object IDs. Keep the inexpensive poll task, but replace the listener
    /// and published objects before attempting a fresh enumeration.
    func recoverAfterServiceRestart() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        clearMeters()
        stateListeners.removeAll()
        failedMeters.removeAll()
        installListListener()
        refresh()
    }

    deinit {
        pollTask?.cancel()
        pendingRefresh?.cancel()
    }

    private func installListListener() {
        // List changes (process appeared / exited) arrive as HAL notifications.
        listListener = AudioObjectID.system.listen(kAudioHardwarePropertyProcessObjectList) {
            Task { @MainActor [weak self] in self?.scheduleRefresh() }
        }
    }

    /// Coalesces listener bursts: HAL fires once per process and once per
    /// output-state flip, often a dozen times within a few milliseconds.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        guard let objectIDs = try? AudioObjectID.readProcessList() else {
            Self.logger.error("Failed to read HAL process list")
            return
        }

        let currentIDs = Set(objectIDs)
        for id in stateListeners.keys where !currentIDs.contains(id) { stateListeners[id] = nil }
        for id in objectIDs where stateListeners[id] == nil {
            stateListeners[id] = [kAudioProcessPropertyIsRunningOutput, kAudioProcessPropertyIsRunningInput].compactMap { selector in
                id.listen(selector) { [weak self] in
                    Task { @MainActor in self?.scheduleRefresh() }
                }
            }
        }

        struct Group {
            let app: NSRunningApplication
            var objects: [AudioObjectID] = []
            var playing = false
            var recording = false
        }
        var groups: [pid_t: Group] = [:]

        for objectID in objectIDs {
            guard let pid = try? objectID.readProcessPID() else { continue }

            // Helper processes answer to the app the user knows; a browser tab's
            // audio belongs to the browser.
            let ownerPID = Self.responsiblePID(for: pid)
            let direct = NSRunningApplication(processIdentifier: pid)
            // A real application launched by Terminal or another app owns its
            // own audio; only background helper processes inherit an owner.
            let responsible = direct?.activationPolicy == .regular ? direct
                : (NSRunningApplication(processIdentifier: ownerPID) ?? direct)
            guard let running = responsible,
                let bundleID = running.bundleIdentifier,
                bundleID != Bundle.main.bundleIdentifier
            else { continue }

            let key = running.processIdentifier
            var group = groups[key] ?? Group(app: running)
            group.objects.append(objectID)
            group.playing = group.playing || objectID.readProcessIsRunningOutput()
            group.recording = group.recording || objectID.readProcessIsRunningInput()
            groups[key] = group
        }

        var nextApps = groups.compactMap { pid, group -> AudioApp? in
            // Regular apps always; agents and helpers only while they actually
            // play or record — keeps Control Center, Siri, and GPU helpers out
            // without dropping background recorders (meeting helpers).
            guard group.app.activationPolicy == .regular || group.playing || group.recording
            else { return nil }
            let bundleID = group.app.bundleIdentifier ?? ""
            let signal = playbackSignal(bundleID: bundleID, objects: group.objects.sorted(), outputRunning: group.playing)
            let measured = signal?.hasReceivedAudio == true
            return AudioApp(
                id: pid,
                bundleID: group.app.bundleIdentifier ?? "",
                name: group.app.localizedName ?? group.app.bundleIdentifier ?? "pid \(pid)",
                objectIDs: group.objects.sorted(),
                isPlaying: measured ? signal!.isPlaying(now: DispatchTime.now().uptimeNanoseconds) : group.playing,
                isRecording: group.recording,
                isPlaybackMeasured: measured
            )
        }
        nextApps = AudioApp.coalescedByBundleID(nextApps)

        let runningBundles = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        nextApps = presence.reconcile(nextApps, runningBundles: runningBundles, now: ProcessInfo.processInfo.systemUptime)
        recentlyPlaying = presence.recentlyPlaying
        let present = Set(nextApps.filter { !$0.objectIDs.isEmpty }.map(\.bundleID))
        for id in meters.keys where !present.contains(id) { meters.removeValue(forKey: id)?.invalidate() }

        if nextApps != apps {
            apps = nextApps
            let names = nextApps.map { "\($0.name)\($0.isPlaying ? "*" : "")" }.joined(separator: ", ")
            // App names stay redacted in the unified log (default .private).
            Self.logger.info("Apps: \(nextApps.count)/\(objectIDs.count) HAL processes — \(names)")
        }
    }

    private func playbackSignal(bundleID: String, objects: [AudioObjectID], outputRunning: Bool) -> AudioSignalActivity? {
        if let existing = signalSource?(bundleID) {
            meters.removeValue(forKey: bundleID)?.invalidate()
            return existing
        }
        guard meteringVisible, !measurementSuspended else { return nil }
        if let meter = meters[bundleID], meter.processObjectIDs != objects || !meter.isAlive {
            meter.invalidate()
            meters[bundleID] = nil
        }
        if meters[bundleID] == nil, pendingMeters[bundleID] == nil, outputRunning, !failedMeters.contains(bundleID) {
            // HAL setup is not allowed to stall the menu bar or popover.
            pendingMeters[bundleID] = Task { @MainActor [weak self] in
                let result = await Task.detached(priority: .utility) { () -> ProcessTap? in
                    let meter = ProcessTap(processObjectIDs: objects, monitorOnly: true)
                    do {
                        let output = try AudioObjectID.readDefaultOutputDevice()
                        let uid = try output.readDeviceUID()
                        try meter.activate(outputs: [.init(uid: uid, id: output)])
                        return meter
                    } catch {
                        return nil // deinit destroys any partially built aggregate.
                    }
                }.value
                guard let self else { return }
                // A close, sleep, helper replacement, or newly created control
                // tap makes the result obsolete. Teardown cannot mute playback.
                guard !Task.isCancelled, meteringVisible, !measurementSuspended,
                    apps.contains(where: { $0.bundleID == bundleID && $0.objectIDs == objects }),
                    signalSource?(bundleID) == nil else {
                    result?.invalidate()
                    if !Task.isCancelled { pendingMeters[bundleID] = nil }
                    return
                }
                pendingMeters[bundleID] = nil
                if let result { meters[bundleID] = result }
                else { failedMeters.insert(bundleID) }
                scheduleRefresh()
            }
        }
        return meters[bundleID]?.activity
    }

    // MARK: - Responsible process lookup

    private typealias ResponsiblePIDFunction = @convention(c) (pid_t) -> pid_t

    /// `responsibility_get_pid_responsible_for_pid` maps helper processes to
    /// the app that spawned them — the same attribution TCC uses. Private SPI:
    /// not in any public header, but stable since macOS 10.14 and widely used
    /// in open-source tools. If it ever disappears, the `?? pid` fallback
    /// degrades gracefully to per-helper attribution (browser audio shows as
    /// its helper process instead of the browser).
    private static let responsiblePIDFunction: ResponsiblePIDFunction? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePIDFunction.self)
    }()

    private static func responsiblePID(for pid: pid_t) -> pid_t {
        guard let function = responsiblePIDFunction else { return pid }
        let owner = function(pid)
        return owner > 0 ? owner : pid
    }
}
