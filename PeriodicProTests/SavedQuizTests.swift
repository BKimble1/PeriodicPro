import Foundation
import SwiftData
import UIKit
import Testing
@testable import PeriodicPro

/// Saved quizzes and the links that share them: persistence, every edit, and
/// every reason an incoming link is refused.
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

@Suite("Quiz share links")
struct QuizShareLinkTests {
    private let catalog = TestCatalog.shared

    private func sampleConfiguration() -> QuizConfiguration {
        var configuration = QuizConfiguration.standard
        configuration.content = .both
        configuration.scope = .custom
        configuration.customElementIDs = [1, 8, 79]
        configuration.customCompoundIDs = ["pubchem-962", "pubchem-5234"]
        configuration.difficulty = .medium
        return configuration
    }

    private func sampleQuiz() -> SavedQuiz {
        SavedQuiz(id: UUID(), name: "Water and salt", configuration: sampleConfiguration(),
                  createdAt: Date(), updatedAt: Date())
    }

    @Test("A quiz round-trips through a link, and nothing else travels with it")
    func roundTrip() throws {
        let quiz = sampleQuiz()
        let url = try QuizShareLink.url(name: quiz.name, configuration: quiz.configuration)
        #expect(url.absoluteString.hasPrefix(ElemoraLinks.quizBaseString))

        let payload = try #require(try QuizShareLink.payload(from: url, catalog: catalog))
        #expect(payload.name == "Water and salt")
        #expect(payload.configuration == quiz.configuration.sanitized())
        #expect(payload.schemaVersion == QuizShareLink.schemaVersion)

        // The visible URL is opaque: no quiz name, no element list, no JSON.
        let text = url.absoluteString
        #expect(!text.contains("Water"))
        #expect(!text.contains("customElementIDs"))
        #expect(!text.contains("{"))

        // And the payload itself carries exactly three fields.
        let encoded = try QuizShareLink.encode(name: quiz.name, configuration: quiz.configuration)
        let compressed = try #require(QuizShareLink.base64URLDecoded(String(encoded.dropFirst())))
        let json = try (compressed as NSData).decompressed(using: .zlib) as Data
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(Set(object.keys) == ["v", "n", "c"])
        let text2 = String(decoding: json, as: UTF8.self)
        for forbidden in ["favorite", "streak", "mastery", "device", "progress", "answered"] {
            #expect(!text2.lowercased().contains(forbidden), "\(forbidden) must never travel")
        }
    }

    @Test("Only this app's quiz links are recognized")
    func routing() {
        let valid = URL(string: ElemoraLinks.quizBaseString + "1abc")
        #expect(ElemoraLinks.quizPayload(from: valid ?? URL(fileURLWithPath: "/")) == "1abc")

        let cases = [
            "https://elemora.idlery.com/",
            "https://elemora.idlery.com/privacy",
            "https://elemora.idlery.com/quiz/",
            "https://elemora.idlery.com/quiz/a/b",
            "https://example.com/quiz/1abc",
            "https://evil.elemora.idlery.com.attacker.test/quiz/1abc",
            "http://elemora.idlery.com/quiz/1abc",
            "elemora://quiz/1abc",
        ]
        for text in cases {
            guard let url = URL(string: text) else { continue }
            #expect(ElemoraLinks.quizPayload(from: url) == nil, "\(text) must not route")
        }
    }

