import Foundation

/// Builds a multiple-choice round from a pool of subjects.
///
/// Fully deterministic: the same `(subjects, difficulty, count, seed)` always
/// produces the same questions, options and answer positions — which is what
/// makes a frozen deck testable, and what lets a shared quiz replay for two
/// learners with the same seed.
enum QuizGenerator {
    static let defaultQuestionCount = 10
    static let optionCount = 4

    /// The original Quick Quiz: elements only, the four classic question types.
    static func makeQuiz(
        pool: [ChemicalElement],
        distractors: [ChemicalElement],
        count: Int = defaultQuestionCount,
        seed: UInt64
    ) -> [QuizQuestion] {
        makeQuiz(
            subjects: pool.map(QuizSubject.element),
            elementDistractors: distractors.isEmpty ? pool : distractors,
            compoundDistractors: [],
            kinds: QuizQuestion.Kind.classic,
            count: count,
            seed: seed
        )
    }

    /// A configured round: elements and compounds, at a difficulty.
    static func makeQuiz(
        subjects: [QuizSubject],
        elementDistractors: [ChemicalElement],
        compoundDistractors: [ChemicalCompound],
        difficulty: QuizDifficulty,
        count: Int,
        seed: UInt64,
        shuffles: Bool = true
    ) -> [QuizQuestion] {
        makeQuiz(
            subjects: subjects,
            elementDistractors: elementDistractors,
            compoundDistractors: compoundDistractors,
            kinds: difficulty.elementKinds + difficulty.compoundKinds,
            count: count,
            seed: seed,
            shuffles: shuffles
        )
    }

    /// The general form. `kinds` is the menu of question types; each subject
    /// gets the next type that applies to it, so a mixed round really mixes.
    static func makeQuiz(
        subjects: [QuizSubject],
        elementDistractors: [ChemicalElement],
        compoundDistractors: [ChemicalCompound],
        kinds: [QuizQuestion.Kind],
        count: Int,
        seed: UInt64,
        shuffles: Bool = true
    ) -> [QuizQuestion] {
        guard !subjects.isEmpty, count > 0 else { return [] }
        let dealt = pick(from: subjects, count: count, seed: seed, shuffles: shuffles)
        var generator = SeededGenerator(seed: seed &+ 0x5DEE_CE66)
        let elementKinds = kinds.filter { !$0.isAboutCompound }
        let compoundKinds = kinds.filter(\.isAboutCompound)
        // Rotate the menus by the seed so the first question is not always
        // the same type.
        var elementCursor = elementKinds.isEmpty ? 0 : Int(generator.next() % UInt64(elementKinds.count))
        var compoundCursor = compoundKinds.isEmpty ? 0 : Int(generator.next() % UInt64(compoundKinds.count))

        var questions: [QuizQuestion] = []
        for subject in dealt {
            let question: QuizQuestion?
            switch subject {
            case .element(let element):
                let menu = elementKinds.isEmpty ? QuizQuestion.Kind.classic : elementKinds
                let kind = menu[elementCursor % menu.count]
                elementCursor += 1
                question = makeQuestion(
                    id: questions.count, kind: kind, element: element,
                    answerPool: elementDistractors, generator: &generator
                )
            case .compound(let compound):
                let menu = compoundKinds.isEmpty
                    ? [QuizQuestion.Kind.formulaForCompound, .compoundForFormula]
                    : compoundKinds
                let kind = menu[compoundCursor % menu.count]
                compoundCursor += 1
                question = makeQuestion(
                    id: questions.count, kind: kind, compound: compound,
                    compoundPool: compoundDistractors, elementPool: elementDistractors, generator: &generator
                )
            }
            if let question { questions.append(question) }
        }
        return questions
    }

    /// Deterministic sample. Shuffled, or in the pool's own order; when the
    /// pool is smaller than `count` the deck wraps around rather than
    /// coming up short.
    static func pick(from subjects: [QuizSubject], count: Int, seed: UInt64, shuffles: Bool) -> [QuizSubject] {
        guard !subjects.isEmpty, count > 0 else { return [] }
        var generator = SeededGenerator(seed: seed)
        let ordered = shuffles ? subjects.shuffled(using: &generator) : subjects
        if ordered.count >= count { return Array(ordered.prefix(count)) }
        var result: [QuizSubject] = []
        var index = 0
        while result.count < count {
            result.append(ordered[index % ordered.count])
            index += 1
        }
        return result
    }

