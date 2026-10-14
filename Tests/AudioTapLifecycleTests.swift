import Testing

@Suite("Audio taps across sleep")
@MainActor
struct AudioTapLifecycleTests {
    private final class Tap: SleepManagedAudioTap {
        // Represents the bug: HAL still reports the object alive even when
        // audio IO has stopped. Recovery must release it regardless.
        let reportsAlive = true
        var isIntercepting = true
        var invalidations = 0
        func invalidate() {
            isIntercepting = false
            invalidations += 1
        }
    }

    @Test("sleep releases interception and rejects queued recreation")
    func sleepReleasesAudio() {
        let lifecycle = AudioTapLifecycle<Tap>()
        let browser = Tap()
        lifecycle.install(browser, for: "browser")
        lifecycle.prepareForSleep()
        #expect(browser.reportsAlive)
        #expect(!browser.isIntercepting)
        #expect(lifecycle.taps.isEmpty)
        let delayed = Tap()
        let installed = lifecycle.install(delayed, for: "browser")
        #expect(!installed)
        #expect(!delayed.isIntercepting)
        #expect(lifecycle.taps.isEmpty)
    }

    @Test("wake replaces stale live-looking resources, even without a sleep notice")
    func wakeRebuildsInsteadOfReusing() {
        let lifecycle = AudioTapLifecycle<Tap>()
        let stale = Tap()
        lifecycle.install(stale, for: "browser")
        lifecycle.prepareForWake()
        let fresh = Tap()
        lifecycle.install(fresh, for: "browser")
        #expect(stale.invalidations == 1)
        #expect(!stale.isIntercepting)
        #expect(lifecycle.taps["browser"] === fresh)
        #expect(fresh.isIntercepting)
        lifecycle.prepareForSleep()
        lifecycle.prepareForWake()
        #expect(fresh.invalidations == 1)
        #expect(!lifecycle.isSleeping)
        #expect(lifecycle.taps.isEmpty)
    }
}

@Suite("Audio handoff safety")
struct TapHandoffPolicyTests {
    @Test("an idle app that has never supplied buffers is not a failure")
    func waitingForFirstPlay() {
        #expect(TapHandoffPolicy.action(now: 100_000_000_000, lastCallback: 0, runningSince: nil, isAlive: true) == .wait)
    }
    @Test("playing drivers receive startup grace before a nonmuting rebuild")
    func initialGrace() {
        #expect(TapHandoffPolicy.action(now: 4_000_000_000, lastCallback: 0, runningSince: 1, isAlive: true) == .wait)
        #expect(TapHandoffPolicy.action(now: 6_000_000_000, lastCallback: 0, runningSince: 1, isAlive: true) == .recover)
    }
    @Test("paused streams restore native playback without an error")
    func pause() {
        #expect(TapHandoffPolicy.action(now: 6_000_000_000, lastCallback: 3_000_000_000, runningSince: nil, isAlive: true) == .releaseIdle)
    }
    @Test("resuming after a long pause gives IO a fresh startup grace period")
    func resume() {
        #expect(TapHandoffPolicy.action(now: 100_100_000_000, lastCallback: 3_000_000_000, runningSince: 100_000_000_000, isAlive: true) == .wait)
    }
    @Test("a playing app whose callbacks stop still fails open")
    func stalledAfterHandoff() {
        #expect(TapHandoffPolicy.action(now: 6_000_000_000, lastCallback: 3_000_000_000, runningSince: 1, isAlive: true) == .recover)
    }
    @Test("a live silent callback is healthy and dead aggregates always recover")
    func healthyIdleAndDeadDevice() {
        #expect(TapHandoffPolicy.action(now: 6_000_000_000, lastCallback: 5_900_000_000, runningSince: nil, isAlive: true) == .wait)
        #expect(TapHandoffPolicy.action(now: 6_000_000_000, lastCallback: 0, runningSince: nil, isAlive: false) == .recover)
    }
    @Test("retries are automatic, capped, and release the pending deadline when attempted")
    func retries() {
        var schedule = TapRecoverySchedule()
        schedule.failed("spotify", processes: [1, 2], now: 1)
        #expect(!schedule.canAttempt("spotify", processes: [1, 2], now: 1.4))
        #expect(schedule.canAttempt("spotify", processes: [1, 2], now: 1.5))
        schedule.attempted("spotify", processes: [1, 2])
        #expect(schedule.nextRetry == nil)
        schedule.failed("spotify", processes: [1, 2], now: 2)
        #expect(schedule.nextRetry == 3)
        for _ in 0..<15 { schedule.failed("spotify", processes: [1, 2], now: 4) }
        #expect(schedule.nextRetry == 34)
        #expect(schedule.canAttempt("spotify", processes: [3], now: 4))
        schedule.clear("spotify")
        #expect(schedule.entries.isEmpty)
    }
    @Test("one app's failure neither blocks other apps nor survives helper replacement")
    func independentApps() {
        var schedule = TapRecoverySchedule()
        schedule.failed("spotify", processes: [1], now: 100)
        #expect(schedule.canAttempt("browser", processes: [2], now: 100))
        schedule.attempted("spotify", processes: [3])
        #expect(schedule.entries.isEmpty)
        schedule.failed("quit-app", processes: [4], now: 100)
        schedule.retain(["spotify"])
        #expect(schedule.entries.isEmpty)
    }
}
