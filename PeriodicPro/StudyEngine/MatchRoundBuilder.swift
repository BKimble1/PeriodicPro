import Foundation

/// One pair in a Match round: a prompt on the left, its answer on the right.
struct MatchPair: Identifiable, Hashable, Sendable {
    let id: Int
    let subject: QuizSubject
    /// "Sodium" or "Sodium chloride".
    let prompt: String
    /// "Na" or "NaCl".
    let answer: String
}

/// A dealt Match round: the pairs, and the two shuffled column orders.
struct MatchRound: Hashable, Sendable {
    let pairs: [MatchPair]
    /// Pair identifiers in the order the prompts are shown.
    let promptOrder: [Int]
    /// Pair identifiers in the order the answers are shown.
    let answerOrder: [Int]

    func pair(id: Int) -> MatchPair? { pairs.first { $0.id == id } }
}

/// Deals Match rounds. Deterministic for a seed, like everything else here.
///
/// Two rules keep a round fair: no subject appears twice, and no two pairs
/// share an answer — ethanol and dimethyl ether are both C₂H₆O, and a round
/// that showed that formula twice would have two right answers for one card.
enum MatchRoundBuilder {
    static let defaultPairCount = 8

    static func round(subjects: [QuizSubject], pairCount: Int, seed: UInt64) -> MatchRound {
        var generator = SeededGenerator(seed: seed &+ 0x3C6E_F372)
        let shuffled = subjects.shuffled(using: &generator)
        var pairs: [MatchPair] = []
        var seenSubjects = Set<String>()
        var seenAnswers = Set<String>()
        var seenPrompts = Set<String>()
        for subject in shuffled {
            guard pairs.count < max(pairCount, 0) else { break }
            guard seenSubjects.insert(subject.key).inserted else { continue }
            let (prompt, answer) = faces(of: subject)
            guard seenAnswers.insert(answer).inserted, seenPrompts.insert(prompt).inserted else { continue }
            pairs.append(MatchPair(id: pairs.count, subject: subject, prompt: prompt, answer: answer))
        }
        var promptGenerator = SeededGenerator(seed: seed &+ 0x1B87_3593)
        var answerGenerator = SeededGenerator(seed: seed &+ 0x7F4A_7C15)
        let ids = pairs.map(\.id)
        return MatchRound(
            pairs: pairs,
            promptOrder: ids.shuffled(using: &promptGenerator),
            answerOrder: ids.shuffled(using: &answerGenerator)
        )
    }

    /// What goes on each side of the card.
    static func faces(of subject: QuizSubject) -> (prompt: String, answer: String) {
        switch subject {
        case .element(let element):
            return (element.name, element.symbol)
        case .compound(let compound):
            return (compound.preferredName, compound.displayFormula)
        }
    }
}
