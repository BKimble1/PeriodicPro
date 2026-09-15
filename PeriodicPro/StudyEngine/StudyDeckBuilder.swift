import Foundation

/// Builds flashcard and identify decks. Every function is deterministic for a
/// given seed so sessions can be verified in tests.
enum StudyDeckBuilder {
    static let defaultCardCount = 10

    /// How many elements one round draws from. Wide enough that ten cards are
    /// never the same ten twice over, narrow enough to stay focused on what the
    /// learner knows least well.
    static let defaultPoolSize = 40

    /// Alternates name→symbol and symbol→name so a deck never feels repetitive.
    static func flashcards(
        pool: [ChemicalElement],
        count: Int = defaultCardCount,
        seed: UInt64
    ) -> [StudyCard] {
        let subjects = pick(from: pool, count: count, seed: seed)
        return subjects.enumerated().map { index, element in
            if index.isMultiple(of: 2) {
                return StudyCard(
                    id: index,
                    element: element,
                    question: "What is the symbol?",
                    clue: .text(element.name),
                    answerTitle: element.symbol,
                    answerDetail: "\(element.name) \u{00B7} Atomic number \(element.atomicNumber)"
                )
            }
            return StudyCard(
                id: index,
                element: element,
                question: "Which element is this?",
                clue: .text(element.symbol),
                answerTitle: element.name,
                answerDetail: "Atomic number \(element.atomicNumber) \u{00B7} \(element.category.displayName)"
            )
        }
    }

    /// Identify cycles through a structure diagram, an atomic number and a
    /// written clue, so the learner recognizes elements more than one way.
    static func identifyCards(
        pool: [ChemicalElement],
        count: Int = defaultCardCount,
        seed: UInt64
    ) -> [StudyCard] {
        let subjects = pick(from: pool, count: count, seed: seed)
        return subjects.enumerated().map { index, element in
            let clue: StudyClue
            let question: String
            switch index % 3 {
            case 0:
                clue = .structure
                question = "What element is this?"
            case 1:
                clue = .text("\(element.atomicNumber)")
                question = "Which element has this atomic number?"
            default:
                clue = .description(hint(for: element))
                question = "What element is described?"
            }
            return StudyCard(
                id: index,
                element: element,
                question: question,
                clue: clue,
                answerTitle: element.name,
                answerDetail: "\(element.symbol) \u{00B7} Atomic number \(element.atomicNumber)"
            )
        }
    }

    /// A clue that describes an element without naming it or its symbol.
    static func hint(for element: ChemicalElement) -> String {
        var parts: [String] = ["\(element.category.displayName) in period \(element.period)"]
        if let group = element.group {
            parts.append("group \(group)")
        }
        parts.append(element.phase == .unknown
                     ? "state not established"
                     : "\(element.phase.displayName.lowercased()) at room temperature")
        return parts.joined(separator: ", ") + "."
    }

    /// Deterministic sample. When the pool is smaller than `count` the deck
    /// simply wraps around rather than returning a short deck.
    static func pick(from pool: [ChemicalElement], count: Int, seed: UInt64) -> [ChemicalElement] {
        guard !pool.isEmpty, count > 0 else { return [] }
        var generator = SeededGenerator(seed: seed)
        let shuffled = pool.shuffled(using: &generator)
        if shuffled.count >= count {
            return Array(shuffled.prefix(count))
        }
        var result: [ChemicalElement] = []
        result.reserveCapacity(count)
        var index = 0
        while result.count < count {
            result.append(shuffled[index % shuffled.count])
            index += 1
        }
        return result
    }
}