    // MARK: - Element questions

    static func makeQuestion(
        id: Int,
        kind: QuizQuestion.Kind,
        element: ChemicalElement,
        answerPool: [ChemicalElement],
        generator: inout SeededGenerator
    ) -> QuizQuestion? {
        let others = answerPool.filter { $0.atomicNumber != element.atomicNumber }
        let prompt: String
        let correct: String
        let candidates: [String]
        var detail: String? = "\(element.name) · \(element.symbol) · atomic number \(element.atomicNumber)"

        switch kind {
        case .symbolForName:
            prompt = "What is the symbol for \(element.name)?"
            correct = element.symbol
            candidates = others.map(\.symbol)
        case .nameForSymbol:
            prompt = "Which element is \(element.symbol)?"
            correct = element.name
            candidates = others.map(\.name)
        case .numberForName:
            prompt = "What is the atomic number of \(element.name)?"
            correct = "\(element.atomicNumber)"
            candidates = others.map { "\($0.atomicNumber)" }
        case .familyForElement:
            prompt = "Which family does \(element.name) belong to?"
            correct = element.category.displayName
            candidates = ElementCategory.allCases.filter { $0 != element.category }.map(\.displayName)
        case .phaseForElement:
            guard element.phase != .unknown else {
                return makeQuestion(id: id, kind: .numberForName, element: element,
                                    answerPool: answerPool, generator: &generator)
            }
            prompt = "At room temperature, \(element.name.lowercased()) is a…"
            correct = element.phase.displayName
            candidates = [MatterPhase.solid, .liquid, .gas].filter { $0 != element.phase }.map(\.displayName)
        case .periodForElement:
            prompt = "Which period of the table is \(element.name) in?"
            correct = "Period \(element.period)"
            candidates = (1...7).filter { $0 != element.period }.map { "Period \($0)" }
        case .groupForElement:
            guard let group = element.group else {
                // The f-block has no group: keep the question at the same
                // difficulty rather than dropping to a medium one.
                return makeQuestion(id: id, kind: .massForElement, element: element,
                                    answerPool: answerPool, generator: &generator)
            }
            prompt = "Which group is \(element.name) in?"
            correct = "Group \(group)"
            candidates = (1...18).filter { $0 != group }.map { "Group \($0)" }
        case .configurationForElement:
            prompt = "Which is the electron configuration of \(element.name)?"
            correct = element.formattedElectronConfiguration
            candidates = others.map(\.formattedElectronConfiguration)
        case .massForElement:
            prompt = "Which is the standard atomic mass of \(element.name)?"
            correct = element.formattedAtomicMass
            candidates = others.map(\.formattedAtomicMass)
            detail = element.atomicMassFootnote.map { "\(element.name): \(element.formattedAtomicMass), \($0)" }
                ?? "\(element.name): \(element.formattedAtomicMass)"
        case .elementForClue:
            prompt = "Which element is described? " + StudyDeckBuilder.hint(for: element)
            correct = element.name
            candidates = others.map(\.name)
        default:
            return nil
        }

        return assemble(id: id, kind: kind, subject: .element(element), prompt: prompt, correct: correct,
                        candidates: candidates, detail: detail, generator: &generator)
    }

    // MARK: - Compound questions

