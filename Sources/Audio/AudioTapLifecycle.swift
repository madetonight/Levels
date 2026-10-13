/// Audio resources must not survive system sleep just because their device
/// objects still exist. A surviving object does not guarantee live audio IO.
protocol SleepManagedAudioTap: AnyObject {
    @MainActor func invalidate()
}

@MainActor
final class AudioTapLifecycle<Tap: SleepManagedAudioTap> {
    var taps: [String: Tap] = [:]
    private(set) var isSleeping = false

    func prepareForSleep() {
        isSleeping = true
        discard()
    }

    func prepareForWake() {
        // Also covers a missed willSleep notification: no pre-wake IO survives.
        discard()
        isSleeping = false
    }

    @discardableResult
    func install(_ tap: Tap, for app: String) -> Bool {
        guard !isSleeping else {
            tap.invalidate()
            return false
        }
        taps.removeValue(forKey: app)?.invalidate()
        taps[app] = tap
        return true
    }

    func discard() {
        let previous = taps
        taps.removeAll()
        for tap in previous.values { tap.invalidate() }
    }
}
