import Foundation

/// Builds a round from the elements the learner actually keeps getting wrong.
///
/// Deliberately not spaced repetition. There is no forgetting curve, no
/// interval schedule and no extra stored state — it reads the mastery data the
/// app already keeps and sorts it. That is enough to be genuinely useful, and
/// it is small enough to be completely testable.
enum SmartReviewBuilder {
    /// Below this, there is not enough history for a review to mean anything,
    /// and the honest answer is to say so rather than to quietly serve a normal
    /// round under a different name.
    static let minimumAttemptedElements = 5

    /// Weakest first.
    ///
    /// The order is, in turn:
    /// 1. how many times the element has been answered incorrectly, most first;
    /// 2. how familiar it is, least familiar first;
    /// 3. how long ago it was last seen, longest first;
    /// 4. atomic number, so the result is deterministic and testable.
    ///
    /// Elements that have never been attempted are excluded: this is a review of
    /// what went wrong, not a first introduction.
    static func ranked(_ snapshots: [ElementProgressSnapshot]) -> [ElementProgressSnapshot] {
        snapshots
            .filter { $0.attempts > 0 }
            .sorted { lhs, rhs in
                if lhs.incorrectCount != rhs.incorrectCount {
                    return lhs.incorrectCount > rhs.incorrectCount
                }
                if lhs.mastery != rhs.mastery {
                    return lhs.mastery < rhs.mastery
                }
                switch (lhs.lastReviewed, rhs.lastReviewed) {
                case let (left?, right?) where left != right:
                    return left < right
                case (nil, .some):
                    return true
                case (.some, nil):
                    return false
                default:
                    break
                }
                return lhs.atomicNumber < rhs.atomicNumber
            }
    }

    /// Whether Smart Review has anything to work with yet.
    static func isAvailable(snapshots: [Int: ElementProgressSnapshot]) -> Bool {
        snapshots.values.filter { $0.attempts > 0 }.count >= minimumAttemptedElements
    }

    /// Explains why the mode is not ready, or `nil` when it is.
    static func unavailableReason(snapshots: [Int: ElementProgressSnapshot]) -> String? {
        guard !isAvailable(snapshots: snapshots) else { return nil }
        let attempted = snapshots.values.filter { $0.attempts > 0 }.count
        let needed = minimumAttemptedElements - attempted
        return "Smart Review builds from the elements you miss. Answer \(needed) more "
            + (needed == 1 ? "element" : "elements")
            + " in any mode and it will be ready."
    }

    /// The pool a Smart Review round draws from: the weakest elements first,
    /// topped up from the normal study priority if there are not enough of them
    /// to fill a round.
    ///
    /// The top-up matters — with only six weak elements a ten-card round would
    /// otherwise have to repeat four of them, and seeing the same card twice in
    /// one round reads as a bug.
    static func queue(
        elements: [ChemicalElement],
        snapshots: [Int: ElementProgressSnapshot],
        poolSize: Int = StudyDeckBuilder.defaultPoolSize
    ) -> [ChemicalElement] {
        let byNumber = Dictionary(
            elements.map { ($0.atomicNumber, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var ordered: [ChemicalElement] = []
        var seen: Set<Int> = []
        for snapshot in ranked(Array(snapshots.values)) {
            guard let element = byNumber[snapshot.atomicNumber] else { continue }
            guard seen.insert(element.atomicNumber).inserted else { continue }
            ordered.append(element)
        }

        if ordered.count < poolSize {
            let fill = MasteryEngine.studyPriority(elements) {
                snapshots[$0]?.mastery ?? .notStarted
            }
            for element in fill where !seen.contains(element.atomicNumber) {
                ordered.append(element)
                seen.insert(element.atomicNumber)
                if ordered.count >= poolSize { break }
            }
        }

        return ordered
    }
}