    @Test("The decoder refuses what it should")
    func refusals() throws {
        let good = try QuizShareLink.encode(name: "Water and salt", configuration: sampleConfiguration())

        #expect(throws: QuizLinkError.tooLarge) {
            _ = try QuizShareLink.decode(
                String(repeating: "A", count: QuizShareLink.maximumEncodedLength + 1), catalog: catalog
            )
        }
        #expect(throws: QuizLinkError.notAQuiz) {
            _ = try QuizShareLink.decode("", catalog: catalog)
        }
        #expect(throws: QuizLinkError.notAQuiz) {
            _ = try QuizShareLink.decode("not-a-payload", catalog: catalog)
        }
        // A payload that is base64 but not compressed JSON.
        #expect(throws: QuizLinkError.notAQuiz) {
            _ = try QuizShareLink.decode("1" + QuizShareLink.base64URLEncoded(Data("hello".utf8)),
                                         catalog: catalog)
        }
        #expect(throws: QuizLinkError.unsupportedVersion(9)) {
            _ = try QuizShareLink.decode("9" + String(good.dropFirst()), catalog: catalog)
        }
        #expect(throws: QuizLinkError.unknownElement(200)) {
            var configuration = sampleConfiguration()
            configuration.customElementIDs = [200]
            _ = try QuizShareLink.decode(try encodeUnsanitized(configuration), catalog: catalog)
        }
        #expect(throws: QuizLinkError.invalidCompoundReference("hypothetical-abc")) {
            var configuration = sampleConfiguration()
            configuration.customCompoundIDs = ["hypothetical-abc"]
            _ = try QuizShareLink.decode(try encodeUnsanitized(configuration), catalog: catalog)
        }
        #expect(throws: QuizLinkError.invalidName) {
            _ = try QuizShareLink.decode(try encodeUnsanitized(sampleConfiguration(), name: "   "),
                                         catalog: catalog)
        }

    }

    @Test("A link is refused when it would not fit, and the full-size quiz still does")
    func lengthLimit() throws {
        // Two hundred scattered nine-digit CIDs is what a link cannot carry:
        // the payload is deflated, so what costs space is distinct text, not
        // the number of items. This is the case that has to be refused rather
        // than handed over as a URL nothing can open.
        var huge = QuizConfiguration.standard
        huge.content = .both
        huge.scope = .custom
        huge.customElementIDs = Array(1...118)
        huge.customCompoundIDs = (0..<QuizConfiguration.maximumCustomItems)
            .map { "pubchem-\(100_000_000 + $0 * 4_177_777)" }
        #expect(throws: QuizLinkError.tooLarge) {
            _ = try QuizShareLink.encode(name: String(repeating: "A", count: 60), configuration: huge)
        }

        // And the quiz a learner can actually build at full size — every
        // element, two hundred compounds, the longest name the app keeps —
        // still fits, so the limit never refuses ordinary work.
        var full = QuizConfiguration.standard
        full.content = .both
        full.scope = .custom
        full.questionCount = QuizConfiguration.maximumQuestions
        full.customElementIDs = Array(1...118)
        full.customCompoundIDs = (0..<QuizConfiguration.maximumCustomItems).map { "pubchem-\($0 + 962)" }
        let link = try QuizShareLink.encode(name: String(repeating: "A", count: 60), configuration: full)
        #expect(link.count <= QuizShareLink.maximumEncodedLength)
        let decoded = try QuizShareLink.decode(link, catalog: catalog)
        #expect(decoded.configuration.customCompoundIDs.count == QuizConfiguration.maximumCustomItems)
    }

    /// Builds a payload without going through `encode`, which sanitizes — the
    /// point of these cases is what `decode` does with a hostile one.
    private func encodeUnsanitized(_ configuration: QuizConfiguration,
                                   name: String = "Sample") throws -> String {
        let payload = QuizSharePayload(name: name, configuration: configuration)
        let json = try JSONEncoder().encode(payload)
        let compressed = try (json as NSData).compressed(using: .zlib) as Data
        return "1" + QuizShareLink.base64URLEncoded(compressed)
    }

    @Test("Every refusal has a message a learner can act on")
    func messages() {
        let errors: [QuizLinkError] = [
            .tooLarge, .notAQuiz, .unsupportedVersion(7), .invalidName,
            .unknownElement(300), .invalidCompoundReference("x"), .tooManyItems,
        ]
        for error in errors {
            #expect(!error.userMessage.isEmpty)
            #expect(error.userMessage.first?.isUppercase == true)
        }
    }

    @Test("Shareable identifiers are PubChem identifiers, and nothing else")
    func shareableIdentifiers() {
        #expect(QuizShareLink.isShareableCompoundID("pubchem-962"))
        #expect(!QuizShareLink.isShareableCompoundID("hypothetical-1234"))
        #expect(!QuizShareLink.isShareableCompoundID("pubchem-"))
        #expect(!QuizShareLink.isShareableCompoundID("pubchem-12345678901"))
    }
}

