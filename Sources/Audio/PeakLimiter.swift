import Foundation

/// Linked-channel peak limiter. Instant attack, 80 ms release, and -0.18 dB
/// headroom. State belongs to one IO stream; no allocation or locks in render.
/// This prevents digital overs without adding latency or changing quiet audio.
struct PeakLimiter {
    static let ceiling: Float = 0.98
    private(set) var reduction: Float = 1
    private var release: Float

    init(sampleRate: Double = 48_000) {
        let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        release = 1 - exp(-1 / (Float(rate) * 0.080))
    }

    var isReducing: Bool { reduction < 1 }

    mutating func process(frame: UnsafeMutablePointer<Float>, channels: Int) {
        var peak: Float = 0
        for channel in 0..<channels {
            if !frame[channel].isFinite { frame[channel] = 0 }
            peak = max(peak, abs(frame[channel]))
        }
        let required = peak > Self.ceiling ? Self.ceiling / peak : 1
        if required < reduction {
            reduction = required
        } else {
            reduction = min(required, reduction + (1 - reduction) * release)
            if 1 - reduction < 1e-6 { reduction = 1 }
        }
        for channel in 0..<channels { frame[channel] *= reduction }
    }
}
