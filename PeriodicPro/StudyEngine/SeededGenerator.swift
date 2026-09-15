import Foundation

/// SplitMix64. Small, fast and — crucially — reproducible, so every quiz and
/// deck built from the same seed is identical and therefore testable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the all-zero state, which would make the sequence degenerate.
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension SeededGenerator {
    /// A seed derived from the current day so "today's session" is stable if
    /// the learner backs out and returns, but changes tomorrow.
    static func dailySeed(for date: Date = Date(), calendar: Calendar = .current) -> UInt64 {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = UInt64(components.year ?? 2_026)
        let month = UInt64(components.month ?? 1)
        let day = UInt64(components.day ?? 1)
        return year &* 10_000 &+ month &* 100 &+ day
    }
}
