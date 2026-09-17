import CoreGraphics
import Foundation

/// Decides when the camera has settled on something.
///
/// Text recognition answers several times a second, and most of those answers
/// are wrong for a moment: a half-framed word, a blurred digit, a formula
/// caught mid-pan. Opening a compound's page on the first frame that parses
/// would open the wrong one constantly.
///
/// So a candidate has to earn it. The same normalized text, in roughly the
/// same place in the frame, above a confidence floor, on several consecutive
/// analyses spanning at least `minimumDuration` — then it is what the learner
/// is pointing at, and not before. Anything else resets the count, so a pan
/// across a page cannot accumulate a result out of unrelated frames.
///
/// Pure and deterministic: the clock is passed in, so the whole rule is
/// unit-tested rather than felt for with a phone.
struct ScanStabilizer: Sendable {
    /// How many consecutive sightings a candidate needs.
    var requiredSightings = 3
    /// And how long those sightings must span.
    var minimumDuration: Duration = .milliseconds(400)
    /// Below this, Vision is not confident enough to act on.
    var minimumConfidence: Double = 0.45
    /// How far the box may move between sightings, as a fraction of the
    /// frame, before it counts as a different thing.
    var maximumDrift: CGFloat = 0.25
    /// How long after a result the scanner ignores everything, so the sheet
    /// is not immediately replaced by the next frame's reading.
    var settleAfterResult: Duration = .milliseconds(900)

    private var trackedID: String?
    private var sightings = 0
    private var firstSeen: ContinuousClock.Instant?
    private var lastBounds: CGRect = .zero
    private var suppressedUntil: ContinuousClock.Instant?

    init() {}

    /// Feeds one frame's best candidate in and gets back a result when the
    /// scanner is sure. `nil` every other time.
    mutating func observe(
        _ candidate: ScanCandidate?,
        at now: ContinuousClock.Instant = .now
    ) -> ScanCandidate? {
        if let suppressedUntil, now < suppressedUntil { return nil }
        suppressedUntil = nil

        guard let candidate, candidate.confidence >= minimumConfidence else {
            reset()
            return nil
        }

        let isSameThing = candidate.id == trackedID && !drifted(to: candidate.bounds)
        if isSameThing {
            sightings += 1
        } else {
            trackedID = candidate.id
            sightings = 1
            firstSeen = now
        }
        lastBounds = candidate.bounds

        guard sightings >= requiredSightings, let firstSeen,
              firstSeen.duration(to: now) >= minimumDuration else { return nil }

        // Delivered. Hold everything for a beat so the result the learner is
        // reading is not replaced by whatever the next frame happens to see.
        suppressedUntil = now.advanced(by: settleAfterResult)
        reset()
        return candidate
    }

    /// Called when the learner asks to keep scanning.
    mutating func resume(at now: ContinuousClock.Instant = .now) {
        reset()
        suppressedUntil = now.advanced(by: settleAfterResult)
    }

    mutating func reset() {
        trackedID = nil
        sightings = 0
        firstSeen = nil
        lastBounds = .zero
    }

    /// How close the scanner is to a result, 0 to 1 — for the ring that fills
    /// while the learner holds the phone still.
    var progress: Double {
        guard requiredSightings > 0 else { return 0 }
        return min(1, Double(sightings) / Double(requiredSightings))
    }

    private func drifted(to bounds: CGRect) -> Bool {
        guard lastBounds != .zero else { return false }
        return abs(bounds.midX - lastBounds.midX) > maximumDrift
            || abs(bounds.midY - lastBounds.midY) > maximumDrift
    }
}
