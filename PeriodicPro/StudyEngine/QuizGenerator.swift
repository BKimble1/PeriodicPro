import Foundation

/// Builds a short multiple-choice quiz from the catalog.
///
/// Fully deterministic: the same `(pool, count, seed)` always produces the same
/// questions, options and answer positions.
enum QuizGenerator {
    static let defaultQuestionCount = 10
    static let optionCount = 4

    static func makeQuiz(
        pool: [ChemicalElement],
        distractors: [ChemicalElement],
        count: Int = defaultQuestionCount,
        seed: UInt64
    ) -> [QuizQuestion] {
        guard !pool.isEmpty else { return [] }
        let subjects = StudyDeckBuilder.pick(from: pool, count: count, seed: seed)
        let answerPool = distractors.isEmpty ? pool : distractors
        var generator = SeededGenerator(seed: seed &+ 0x5DEE_CE66)
        let kinds = QuizQuestion.Kind.allCases

        return subjects.enumerated().compactMap { index, element in
            let kind = kinds[index % kinds.count]
            return makeQuestion(
                id: index,
                kind: kind,
                element: element,
                answerPool: answerPool,
                generator: &generator
            )
        }
    }

    static func makeQuestion(
        id: Int,
        kind: QuizQuestion.Kind,
        element: ChemicalElement,
        answerPool: [ChemicalElement],
        generator: inout SeededGenerator
    ) -> QuizQuestion? {
        let prompt: String
        let correct: String
        let candidates: [String]

        switch kind {
        case .symbolForName:
            prompt = "What is the symbol for \(element.name)?"
            correct = element.symbol
            candidates = answerPool.filter { $0.atomicNumber != element.atomicNumber }.map(\.symbol)
        case .nameForSymbol:
            prompt = "Which element is \(element.symbol)?"
            correct = element.name
            candidates = answerPool.filter { $0.atomicNumber != element.atomicNumber }.map(\.name)
        case .numberForName:
            prompt = "What is the atomic number of \(element.name)?"
            correct = "\(element.atomicNumber)"
            candidates = answerPool
                .filter { $0.atomicNumber != element.atomicNumber }
                .map { "\($0.atomicNumber)" }
        case .familyForElement:
            prompt = "Which family does \(element.name) belong to?"
            correct = element.category.displayName
            candidates = ElementCategory.allCases
                .filter { $0 != element.category }
                .map(\.displayName)
        }

        // Deduplicate, drop anything equal to the answer, then take a stable
        // random sample so the wrong options differ every run but replay
        // identically for the same seed.
        var seen = Set<String>([correct])
        var unique: [String] = []
        for candidate in candidates.shuffled(using: &generator) where !seen.contains(candidate) {
            seen.insert(candidate)
            unique.append(candidate)
            if unique.count == optionCount - 1 { break }
        }

        guard !unique.isEmpty else { return nil }

        var options = unique + [correct]
        options.shuffle(using: &generator)
        guard let correctIndex = options.firstIndex(of: correct) else { return nil }

        return QuizQuestion(
            id: id,
            kind: kind,
            element: element,
            prompt: prompt,
            options: options,
            correctIndex: correctIndex
        )
    }
}
