import Foundation
import Testing
@testable import PeriodicPro

@Suite("Quiz generation")
struct QuizGeneratorTests {
    private let catalog = TestCatalog.shared

    private var pool: [ChemicalElement] { Array(catalog.elements.prefix(40)) }

    @Test("A quiz has the requested number of questions")
    func questionCount() {
        let quiz = QuizGenerator.makeQuiz(pool: pool, distractors: catalog.elements, seed: 1)
        #expect(quiz.count == QuizGenerator.defaultQuestionCount)
    }

    @Test("The same seed always produces the same quiz")
    func generationIsDeterministic() {
        let first = QuizGenerator.makeQuiz(pool: pool, distractors: catalog.elements, seed: 42)
        let second = QuizGenerator.makeQuiz(pool: pool, distractors: catalog.elements, seed: 42)
        #expect(first == second)

        let different = QuizGenerator.makeQuiz(pool: pool, distractors: catalog.elements, seed: 43)
        #expect(first != different)
    }

    @Test("Every question has four distinct options, exactly one of them right")
    func optionsAreWellFormed() {
        for seed in UInt64(1)...25 {
            let quiz = QuizGenerator.makeQuiz(pool: pool, distractors: catalog.elements, seed: seed)
            for question in quiz {
                #expect(question.options.count == QuizGenerator.optionCount,
                        "Seed \(seed): \(question.prompt) has \(question.options.count) options")
                #expect(Set(question.options).count == question.options.count,
                        "Seed \(seed): duplicate options in \(question.prompt)")
                #expect(question.options.indices.contains(question.correctIndex))
                #expect(question.options.filter { $0 == question.correctAnswer }.count == 1)
            }
        }
    }

    @Test("The correct answer really is the element's own value")
    func correctAnswersAreAccurate() {
        let quiz = QuizGenerator.makeQuiz(pool: pool, distractors: catalog.elements, seed: 7)
        for question in quiz {
            switch question.kind {
            case .symbolForName:
                #expect(question.correctAnswer == question.element.symbol)
                #expect(question.prompt.contains(question.element.name))
            case .nameForSymbol:
                #expect(question.correctAnswer == question.element.name)
                #expect(question.prompt.contains(question.element.symbol))
            case .numberForName:
                #expect(question.correctAnswer == "\(question.element.atomicNumber)")
            case .familyForElement:
                #expect(question.correctAnswer == question.element.category.displayName)
            }
        }
    }

    @Test("All four question kinds appear in a ten-question round")
    func questionKindsAreMixed() {
        let quiz = QuizGenerator.makeQuiz(pool: pool, distractors: catalog.elements, seed: 5)
        #expect(Set(quiz.map(\.kind)).count == QuizQuestion.Kind.allCases.count)
    }

    @Test("Correct answers are not always in the same slot")
    func answerPositionVaries() {
        var positions = Set<Int>()
        for seed in UInt64(1)...15 {
            let quiz = QuizGenerator.makeQuiz(pool: pool, distractors: catalog.elements, seed: seed)
            positions.formUnion(quiz.map(\.correctIndex))
        }
        #expect(positions.count >= 3, "Answers should not cluster in one position")
    }

    @Test("isCorrect only accepts the right index")
    func isCorrectMatchesIndex() {
        let quiz = QuizGenerator.makeQuiz(pool: pool, distractors: catalog.elements, seed: 11)
        for question in quiz {
            for index in question.options.indices {
                #expect(question.isCorrect(index) == (index == question.correctIndex))
            }
        }
    }

    @Test("An empty pool produces an empty quiz rather than crashing")
    func emptyPool() {
        #expect(QuizGenerator.makeQuiz(pool: [], distractors: [], seed: 1).isEmpty)
    }

    @Test("A tiny pool still yields usable questions")
    func smallPool() {
        let tiny = Array(catalog.elements.prefix(3))
        let quiz = QuizGenerator.makeQuiz(pool: tiny, distractors: tiny, count: 3, seed: 2)
        #expect(quiz.count == 3)
        for question in quiz {
            #expect(question.options.count >= 2)
            #expect(question.options.indices.contains(question.correctIndex))
        }
    }
}

@Suite("Deck building")
struct StudyDeckBuilderTests {
    private let catalog = TestCatalog.shared

