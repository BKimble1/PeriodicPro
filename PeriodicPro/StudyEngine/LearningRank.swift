import Foundation

/// How far through the periodic table the learner has come.
///
/// Not a leaderboard and not a comparison with anybody. Elemora has no
/// accounts, no server and nobody else's numbers; this is one person's
/// progress, named, so that "42 of 118 mastered" has a shape as well as a
/// number.
///
/// The names are deliberately about the work rather than about the person:
/// none of them implies a qualification, and the highest is what somebody who
/// has learned the table is, not what they are licensed to do.
enum LearningRank: Int, CaseIterable, Comparable, Identifiable, Codable, Sendable {
    case explorer = 0
    case pathfinder
    case patternReader
    case bondBuilder
    case periodicAnalyst
    case chemistryScholar
    case elementSpecialist
    case periodicMaster

    var id: Int { rawValue }

    static func < (lhs: LearningRank, rhs: LearningRank) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .explorer: return "Element Explorer"
        case .pathfinder: return "Periodic Pathfinder"
        case .patternReader: return "Pattern Reader"
        case .bondBuilder: return "Bond Builder"
        case .periodicAnalyst: return "Periodic Analyst"
        case .chemistryScholar: return "Chemistry Scholar"
        case .elementSpecialist: return "Element Specialist"
        case .periodicMaster: return "Periodic Master"
        }
    }

    /// One line about what this rank represents.
    var summary: String {
        switch self {
        case .explorer: return "Finding your way around the table."
        case .pathfinder: return "The main groups are starting to be familiar territory."
        case .patternReader: return "You are reading the table by its patterns, not one tile at a time."
        case .bondBuilder: return "Compounds as well as elements."
        case .periodicAnalyst: return "Trends, families and the reasons behind them."
        case .chemistryScholar: return "Breadth across the table and depth in the harder questions."
        case .elementSpecialist: return "Most of the table mastered, and the calculations with it."
        case .periodicMaster: return "The whole table, the compounds, and the chemistry underneath."
        }
    }

    /// The score at which this rank begins, out of 1.
    var threshold: Double {
        switch self {
        // The first step is above 0.10 deliberately: consistency is a tenth
        // of the score on its own, and turning up every day without learning
        // anything is not a rank.
        case .explorer: return 0
        case .pathfinder: return 0.12
        case .patternReader: return 0.22
        case .bondBuilder: return 0.34
        case .periodicAnalyst: return 0.47
        case .chemistryScholar: return 0.60
        case .elementSpecialist: return 0.76
        case .periodicMaster: return 0.90
        }
    }

    var next: LearningRank? { LearningRank(rawValue: rawValue + 1) }

    /// A shape as well as a color, so the rank is never carried by color
    /// alone.
    var symbolName: String {
        switch self {
        case .explorer: return "circle.dotted"
        case .pathfinder: return "circle.lefthalf.filled"
        case .patternReader: return "circle.righthalf.filled"
        case .bondBuilder: return "hexagon"
        case .periodicAnalyst: return "hexagon.fill"
        case .chemistryScholar: return "diamond.fill"
        case .elementSpecialist: return "seal.fill"
        case .periodicMaster: return "laurel.leading"
        }
    }
}

/// What the learner's rank is, and why.
struct RankStanding: Equatable, Sendable {
    let rank: LearningRank
    /// The overall score, 0 to 1.
    let score: Double
    /// Each component, so the screen can say what is holding the rank back
    /// rather than showing a number with no explanation.
    let elementBreadth: Double
    let compoundBreadth: Double
    let questionDepth: Double
    let reviewConsistency: Double
    let pathCompletion: Double

    /// How far from here to the next rank, 0 to 1. One when there is no next.
    var progressToNext: Double {
        guard let next = rank.next else { return 1 }
        let span = next.threshold - rank.threshold
        guard span > 0 else { return 1 }
        return min(1, max(0, (score - rank.threshold) / span))
    }

