/// Slider-position → amplitude-gain mapping for the per-app process tap.
///
/// A linear position→amplitude map crams every audible step into the bottom
/// of the travel — 0.5 is only −6 dB, still loud, then the last sliver does
/// everything (the "loud, then nothing" complaint). The system volume slider
/// tapers, so the per-app tap must too or the two controls feel nothing alike.
/// Cube law is the standard audio-fader taper: equal slider travel ≈ equal
/// perceived-loudness change. Kept pure and free of HAL imports so it unit-tests
/// in the hostless bundle.
enum VolumeTaper {
    static let maximumPosition: Float = 2

    static func clampedPosition(_ position: Float) -> Float {
        position.isFinite ? max(0, min(maximumPosition, position)) : 1
    }

    static func gain(position: Float) -> Float {
        let p = clampedPosition(position)
        // Preserve every existing 0–100% setting. Boost uses amplitude gain,
        // rather than cubing above unity (200% must not become 8× gain).
        return p <= 1 ? p * p * p : p
    }
}
