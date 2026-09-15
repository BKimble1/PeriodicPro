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

    @Test("A structure clue never names its own element")
    func structureCluesDoNotLeakTheAnswer() {
        let deck = StudyDeckBuilder.identifyCards(pool: catalog.elements, count: 9, seed: 5)
        for card in deck where card.clue == .structure {
            #expect(!card.question.contains(card.element.name))
            #expect(!card.question.contains(card.element.symbol))
            #expect(card.answerTitle == card.element.name,
                    "The answer is only revealed after the learner commits")
        }
        #expect(deck.contains { $0.clue == .structure }, "The deck should include structure clues")
    }
}
