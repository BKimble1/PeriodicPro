import Foundation
import Testing
@testable import PeriodicPro

/// Configured quizzes: scopes, filters, difficulty, frozen decks, seeds, and
/// Match rounds. Everything runs against the bundled data with injected
/// progress snapshots, so no store and no clock is involved.
@Suite("Quiz configuration")
struct QuizConfigurationTests {
    private let catalog = TestCatalog.shared
    private let compounds = TestCompounds.catalog.compounds

    private func subjects(
        _ configuration: QuizConfiguration,
        elements: [Int: ElementProgressSnapshot] = [:],
        compoundSnapshots: [String: CompoundProgressSnapshot] = [:]
    ) -> [QuizSubject] {
        QuizPoolBuilder.subjects(for: configuration, catalog: catalog, compounds: compounds,
                                 elementSnapshots: elements, compoundSnapshots: compoundSnapshots)
    }

    private func dealer(_ configuration: QuizConfiguration, pool: [QuizSubject]? = nil) -> QuizRoundDealer {
        QuizRoundDealer(configuration: configuration, subjects: pool ?? subjects(configuration),
                        elementDistractors: catalog.elements, compoundDistractors: compounds)
    }

    @Test("The defaults: ten questions, elements, mixed, everything, shuffled, no timer")
    func defaults() {
        let standard = QuizConfiguration.standard
        #expect(standard.questionCount == 10)
        #expect(standard.content == .elements)
        #expect(standard.difficulty == .mixed)
        #expect(standard.scope == .all)
        #expect(standard.shuffles)
        #expect(standard.timerSeconds == nil)
        #expect(!standard.isTimed)
    }

    @Test("Scopes select the right elements: everything, favorites, missed, not mastered, custom")
    func elementScopes() {
        let snapshots: [Int: ElementProgressSnapshot] = [
            8: ElementProgressSnapshot(atomicNumber: 8, isFavorite: true, mastery: .mastered, correctCount: 3),
            11: ElementProgressSnapshot(atomicNumber: 11, isFavorite: true),
            26: ElementProgressSnapshot(atomicNumber: 26, mastery: .learning, incorrectCount: 2,
                                        lastReviewed: Date(timeIntervalSince1970: 100)),
            79: ElementProgressSnapshot(atomicNumber: 79, mastery: .familiar, incorrectCount: 1,
                                        lastReviewed: Date(timeIntervalSince1970: 200)),
        ]
        var configuration = QuizConfiguration.standard
        #expect(subjects(configuration, elements: snapshots).count == 118)

        configuration.scope = .favorites
        #expect(subjects(configuration, elements: snapshots).map(\.key) == ["element-8", "element-11"])

        configuration.scope = .recentlyMissed
        #expect(subjects(configuration, elements: snapshots).map(\.key) == ["element-79", "element-26"],
                "most recently missed first")

        configuration.scope = .notMastered
        let notMastered = subjects(configuration, elements: snapshots)
        #expect(notMastered.count == 117)
        #expect(!notMastered.contains { $0.key == "element-8" })