    @Test("Flashcard decks are the requested size and reproducible")
    func flashcardDeterminism() {
        let first = StudyDeckBuilder.flashcards(pool: catalog.elements, seed: 9)
        let second = StudyDeckBuilder.flashcards(pool: catalog.elements, seed: 9)
        #expect(first.count == 10)
        #expect(first == second)
        #expect(first != StudyDeckBuilder.flashcards(pool: catalog.elements, seed: 10))
    }

    @Test("Flashcards alternate between name-to-symbol and symbol-to-name")
    func flashcardFacesAlternate() {
        let deck = StudyDeckBuilder.flashcards(pool: catalog.elements, seed: 3)
        for (index, card) in deck.enumerated() {
            if index.isMultiple(of: 2) {
                #expect(card.clue == .text(card.element.name))
                #expect(card.answerTitle == card.element.symbol)
            } else {
                #expect(card.clue == .text(card.element.symbol))
                #expect(card.answerTitle == card.element.name)
            }
        }
    }

    @Test("Identify cards cycle through structure, number and description clues")
    func identifyCluesCycle() {
        let deck = StudyDeckBuilder.identifyCards(pool: catalog.elements, seed: 4)
        #expect(deck.count == 10)
        for (index, card) in deck.enumerated() {
            switch index % 3 {
            case 0: #expect(card.clue == .structure)
            case 1: #expect(card.clue == .text("\(card.element.atomicNumber)"))
            default:
                if case .description = card.clue {} else {
                    Issue.record("Card \(index) should carry a written clue")
                }
            }
            #expect(card.answerTitle == card.element.name)
        }
    }

    @Test("A written clue never gives the answer away")
    func writtenCluesDoNotLeakTheAnswer() {
        for element in catalog.elements {
            let hint = StudyDeckBuilder.hint(for: element).lowercased()
            #expect(!hint.contains(element.name.lowercased()),
                    "Hint for \(element.name) names the element")
        }
    }

    @Test("A deck never contains the same element twice when the pool is big enough")
    func decksAvoidRepeats() {
        let deck = StudyDeckBuilder.flashcards(pool: catalog.elements, count: 10, seed: 21)
        #expect(Set(deck.map(\.element.atomicNumber)).count == 10)
    }

    @Test("A pool smaller than the deck wraps instead of returning a short deck")
    func smallPoolWraps() {
        let tiny = Array(catalog.elements.prefix(3))
        let deck = StudyDeckBuilder.flashcards(pool: tiny, count: 7, seed: 1)
        #expect(deck.count == 7)
    }

    @Test("An empty pool yields an empty deck")
    func emptyPool() {
        #expect(StudyDeckBuilder.flashcards(pool: [], seed: 1).isEmpty)
        #expect(StudyDeckBuilder.identifyCards(pool: [], seed: 1).isEmpty)
    }
}

@Suite("Seeded randomness")
struct SeededGeneratorTests {
    @Test("The same seed replays the same sequence")
    func replayable() {
        var a = SeededGenerator(seed: 12_345)
        var b = SeededGenerator(seed: 12_345)
        let first = (0..<20).map { _ in a.next() }
        let second = (0..<20).map { _ in b.next() }
        #expect(first == second)
    }

    @Test("Different seeds diverge")
    func seedsDiffer() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        #expect(a.next() != b.next())
    }

    @Test("A zero seed still produces a varied sequence")
    func zeroSeedIsSafe() {
        var generator = SeededGenerator(seed: 0)
        let values = (0..<10).map { _ in generator.next() }
        #expect(Set(values).count == 10)
    }

    @Test("A day's seed is stable within the day and changes the next day")
    func dailySeed() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let morning = Date(timeIntervalSince1970: 1_767_225_600)          // 2026-01-01 00:00 UTC
        let evening = morning.addingTimeInterval(60 * 60 * 20)
        let tomorrow = morning.addingTimeInterval(60 * 60 * 24)

        #expect(SeededGenerator.dailySeed(for: morning, calendar: calendar)
                == SeededGenerator.dailySeed(for: evening, calendar: calendar))
        #expect(SeededGenerator.dailySeed(for: morning, calendar: calendar)
                != SeededGenerator.dailySeed(for: tomorrow, calendar: calendar))
    }
}

@Suite("Study modes draw different material")
struct StudyModeSeedTests {
    private let catalog = TestCatalog.shared

    private var pool: [ChemicalElement] { Array(catalog.elements.prefix(40)) }

