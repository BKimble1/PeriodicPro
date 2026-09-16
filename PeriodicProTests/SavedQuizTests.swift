import Foundation
import SwiftData
import Testing
@testable import PeriodicPro

/// Saved quizzes and the `.elemoraquiz` package: persistence, every edit,
/// and every reason an import is refused.
@MainActor
@Suite("Saved quizzes")
struct SavedQuizStoreTests {
    private let catalog = TestCatalog.shared

    private func makeStore() throws -> (SavedQuizStore, ModelContainer) {
        let container = try #require(PersistenceController.makeInMemoryContainer())
        return (SavedQuizStore(container: container), container)
    }

    @Test("Create, rename, edit, duplicate and delete, newest first")
    func lifecycle() throws {
        let (store, _) = try makeStore()
        var configuration = QuizConfiguration.standard
        configuration.difficulty = .hard
        let quiz = store.create(name: "  Halogens  ", configuration: configuration,
                                date: Date(timeIntervalSince1970: 10))
        #expect(quiz.name == "Halogens")
        #expect(store.quizzes.count == 1)

        store.rename(id: quiz.id, to: "Halogens and noble gases")
        #expect(store.quiz(id: quiz.id)?.name == "Halogens and noble gases")

        var edited = try #require(store.quiz(id: quiz.id))
        edited.configuration.questionCount = 20
        store.update(edited, date: Date(timeIntervalSince1970: 20))
        #expect(store.quiz(id: quiz.id)?.configuration.questionCount == 20)

        let copy = try #require(store.duplicate(id: quiz.id, date: Date(timeIntervalSince1970: 30)))
        #expect(copy.id != quiz.id)
        #expect(copy.name == "Halogens and noble gases copy")
        #expect(copy.configuration == store.quiz(id: quiz.id)?.configuration)
        #expect(store.quizzes.first?.id == copy.id, "newest first")

        store.delete(id: quiz.id)
        #expect(store.quizzes.map(\.id) == [copy.id])
        store.delete(id: UUID())
        #expect(store.quizzes.count == 1, "deleting something unknown is a no-op")
    }

    @Test("Saved quizzes persist across a reload, and a corrupt row is dropped")
    func persistence() throws {
        let (store, container) = try makeStore()
        let quiz = store.create(name: "Persisted", configuration: .standard)
        let context = container.mainContext
        let corrupt = SavedQuizRecord(id: UUID(), name: "Broken", configurationPayload: Data("{".utf8),
                                      createdAt: Date(), updatedAt: Date())
        context.insert(corrupt)
        try context.save()

        let reopened = SavedQuizStore(container: container)
        #expect(reopened.quizzes.map(\.id) == [quiz.id])
        #expect(reopened.quiz(id: quiz.id)?.name == "Persisted")
    }

    @Test("Without a container everything still works for the session")
    func containerless() {
        let store = SavedQuizStore(container: nil)
        let quiz = store.create(name: "Ephemeral", configuration: .standard)
        #expect(store.quizzes.count == 1)
        store.delete(id: quiz.id)
        #expect(store.quizzes.isEmpty)
    }

    @Test("Names are cleaned: one line, sixty characters, never empty")
    func names() {
        #expect(SavedQuiz.cleanName("") == "Untitled quiz")
        #expect(SavedQuiz.cleanName("a\nb") == "a b")
        #expect(SavedQuiz.cleanName(String(repeating: "x", count: 100)).count == 60)
    }
}

@Suite("Quiz packages")
struct QuizPackageTests {
    private let catalog = TestCatalog.shared

    private func sampleQuiz() -> SavedQuiz {
        var configuration = QuizConfiguration.standard
        configuration.content = .both
        configuration.scope = .custom
        configuration.customElementIDs = [1, 8, 79]
        configuration.customCompoundIDs = ["pubchem-962", "pubchem-5234"]
        configuration.difficulty = .medium
        return SavedQuiz(id: UUID(), name: "Water and salt", configuration: configuration,
                         createdAt: Date(), updatedAt: Date())
    }