        configuration.scope = .custom
        configuration.customElementIDs = [79, 1, 999, 79]
        #expect(subjects(configuration, elements: snapshots).map(\.key) == ["element-79", "element-1"],
                "the learner's order, unknown ids dropped, duplicates removed")
    }

    @Test("Element filters narrow by family, phase, period, group and atomic-number range")
    func elementFilters() {
        var configuration = QuizConfiguration.standard
        configuration.elementFilters.categories = [.nobleGas]
        #expect(subjects(configuration).count == 7)
        configuration.elementFilters.phases = [.gas]
        #expect(subjects(configuration).count == 6, "oganesson's state is not established, so it is not a gas")
        configuration.elementFilters.categories = []
        #expect(subjects(configuration).allSatisfy { $0.element?.phase == .gas })
        configuration.elementFilters = QuizElementFilters(periods: [1, 2])
        #expect(subjects(configuration).count == 10)
        configuration.elementFilters = QuizElementFilters(groups: [1])
        #expect(subjects(configuration).map { $0.element?.symbol ?? "" }
                == ["H", "Li", "Na", "K", "Rb", "Cs", "Fr"])
        configuration.elementFilters = QuizElementFilters(minimumAtomicNumber: 10, maximumAtomicNumber: 20)
        #expect(subjects(configuration).count == 11)
        #expect(configuration.elementFilters.summary == "Z 10–20")
        #expect(QuizElementFilters().summary == nil)
    }

    @Test("Compound content, scopes and filters")
    func compoundPools() {
        var configuration = QuizConfiguration.standard
        configuration.content = .compounds
        #expect(subjects(configuration).count == 50)
        #expect(subjects(configuration).allSatisfy { $0.compound != nil })

        configuration.content = .both
        #expect(subjects(configuration).count == 168)

        configuration.compoundFilters.bondingClasses = [.ionic]
        #expect(subjects(configuration).filter { $0.compound != nil }
            .allSatisfy { $0.compound?.bondingClass == .ionic })

        configuration = QuizConfiguration.standard
        configuration.content = .compounds
        configuration.scope = .favorites
        let favorites = ["pubchem-962": CompoundProgressSnapshot(compoundID: "pubchem-962", isFavorite: true)]
        #expect(subjects(configuration, compoundSnapshots: favorites).map(\.key) == ["pubchem-962"])

        configuration.scope = .all
        configuration.compoundFilters.onlySaved = true
        let saved = ["pubchem-5234": CompoundProgressSnapshot(compoundID: "pubchem-5234", isSaved: true)]
        #expect(subjects(configuration, compoundSnapshots: saved).map(\.key) == ["pubchem-5234"])

        // A hypothetical composition has nothing to ask about.
        let hypothetical = ChemicalCompound.hypothetical(composition: [79: 1, 2: 1], catalog: catalog)
        configuration = QuizConfiguration.standard
        configuration.content = .compounds
        let pool = QuizPoolBuilder.subjects(for: configuration, catalog: catalog,
                                            compounds: compounds + [hypothetical],
                                            elementSnapshots: [:], compoundSnapshots: [:])
        #expect(!pool.contains { $0.key == hypothetical.id })
    }

    @Test("A round cannot start from too small a pool, and the reason is spoken")
    func unavailableReasons() {
        var configuration = QuizConfiguration.standard
        configuration.scope = .favorites
        #expect(QuizPoolBuilder.unavailableReason(for: configuration, poolCount: 0)?.contains("favorites") == true)
        configuration.scope = .recentlyMissed
        #expect(QuizPoolBuilder.unavailableReason(for: configuration, poolCount: 2) != nil)
        #expect(QuizPoolBuilder.unavailableReason(for: configuration, poolCount: 3) == nil)
    }

    @Test("Difficulty decides the question types dealt")
    func difficultyKinds() {
        for difficulty in [QuizDifficulty.easy, .medium, .hard] {
            var configuration = QuizConfiguration.standard
            configuration.difficulty = difficulty
            configuration.questionCount = 20
            let questions = dealer(configuration).questions(seed: 7)
            #expect(questions.count == 20)
            #expect(questions.allSatisfy { $0.kind.difficulty == difficulty }, "\(difficulty) dealt a stray kind")
            let dealt = Set(questions.map(\.kind))
            #expect(dealt.isSubset(of: Set(difficulty.elementKinds)))
            #expect(dealt.count >= 3, "\(difficulty) should rotate through its kinds")
        }
        var mixed = QuizConfiguration.standard
        mixed.difficulty = .mixed
        mixed.questionCount = 50
        let kinds = Set(dealer(mixed).questions(seed: 3).map(\.kind))
        #expect(kinds.contains { $0.difficulty == .easy })
        #expect(kinds.contains { $0.difficulty == .hard })
    }

    @Test("Every dealt question is well formed and its answer is true")
    func questionsAreCorrect() throws {
        var configuration = QuizConfiguration.standard
        configuration.content = .both
        configuration.difficulty = .mixed
        configuration.questionCount = 50
        for seed in UInt64(1)...5 {
            for question in dealer(configuration).questions(seed: seed) {
                // Three states of matter make a three-option question; everything else has four.
                let expectedOptions = question.kind == .phaseForElement ? 3 : 4
                #expect(question.options.count == expectedOptions,
                        "\(question.prompt) has \(question.options.count) options")
                #expect(Set(question.options).count == question.options.count)
                #expect(question.options.indices.contains(question.correctIndex))
                switch question.kind {
                case .symbolForName: #expect(question.correctAnswer == question.element?.symbol)
                case .nameForSymbol, .elementForClue: #expect(question.correctAnswer == question.element?.name)
                case .numberForName: #expect(question.correctAnswer == "\(question.element?.atomicNumber ?? -1)")
                case .familyForElement: #expect(question.correctAnswer == question.element?.category.displayName)
                case .phaseForElement: #expect(question.correctAnswer == question.element?.phase.displayName)
                case .periodForElement:
                    #expect(question.correctAnswer == "Period \(question.element?.period ?? -1)")
                case .groupForElement: #expect(question.correctAnswer == "Group \(question.element?.group ?? -1)")
                case .configurationForElement:
                    #expect(question.correctAnswer == question.element?.formattedElectronConfiguration)
                case .massForElement: #expect(question.correctAnswer == question.element?.formattedAtomicMass)
                case .formulaForCompound: #expect(question.correctAnswer == question.compound?.displayFormula)
                case .compoundForFormula, .compoundForDescription:
                    #expect(question.correctAnswer == question.compound?.preferredName)
                case .molarMassForCompound:
                    #expect(question.correctAnswer == question.compound?.molarMassDisplay)
                case .bondingForCompound:
                    #expect(question.correctAnswer == question.compound?.bondingClass.displayName)
                case .elementInCompound:
                    let compound = try #require(question.compound)
                    let named = try #require(catalog.elements.first { $0.name == question.correctAnswer })
                    #expect(compound.composition[named.atomicNumber] != nil)
                    for option in question.options where option != question.correctAnswer {
                        let other = try #require(catalog.elements.first { $0.name == option })
                        #expect(compound.composition[other.atomicNumber] == nil,
                                "\(option) is in \(compound.formula)")
                    }
                case .atomCountForCompound:
                    let compound = try #require(question.compound)
                    #expect(question.correctAnswer == "\(compound.composition.values.reduce(0, +))")
                }
            }
        }
    }

    @Test("A formula shared by two compounds is never a wrong answer to the other")
    func sharedFormulaIsNeverADistractor() {
        var configuration = QuizConfiguration.standard
        configuration.content = .compounds
        configuration.difficulty = .easy
        configuration.questionCount = 50
        for seed in UInt64(1)...10 {
            for question in dealer(configuration).questions(seed: seed) where question.kind == .compoundForFormula {
                let formula = question.compound?.hillFormula
                let sameFormula = compounds.filter { $0.hillFormula == formula }.map(\.preferredName)
                let wrong = question.options.filter { $0 != question.correctAnswer }
                #expect(wrong.allSatisfy { !sameFormula.contains($0) },
                        "\(question.prompt) offers a compound with the same formula as a wrong answer")
            }
        }
    }

    @Test("The deck is frozen for a seed, and different seeds deal different orders")
    func seedsAndFrozenDecks() {
        let configuration = QuizConfiguration.standard
        let dealer = dealer(configuration)
        #expect(dealer.questions(seed: 42) == dealer.questions(seed: 42))
        let first = dealer.questions(seed: 1).map(\.subject.key)
        let second = dealer.questions(seed: 2).map(\.subject.key)
        #expect(first != second)
        var distinctOrders = Set<[String]>()
        for _ in 0..<5 {
            distinctOrders.insert(dealer.questions(seed: QuizSeed.fresh()).map(\.subject.key))
        }
        #expect(distinctOrders.count == 5, "fresh seeds should never repeat an order")
        #expect(QuizSeed.fresh() != QuizSeed.fresh())
    }

    @Test("Shuffle off keeps the pool's own order")
    func shuffleOff() {
        var configuration = QuizConfiguration.standard
        configuration.scope = .custom
        configuration.customElementIDs = [79, 1, 8, 26, 11]
        configuration.shuffles = false
        configuration.questionCount = 5
        let keys = dealer(configuration).questions(seed: 9).map(\.subject.key)
        #expect(keys == ["element-79", "element-1", "element-8", "element-26", "element-11"])
    }

    @Test("Counts: presets, a capped custom count, and wrapping a small pool")
    func counts() {
        #expect(QuizConfiguration.lengthPresets == [5, 10, 20])
        var configuration = QuizConfiguration.standard
        configuration.questionCount = 500
        #expect(configuration.clampedQuestionCount == 50)
        configuration.questionCount = 1
        #expect(configuration.clampedQuestionCount == 3)
        configuration.questionCount = 20
        configuration.scope = .custom
        configuration.customElementIDs = [1, 2, 3, 4]
        let questions = dealer(configuration).questions(seed: 1)
        #expect(questions.count == 20, "a small pool wraps rather than dealing a short round")
        #expect(configuration.sanitized().customElementIDs == [1, 2, 3, 4])
        var wild = configuration
        wild.customElementIDs = Array(repeating: 1, count: 500) + [0, 119]
        wild.timerSeconds = 999
        #expect(wild.sanitized().customElementIDs.count == QuizConfiguration.maximumCustomItems)
        #expect(wild.sanitized().timerSeconds == nil)
    }

    @Test("Timer presets and the summary line")
    func timerAndSummary() {
        var configuration = QuizConfiguration.standard
        #expect(QuizConfiguration.timerPresets == [15, 30, 60])
        configuration.timerSeconds = 30
        #expect(configuration.isTimed)
        #expect(configuration.summary == "10 questions · Elements · Mixed · timed")
        configuration.scope = .favorites
        configuration.content = .both
        #expect(configuration.summary == "10 questions · Both · Mixed · Favorites · timed")
    }

    @Test("Configurations round-trip through JSON")
    func codable() throws {
        var configuration = QuizConfiguration.standard
        configuration.content = .both
        configuration.elementFilters.categories = [.halogen, .nobleGas]
        configuration.compoundFilters.tags = [.acid]
        configuration.customCompoundIDs = ["pubchem-962"]
        configuration.timerSeconds = 15
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(QuizConfiguration.self, from: data)
        #expect(decoded == configuration)
    }
}