    @Test("Each mode has its own salt, so no two modes share a session seed")
    func saltsAreDistinct() {
        let salts = StudyMode.allCases.map(\.seedSalt)
        #expect(Set(salts).count == StudyMode.allCases.count)
    }

    @Test("The same round gives the three modes different elements")
    func modesDivergeWithinARound() {
        let base: UInt64 = 20_260_115
        let flashcards = StudyDeckBuilder.flashcards(
            pool: pool, seed: base &+ StudyMode.flashcards.seedSalt
        ).map(\.element.atomicNumber)
        let identify = StudyDeckBuilder.identifyCards(
            pool: pool, seed: base &+ StudyMode.identify.seedSalt
        ).map(\.element.atomicNumber)
        let quiz = QuizGenerator.makeQuiz(
            pool: pool, distractors: catalog.elements, seed: base &+ StudyMode.quiz.seedSalt
        ).map(\.element.atomicNumber)

        #expect(flashcards != identify, "Flashcards and Identify should not be the same ten")
        #expect(flashcards != quiz, "Flashcards and the quiz should not be the same ten")
        #expect(identify != quiz, "Identify and the quiz should not be the same ten")
    }

    /// Regression cover for the mid-round reshuffle. `StudyScreen` used to pass
    /// `studyPriority(...)` into a running session live. A session's pool is the
    /// 40 least-familiar elements, and `pick` shuffles that whole pool — so the
    /// moment one answer changed the pool's membership, every remaining card was
    /// re-dealt underneath the learner. The session now snapshots its pool in
    /// `init`; this test pins the property that made the old arrangement unsafe.
    @Test("One answer changes which 40 elements a session would draw from")
    func oneAnswerChangesTheStudyPool() throws {
        let all = catalog.elements
        var mastery: [Int: MasteryLevel] = [:]
        func pool() -> [Int] {
            MasteryEngine.studyPriority(all) { mastery[$0] ?? .notStarted }
                .prefix(StudyDeckBuilder.defaultPoolSize)
                .map(\.atomicNumber)
        }

        let before = pool()
        #expect(before.count == StudyDeckBuilder.defaultPoolSize)

        // The learner gets one card right. Everything else is still .notStarted,
        // so this element now sorts behind all 117 others and leaves the pool
        // entirely — which pulls a new element in behind it.
        let answered = try #require(before.first)
        mastery[answered] = .learning

        let after = pool()
        #expect(!after.contains(answered),
                "An answered element should drop out of the least-familiar pool")
        #expect(Set(before) != Set(after),
                "A live queue would hand the running session a different pool")
    }

    @Test("No Identify card shows its own answer before the reveal")
    func identifyCluesDoNotLeakTheAnswer() {
        // Every seed, not one: the clue a given element draws depends on where
        // it lands in the shuffle, so a single deck only ever exercises a third
        // of the pool. Substring-matching the *question* would be both vacuous
        // (it is a constant) and a trap — "What element is this?" contains a
        // capital W, so it would fail the day tungsten landed on a structure
        // index. The face that can actually leak is the clue.
        for seed in UInt64(0)..<40 {
            let deck = StudyDeckBuilder.identifyCards(pool: catalog.elements, count: 9, seed: seed)
            #expect(deck.contains { $0.clue == .structure },
                    "Every deck of nine should include structure clues")

            for card in deck {
                switch card.clue {
                case .structure:
                    // The diagram carries the question alone: no text at all.
                    #expect(card.question == "What element is this?")
                case .text(let shown):
                    // The atomic-number clue may show the number and nothing else.
                    #expect(shown == "\(card.element.atomicNumber)")
                case .description(let hint):
                    #expect(!hint.localizedCaseInsensitiveContains(card.element.name),
                            "\(card.element.name)'s hint names it: \(hint)")
                    #expect(!containsSymbolAsWord(hint, card.element.symbol),
                            "\(card.element.name)'s hint gives away \(card.element.symbol): \(hint)")
                }

                // The answer face is where the name and symbol belong.
                #expect(card.answerTitle == card.element.name)
                #expect(card.answerDetail.contains(card.element.symbol))
            }
        }
    }

    /// Matches a symbol only as a standalone word. A plain `contains` would
    /// report four false leaks against the real hints: N inside "Nonmetal",
    /// La inside "Lanthanide", Po inside "Post-Transition" and Ac inside
    /// "Actinide".
    private func containsSymbolAsWord(_ text: String, _ symbol: String) -> Bool {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { String($0) == symbol }
    }
}