    @Test("Export and import round-trip the name and configuration, and nothing else")
    func roundTrip() throws {
        let package = ElemoraQuizPackage(quiz: sampleQuiz())
        let data = try package.encoded()
        let decoded = try ElemoraQuizPackage.decode(data, catalog: catalog)
        #expect(decoded.name == "Water and salt")
        #expect(decoded.configuration == package.configuration)
        #expect(decoded.schemaVersion == 1)

        // No private information: the file holds exactly these keys.
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["format", "schemaVersion", "name", "exportedAt", "configuration"])
        let text = try #require(String(data: data, encoding: .utf8))
        for forbidden in ["mastery", "correct", "favorite", "streak", "email", "device", "uuid"] {
            #expect(!text.lowercased().contains(forbidden), "the package must not carry \(forbidden)")
        }
        #expect(package.suggestedFileName == "Water and salt.elemoraquiz")
    }

    @Test("The package refuses what it should")
    func rejections() throws {
        let good = try ElemoraQuizPackage(quiz: sampleQuiz()).encoded()

        #expect(throws: QuizPackageError.tooLarge) {
            _ = try ElemoraQuizPackage.decode(Data(count: ElemoraQuizPackage.maximumBytes + 1), catalog: catalog)
        }
        #expect(throws: QuizPackageError.notAQuiz) {
            _ = try ElemoraQuizPackage.decode(Data("not json".utf8), catalog: catalog)
        }
        #expect(throws: QuizPackageError.notAQuiz) {
            _ = try ElemoraQuizPackage.decode(Data("{\"format\":\"something-else\"}".utf8), catalog: catalog)
        }

        func mutated(_ edit: (inout [String: Any]) -> Void) throws -> Data {
            var object = try #require(try JSONSerialization.jsonObject(with: good) as? [String: Any])
            edit(&object)
            return try JSONSerialization.data(withJSONObject: object)
        }

        #expect(throws: QuizPackageError.unsupportedVersion(2)) {
            _ = try ElemoraQuizPackage.decode(try mutated { $0["schemaVersion"] = 2 }, catalog: catalog)
        }
        #expect(throws: QuizPackageError.notAQuiz) {
            _ = try ElemoraQuizPackage.decode(try mutated { $0["format"] = "elemora-deck" }, catalog: catalog)
        }
        #expect(throws: QuizPackageError.invalidName) {
            _ = try ElemoraQuizPackage.decode(try mutated { $0["name"] = "   " }, catalog: catalog)
        }
        #expect(throws: QuizPackageError.unknownElement(200)) {
            _ = try ElemoraQuizPackage.decode(try mutated {
                var configuration = $0["configuration"] as? [String: Any] ?? [:]
                configuration["customElementIDs"] = [1, 200]
                $0["configuration"] = configuration
            }, catalog: catalog)
        }
        #expect(throws: QuizPackageError.invalidCompoundReference("hypothetical-abc")) {
            _ = try ElemoraQuizPackage.decode(try mutated {
                var configuration = $0["configuration"] as? [String: Any] ?? [:]
                configuration["customCompoundIDs"] = ["pubchem-962", "hypothetical-abc"]
                $0["configuration"] = configuration
            }, catalog: catalog)
        }
        #expect(throws: QuizPackageError.tooManyItems) {
            _ = try ElemoraQuizPackage.decode(try mutated {
                var configuration = $0["configuration"] as? [String: Any] ?? [:]
                configuration["customElementIDs"] = Array(repeating: 1, count: 201)
                $0["configuration"] = configuration
            }, catalog: catalog)
        }
        // Out-of-range numbers are clamped rather than refused.
        let clamped = try ElemoraQuizPackage.decode(try mutated {
            var configuration = $0["configuration"] as? [String: Any] ?? [:]
            configuration["questionCount"] = 9_999
            configuration["timerSeconds"] = 1
            $0["configuration"] = configuration
        }, catalog: catalog)
        #expect(clamped.configuration.questionCount == QuizConfiguration.maximumQuestions)
        #expect(clamped.configuration.timerSeconds == nil)
    }

    @Test("Every refusal has a message a learner can act on")
    func messages() {
        let errors: [QuizPackageError] = [
            .tooLarge, .notAQuiz, .unsupportedVersion(3), .invalidName, .unknownElement(200),
            .invalidCompoundReference("x"), .tooManyItems,
        ]
        for error in errors {
            #expect(error.userMessage.count > 10)
        }
        #expect(ElemoraQuizPackage.isShareableCompoundID("pubchem-962"))
        #expect(!ElemoraQuizPackage.isShareableCompoundID("hypothetical-1234"))
        #expect(!ElemoraQuizPackage.isShareableCompoundID("pubchem-"))
    }

    @Test("Importing through the store creates a quiz and reports the outcome")
    @MainActor
    func importThroughStore() throws {
        let store = SavedQuizStore(container: nil)
        let data = try ElemoraQuizPackage(quiz: sampleQuiz()).encoded()
        let imported = try store.importPackage(data, catalog: catalog)
        #expect(imported.name == "Water and salt")
        #expect(store.quizzes.count == 1)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("import-test.elemoraquiz")
        try data.write(to: url)
        store.importFile(at: url, catalog: catalog)
        #expect(store.lastImportMessage?.contains("Imported") == true)
        #expect(store.quizzes.count == 2)

        try Data("garbage".utf8).write(to: url)
        store.importFile(at: url, catalog: catalog)
        #expect(store.lastImportMessage == QuizPackageError.notAQuiz.userMessage)
        #expect(store.quizzes.count == 2)
    }
}