    /// The component with the most room in it: what to work on.
    var weakestComponent: String {
        let components: [(String, Double)] = [
            ("elements", elementBreadth),
            ("compounds", compoundBreadth),
            ("harder questions", questionDepth),
            ("regular review", reviewConsistency),
            ("the learning path", pathCompletion),
        ]
        return components.min { $0.1 < $1.1 }?.0 ?? "elements"
    }
}

/// Works out the rank, deterministically.
///
/// The weights exist to make one thing impossible: reaching the top by
/// answering hydrogen ten thousand times. Breadth across the 118 elements is
/// forty percent of the score and is measured as coverage — how much of the
/// table has been learned — not as a count of answers, so repetition on a
/// small set saturates almost immediately and then contributes nothing more.
///
/// * 40% element breadth and mastery, across all 118
/// * 20% compound breadth and mastery
/// * 20% success on the harder question types
/// * 10% review consistency — turning up, not cramming
/// * 10% learning-path completion
///
/// A rank does not fall because the learner skipped two days. The score is
/// built from what they have learned, which does not un-happen; what does
/// change day to day is how much is due for review, and that is reported
/// separately.
enum LearningRankCalculator {
    /// How many compounds count as full breadth.
    ///
    /// Not the size of the catalog, which would make the compound term a
    /// function of how many compounds happen to be bundled. Thirty is a
    /// working chemistry vocabulary.
    static let compoundBreadthTarget = 30

    /// How many days of study in the last month count as full consistency.
    static let consistencyTarget = 12

    static func standing(
        elements: [Int: ElementProgressSnapshot],
        elementCount: Int,
        compounds: [String: CompoundProgressSnapshot],
        hardQuestionsCorrect: Int,
        hardQuestionsAnswered: Int,
        studyDaysInLastMonth: Int,
        pathCompletion: Double
    ) -> RankStanding {
        let elementBreadth = breadth(
            levels: elements.values.map(\.mastery), target: max(elementCount, 1)
        )
        let compoundBreadth = breadth(
            levels: compounds.values.map(\.mastery), target: compoundBreadthTarget
        )
        let depth = questionDepth(correct: hardQuestionsCorrect, answered: hardQuestionsAnswered)
        let consistency = min(1, Double(studyDaysInLastMonth) / Double(consistencyTarget))
        let path = min(1, max(0, pathCompletion))

        let score = elementBreadth * 0.40
            + compoundBreadth * 0.20
            + depth * 0.20
            + consistency * 0.10
            + path * 0.10

        return RankStanding(
            rank: rank(for: score),
            score: min(1, max(0, score)),
            elementBreadth: elementBreadth,
            compoundBreadth: compoundBreadth,
            questionDepth: depth,
            reviewConsistency: consistency,
            pathCompletion: path
        )
    }

    /// Coverage, not volume.
    ///
    /// Each item contributes according to how well it is known, and the total
    /// is divided by the whole target — so a hundred answers spread over one
    /// element is worth one element's coverage, which out of 118 is under one
    /// percent, and no amount of further drilling on it changes that.
    static func breadth(levels: [MasteryLevel], target: Int) -> Double {
        guard target > 0 else { return 0 }
        let earned = levels.reduce(0.0) { running, level in
            running + credit(for: level)
        }
        return min(1, earned / Double(target))
    }

    /// What one item is worth at each familiarity.
    static func credit(for level: MasteryLevel) -> Double {
        switch level {
        case .notStarted: return 0
        case .learning: return 0.25
        case .familiar: return 0.6
        case .mastered: return 1
        }
    }

    /// Success on the harder questions, discounted until enough have been
    /// answered for the rate to mean anything.
    ///
    /// Without the discount, one hard question answered correctly would read
    /// as a hundred percent, which is a fifth of the whole score for a single
    /// lucky tap.
    static func questionDepth(correct: Int, answered: Int) -> Double {
        guard answered > 0 else { return 0 }
        let accuracy = Double(correct) / Double(answered)
        let confidence = min(1, Double(answered) / 40)
        return accuracy * confidence
    }

    static func rank(for score: Double) -> LearningRank {
        var found = LearningRank.explorer
        for rank in LearningRank.allCases where score >= rank.threshold {
            found = rank
        }
        return found
    }
}