    static func makeQuestion(
        id: Int,
        kind: QuizQuestion.Kind,
        compound: ChemicalCompound,
        compoundPool: [ChemicalCompound],
        elementPool: [ChemicalElement],
        generator: inout SeededGenerator
    ) -> QuizQuestion? {
        let others = compoundPool.filter { $0.id != compound.id }
        let prompt: String
        let correct: String
        let candidates: [String]
        let baseDetail = "\(compound.preferredName) · \(compound.displayFormula)"
            + (compound.molarMassDisplay.map { " · \($0)" } ?? "")
        var detail: String? = baseDetail

        switch kind {
        case .formulaForCompound:
            prompt = "What is the formula of \(compound.preferredName.lowercased())?"
            correct = compound.displayFormula
            candidates = others.map(\.displayFormula)
        case .compoundForFormula:
            prompt = "Which compound is \(compound.displayFormula)?"
            correct = compound.preferredName
            // Two compounds can share a formula (ethanol and dimethyl ether
            // are both C₂H₆O), so a compound with the same formula is never
            // offered as a wrong answer.
            candidates = others.filter { $0.hillFormula != compound.hillFormula }.map(\.preferredName)
        case .molarMassForCompound:
            guard let mass = compound.molarMassDisplay else {
                return makeQuestion(id: id, kind: .formulaForCompound, compound: compound,
                                    compoundPool: compoundPool, elementPool: elementPool, generator: &generator)
            }
            prompt = "What is the molar mass of \(compound.preferredName.lowercased())?"
            correct = mass
            candidates = others.compactMap(\.molarMassDisplay)
        case .bondingForCompound:
            guard compound.bondingClass != .unknown else {
                return makeQuestion(id: id, kind: .compoundForFormula, compound: compound,
                                    compoundPool: compoundPool, elementPool: elementPool, generator: &generator)
            }
            prompt = "How is \(compound.preferredName.lowercased()) (\(compound.displayFormula)) best classified?"
            correct = compound.bondingClass.displayName
            candidates = CompoundBondingClass.allCases
                .filter { $0 != compound.bondingClass && $0 != .unknown }
                .map(\.displayName)
            detail = compound.classificationSource.map { "\(baseDetail) · Classification: \($0)" } ?? baseDetail
        case .elementInCompound:
            let present = Set(compound.composition.keys)
            guard let pickNumber = present.sorted().first,
                  let member = elementPool.first(where: { $0.atomicNumber == pickNumber }) else {
                return makeQuestion(id: id, kind: .formulaForCompound, compound: compound,
                                    compoundPool: compoundPool, elementPool: elementPool, generator: &generator)
            }
            let members = elementPool.filter { present.contains($0.atomicNumber) }
            let chosen = members.randomElement(using: &generator) ?? member
            prompt = "Which element is part of \(compound.preferredName.lowercased())?"
            correct = chosen.name
            candidates = elementPool.filter { !present.contains($0.atomicNumber) }.map(\.name)
        case .atomCountForCompound:
            let total = compound.composition.values.reduce(0, +)
            guard total > 0 else {
                return makeQuestion(id: id, kind: .formulaForCompound, compound: compound,
                                    compoundPool: compoundPool, elementPool: elementPool, generator: &generator)
            }
            prompt = "How many atoms are in one formula unit of \(compound.displayFormula)?"
            correct = "\(total)"
            candidates = [total - 2, total - 1, total + 1, total + 2, total * 2, total + 3]
                .filter { $0 > 0 && $0 != total }
                .map { "\($0)" }
        case .compoundForDescription:
            guard let summary = compound.summary, !summary.isEmpty else {
                return makeQuestion(id: id, kind: .compoundForFormula, compound: compound,
                                    compoundPool: compoundPool, elementPool: elementPool, generator: &generator)
            }
            prompt = "Which compound is described? " + summary
            correct = compound.preferredName
            candidates = others.map(\.preferredName)
        default:
            return nil
        }

        return assemble(id: id, kind: kind, subject: .compound(compound), prompt: prompt, correct: correct,
                        candidates: candidates, detail: detail, generator: &generator)
    }

    // MARK: - Options

    /// Deduplicates, drops anything equal to the answer, then takes a stable
    /// random sample so the wrong options differ every run but replay
    /// identically for the same seed.
    private static func assemble(
        id: Int,
        kind: QuizQuestion.Kind,
        subject: QuizSubject,
        prompt: String,
        correct: String,
        candidates: [String],
        detail: String?,
        generator: inout SeededGenerator
    ) -> QuizQuestion? {
        var seen = Set<String>([correct])
        var unique: [String] = []
        for candidate in candidates.shuffled(using: &generator) where !seen.contains(candidate) {
            seen.insert(candidate)
            unique.append(candidate)
            if unique.count == optionCount - 1 { break }
        }

        // Four options whenever the pool allows it. A pool too small to supply
        // three distinct distractors yields a shorter question rather than a
        // repeated one; with the full catalog as the distractor pool this never
        // happens outside tests.
        guard !unique.isEmpty else { return nil }

        var options = unique + [correct]
        options.shuffle(using: &generator)
        guard let correctIndex = options.firstIndex(of: correct) else { return nil }

        return QuizQuestion(
            id: id,
            kind: kind,
            subject: subject,
            prompt: prompt,
            options: options,
            correctIndex: correctIndex,
            detail: detail
        )
    }
}
