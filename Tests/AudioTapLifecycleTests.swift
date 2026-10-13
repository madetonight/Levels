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
