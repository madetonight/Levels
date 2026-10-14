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
    @Test("HAL objects without working callbacks fail open")
    func noCallbacks() {
        #expect(!TapHandoffPolicy.isStalled(now: 2_000_000_000, activatedAt: 1, lastCallback: 0))
        #expect(TapHandoffPolicy.isStalled(now: 3_000_000_000, activatedAt: 1, lastCallback: 0))
    }
    @Test("a callback that stops after takeover fails open")
    func stalledAfterHandoff() {
        #expect(TapHandoffPolicy.isStalled(now: 6_000_000_000, activatedAt: 1, lastCallback: 3_000_000_000))
    }
    @Test("digital silence still counts as healthy IO")
    func healthyIdle() {
        #expect(!TapHandoffPolicy.isStalled(now: 6_000_000_000, activatedAt: 1, lastCallback: 5_900_000_000))
    }
}
