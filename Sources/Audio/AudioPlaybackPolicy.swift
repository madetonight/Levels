import Foundation
import Synchronization

/// Signal activity, not whether a process merely holds an output stream open.
/// The HAL thread publishes only a timestamp. No samples are retained.
final class AudioSignalActivity: Sendable {
    private let lastSignal = Atomic<UInt64>(0)
    private let received = Atomic<Bool>(false)
    static let threshold: Float = 0.0001 // -80 dBFS; excludes digital silence.
    static let holdNanoseconds: UInt64 = 200_000_000

    func observe(_ samples: UnsafePointer<Float>, count: Int, now: UInt64) {
        guard count > 0 else { return }
        received.store(true, ordering: .relaxed)
        for index in 0..<count {
            let sample = samples[index]
            if sample.isFinite && abs(sample) > Self.threshold {
                lastSignal.store(now, ordering: .relaxed)
                return
            }
        }
    }
    var hasReceivedAudio: Bool { received.load(ordering: .relaxed) }
    func isPlaying(now: UInt64) -> Bool {
        let last = lastSignal.load(ordering: .relaxed)
        return last > 0 && now >= last && now - last <= Self.holdNanoseconds
    }
}

/// Keep known audio apps visible for their open session, including pauses and
/// helper replacement. Cached rows never preserve obsolete HAL process IDs.
struct PlaybackPresence {
    private var previous: [String: AudioApp] = [:]
    private var lastPlaying: [String: TimeInterval] = [:]
    private(set) var recentlyPlaying: Set<String> = []
    static let grace: TimeInterval = 4

    mutating func reconcile(_ current: [AudioApp], runningBundles: Set<String>, now: TimeInterval) -> [AudioApp] {
        var next = Dictionary(uniqueKeysWithValues: AudioApp.coalescedByBundleID(current).map { ($0.bundleID, $0) })
        for app in current where app.isPlaying { lastPlaying[app.bundleID] = now }
        lastPlaying = lastPlaying.filter { runningBundles.contains($0.key) && now - $0.value <= Self.grace }
        recentlyPlaying = Set(lastPlaying.keys)
        for (id, app) in previous where next[id] == nil && runningBundles.contains(id) {
            // Empty IDs deliberately prevent creating a control tap for a
            // vanished helper. Stored controls apply once a new helper arrives.
            next[id] = AudioApp(id: app.id, bundleID: id, name: app.name,
                objectIDs: [], isPlaying: false, isRecording: false, isPlaybackMeasured: true)
        }
        previous = next
        return next.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Presentation only: a HAL process can exist just for alerts or microphone
/// access. Keep those idle apps available without crowding the playback list.
struct OutputAppSections {
    let primary: [AudioApp]
    let other: [AudioApp]

    private static let playbackApps: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition",
        "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
        "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.spotify.client", "com.apple.Music", "com.apple.TV",
        "com.apple.QuickTimePlayerX", "org.videolan.vlc", "com.colliderli.iina",
        "com.hnc.Discord", "com.tinyspeck.slackmacgap", "us.zoom.xos",
        "com.microsoft.teams2", "com.microsoft.teams"
    ]

    init(apps: [AudioApp], recentlyPlaying: Set<String>) {
        let sorted = AudioApp.coalescedByBundleID(apps).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let isPrimary: (AudioApp) -> Bool = {
            $0.isPlaying || recentlyPlaying.contains($0.bundleID)
                || Self.playbackApps.contains($0.bundleID)
        }
        primary = sorted.filter(isPrimary)
        other = sorted.filter { !isPrimary($0) }
    }
}