@MainActor
@Suite("Receiving a shared quiz")
struct QuizImportTests {
    private let catalog = TestCatalog.shared

    private func link(name: String, configuration: QuizConfiguration = .standard) throws -> URL {
        try QuizShareLink.url(name: name, configuration: configuration)
    }

    @Test("A valid link saves the quiz and reports it")
    func saves() throws {
        let store = SavedQuizStore(container: nil)
        #expect(store.open(shareURL: try link(name: "Halogens"), catalog: catalog))
        guard case .saved(let quiz) = store.lastImportOutcome else {
            Issue.record("a valid link should save, got \(String(describing: store.lastImportOutcome))")
            return
        }
        #expect(quiz.name == "Halogens")
        #expect(store.quizzes.count == 1)
    }

    @Test("Opening the same link twice does not pile up copies")
    func duplicates() throws {
        let store = SavedQuizStore(container: nil)
        let url = try link(name: "Halogens")
        store.open(shareURL: url, catalog: catalog)
        store.lastImportOutcome = nil
        store.open(shareURL: url, catalog: catalog)
        guard case .alreadySaved = store.lastImportOutcome else {
            Issue.record("the second open should resolve to the quiz already there")
            return
        }
        #expect(store.quizzes.count == 1)

        // A different quiz that happens to share a name is a copy, never an
        // overwrite of something the learner may have edited.
        var other = QuizConfiguration.standard
        other.difficulty = .hard
        store.open(shareURL: try link(name: "Halogens", configuration: other), catalog: catalog)
        #expect(store.quizzes.count == 2)
        #expect(store.quizzes.contains { $0.name == "Halogens copy" })
        #expect(store.quizzes.contains { $0.configuration.difficulty == .mixed })
    }

    @Test("A URL that is not a quiz link is left alone; a broken one is reported")
    func routing() throws {
        let store = SavedQuizStore(container: nil)
        let existing = store.create(name: "Mine", configuration: .standard)

        for text in ["https://elemora.idlery.com/privacy", "https://example.com/quiz/1abc"] {
            guard let url = URL(string: text) else { continue }
            #expect(!store.open(shareURL: url, catalog: catalog))
            #expect(store.lastImportOutcome == nil)
        }

        let broken = try #require(URL(string: ElemoraLinks.quizBaseString + "1zzzz"))
        #expect(store.open(shareURL: broken, catalog: catalog))
        guard case .failed = store.lastImportOutcome else {
            Issue.record("a malformed payload should be reported, not saved")
            return
        }
        // Nothing the learner already had was touched.
        #expect(store.quizzes.map(\.id) == [existing.id])
    }
}

/// What the share sheet hands Messages. The blank white tile this replaces was
/// the absence of exactly this metadata.
@MainActor
@Suite("Shared quiz link previews")
struct QuizSharePreviewTests {
    @Test("The link preview is branded and points at the quiz's own URL")
    func metadata() throws {
        let url = try #require(URL(string: ElemoraLinks.quizBaseString + "1abc"))
        let source = QuizShareItemSource(url: url, title: "Halogens", image: nil)
        #expect(source.previewTitle == "Halogens \u{2014} Elemora Quiz")

        let controller = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        let metadata = try #require(source.activityViewControllerLinkMetadata(controller))
        #expect(metadata.title == "Halogens \u{2014} Elemora Quiz")
        #expect(metadata.url == url)
        #expect(metadata.originalURL == url)
        // And the item itself is the URL, not a file.
        #expect(source.activityViewControllerPlaceholderItem(controller) as? URL == url)
        #expect(source.activityViewController(controller, itemForActivityType: nil) as? URL == url)
    }

    @Test("The rendered card is the size a link preview wants")
    func card() throws {
        let image = try #require(QuizShareImage.render(title: "Halogens", subtitle: "10 questions"))
        #expect(image.size.width == QuizShareCard.size.width)
        #expect(image.size.height == QuizShareCard.size.height)
    }
}