@Suite("Match rounds")
struct MatchRoundTests {
    private let catalog = TestCatalog.shared
    private let compounds = TestCompounds.catalog.compounds

    @Test("Six, eight and ten pairs, each a real subject with its own answer")
    func pairCounts() {
        let subjects = catalog.elements.map(QuizSubject.element)
        for count in QuizConfiguration.matchPairPresets {
            let round = MatchRoundBuilder.round(subjects: subjects, pairCount: count, seed: 5)
            #expect(round.pairs.count == count)
            #expect(round.promptOrder.count == count)
            #expect(round.answerOrder.count == count)
            #expect(Set(round.promptOrder) == Set(round.pairs.map(\.id)))
            #expect(Set(round.answerOrder) == Set(round.pairs.map(\.id)))
            for pair in round.pairs {
                #expect(pair.prompt == pair.subject.element?.name)
                #expect(pair.answer == pair.subject.element?.symbol)
            }
        }
    }

    @Test("No duplicate subjects, prompts or answers in a round")
    func noDuplicates() {
        let subjects = compounds.map(QuizSubject.compound) + catalog.elements.map(QuizSubject.element)
        for seed in UInt64(1)...30 {
            let round = MatchRoundBuilder.round(subjects: subjects, pairCount: 10, seed: seed)
            #expect(Set(round.pairs.map(\.subject.key)).count == round.pairs.count)
            #expect(Set(round.pairs.map(\.answer)).count == round.pairs.count, "seed \(seed) repeats an answer")
            #expect(Set(round.pairs.map(\.prompt)).count == round.pairs.count)
        }
        // The two C₂H₆O compounds can never both be in one round.
        let ethers = compounds.filter { $0.hillFormula == "C2H6O" }.map(QuizSubject.compound)
        let round = MatchRoundBuilder.round(subjects: ethers, pairCount: 10, seed: 1)
        #expect(round.pairs.count == 1)
    }

    @Test("Rounds are deterministic for a seed and differ between seeds")
    func determinism() {
        let subjects = catalog.elements.map(QuizSubject.element)
        #expect(MatchRoundBuilder.round(subjects: subjects, pairCount: 8, seed: 3)
                == MatchRoundBuilder.round(subjects: subjects, pairCount: 8, seed: 3))
        #expect(MatchRoundBuilder.round(subjects: subjects, pairCount: 8, seed: 3).promptOrder
                != MatchRoundBuilder.round(subjects: subjects, pairCount: 8, seed: 4).promptOrder)
        let round = MatchRoundBuilder.round(subjects: subjects, pairCount: 8, seed: 3)
        #expect(round.promptOrder != round.answerOrder, "the two columns are shuffled independently")
    }

    @Test("A small pool yields a smaller round rather than repeats")
    func smallPool() {
        let subjects = Array(catalog.elements.prefix(3)).map(QuizSubject.element)
        let round = MatchRoundBuilder.round(subjects: subjects, pairCount: 8, seed: 1)
        #expect(round.pairs.count == 3)
        #expect(MatchRoundBuilder.round(subjects: [], pairCount: 8, seed: 1).pairs.isEmpty)
    }
}
