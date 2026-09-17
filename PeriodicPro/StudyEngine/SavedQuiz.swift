import Foundation
import Observation
import OSLog
import SwiftData

/// What happened when a shared quiz link was opened.
enum QuizImportOutcome: Hashable, Sendable {
    /// Saved as a new quiz.
    case saved(SavedQuiz)
    /// The identical quiz was already in My Quizzes; nothing was created.
    case alreadySaved(SavedQuiz)
    case failed(String)

    var quiz: SavedQuiz? {
        switch self {
        case .saved(let quiz), .alreadySaved(let quiz): return quiz
        case .failed: return nil
        }
    }
}

/// A quiz the learner built and kept.
struct SavedQuiz: Identifiable, Hashable, Codable, Sendable {
    static let maximumNameLength = 60

    let id: UUID
    var name: String
    var configuration: QuizConfiguration
    let createdAt: Date
    var updatedAt: Date

    /// A name trimmed to one line of at most sixty characters, never empty.
    static func cleanName(_ raw: String, fallback: String = "Untitled quiz") -> String {
        let oneLine = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oneLine.isEmpty else { return fallback }
        return String(oneLine.prefix(maximumNameLength))
    }
}

/// The SwiftData row behind a `SavedQuiz`.
///
/// The configuration is stored as JSON: it grows with the app, and a row that
/// no longer decodes is dropped rather than migrated — a quiz is a few taps to
/// rebuild, and a schema migration for it is not a good trade.
@Model
final class SavedQuizRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var configurationPayload: Data
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID, name: String, configurationPayload: Data, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.configurationPayload = configurationPayload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Owns the learner's saved quizzes: create, rename, duplicate, edit, delete,
/// and the import side of sharing.
///
/// Same contract as `ProgressStore`: works without a container, in which
/// case nothing survives the app closing.
@MainActor
@Observable
final class SavedQuizStore {
    static let maximumQuizzes = 100
    private static let logger = Logger(subsystem: "com.periodicpro.app", category: "saved-quizzes")

    private let context: ModelContext?
    @ObservationIgnored private var records: [UUID: SavedQuizRecord] = [:]
    /// Newest first.
    private(set) var quizzes: [SavedQuiz] = []
    private(set) var writeFailureMessage: String?
    /// What happened the last time a shared quiz link was opened, for the
    /// screen to show. Cleared by the screen once it has been seen.
    var lastImportOutcome: QuizImportOutcome?

    init(container: ModelContainer?) {
        context = container.map { ModelContext($0) }
        reload()
    }

    func quiz(id: UUID) -> SavedQuiz? { quizzes.first { $0.id == id } }

    // MARK: - Loading

    func reload() {
        guard let context else { return }
        do {
            let fetched = try context.fetch(FetchDescriptor<SavedQuizRecord>(
                sortBy: [SortDescriptor(\SavedQuizRecord.updatedAt, order: .reverse)]
            ))
            var loaded: [SavedQuiz] = []
            var kept: [UUID: SavedQuizRecord] = [:]
            for record in fetched {
                if let configuration = try? JSONDecoder().decode(QuizConfiguration.self,
                                                                 from: record.configurationPayload) {
                    loaded.append(SavedQuiz(
                        id: record.id, name: record.name, configuration: configuration.sanitized(),
                        createdAt: record.createdAt, updatedAt: record.updatedAt
                    ))
                    kept[record.id] = record
                } else {
                    Self.logger.error("Discarding an unreadable saved quiz \(record.id, privacy: .public)")
                    context.delete(record)
                }
            }
            quizzes = loaded
            records = kept
            save()
        } catch {
            Self.logger.error("Saved quiz reload failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Writes

    @discardableResult
    func create(name: String, configuration: QuizConfiguration, date: Date = Date()) -> SavedQuiz {
        let quiz = SavedQuiz(
            id: UUID(), name: SavedQuiz.cleanName(name), configuration: configuration.sanitized(),
            createdAt: date, updatedAt: date
        )
        insert(quiz)
        return quiz
    }

    func update(_ quiz: SavedQuiz, date: Date = Date()) {
        var copy = quiz
        copy.name = SavedQuiz.cleanName(quiz.name)
        copy.configuration = quiz.configuration.sanitized()
        copy.updatedAt = date
        guard let index = quizzes.firstIndex(where: { $0.id == quiz.id }) else {
            insert(copy)
            return
        }
        quizzes[index] = copy
        quizzes.sort { $0.updatedAt > $1.updatedAt }
        if let record = records[copy.id], let payload = try? JSONEncoder().encode(copy.configuration) {
            record.name = copy.name
            record.configurationPayload = payload
            record.updatedAt = copy.updatedAt
        }
        save()
    }

    func rename(id: UUID, to name: String) {
        guard var quiz = quiz(id: id) else { return }
        quiz.name = name
        update(quiz)
    }

    @discardableResult
    func duplicate(id: UUID, date: Date = Date()) -> SavedQuiz? {
        guard let original = quiz(id: id) else { return nil }
        let name = SavedQuiz.cleanName(original.name + " copy")
        return create(name: name, configuration: original.configuration, date: date)
    }

    func delete(id: UUID) {
        quizzes.removeAll { $0.id == id }
        if let record = records.removeValue(forKey: id) {
            context?.delete(record)
        }
        save()
    }

    // MARK: - Sharing

    /// The https link that carries this quiz. Throws when the configuration is
    /// too large to fit in a sensible URL, which the caller shows as an error
    /// rather than handing somebody a link that will not open.
    func shareURL(for quiz: SavedQuiz) throws -> URL {
        try QuizShareLink.url(name: quiz.name, configuration: quiz.configuration)
    }

    /// Saves a validated shared quiz, returning what happened.
    ///
    /// Opening the same link twice is common — somebody forwards a message,
    /// or taps it again later — and it must not fill My Quizzes with copies.
    /// An identical name *and* configuration resolves to the quiz already
    /// there. A quiz with the same name but a different configuration is a
    /// different quiz and is saved as a copy, because overwriting something
    /// the learner may have edited is not a decision a link gets to make.
    @discardableResult
    func save(shared payload: QuizSharePayload, date: Date = Date()) -> QuizImportOutcome {
        if let existing = quizzes.first(where: {
            $0.name == payload.name && $0.configuration == payload.configuration.sanitized()
        }) {
            return .alreadySaved(existing)
        }
        let name = quizzes.contains { $0.name == payload.name }
            ? SavedQuiz.cleanName(payload.name + " copy")
            : payload.name
        return .saved(create(name: name, configuration: payload.configuration, date: date))
    }

    /// Handles a URL the system handed the app. Returns false when the URL is
    /// not an Elemora quiz link at all, so the caller can leave it alone.
    @discardableResult
    func open(shareURL url: URL, catalog: ElementCatalog, date: Date = Date()) -> Bool {
        do {
            guard let payload = try QuizShareLink.payload(from: url, catalog: catalog) else {
                return false
            }
            lastImportOutcome = save(shared: payload, date: date)
        } catch let error as QuizLinkError {
            lastImportOutcome = .failed(error.userMessage)
        } catch {
            lastImportOutcome = .failed(QuizLinkError.notAQuiz.userMessage)
        }
        return true
    }

    // MARK: - Private

    private func insert(_ quiz: SavedQuiz) {
        quizzes.insert(quiz, at: 0)
        if quizzes.count > Self.maximumQuizzes, let oldest = quizzes.last {
            quizzes.removeLast()
            if let record = records.removeValue(forKey: oldest.id) { context?.delete(record) }
        }
        guard let context, let payload = try? JSONEncoder().encode(quiz.configuration) else { return }
        let record = SavedQuizRecord(
            id: quiz.id, name: quiz.name, configurationPayload: payload,
            createdAt: quiz.createdAt, updatedAt: quiz.updatedAt
        )
        context.insert(record)
        records[quiz.id] = record
        save()
    }

    private func save() {
        guard let context, context.hasChanges else { return }
        do {
            try context.save()
            writeFailureMessage = nil
        } catch {
            Self.logger.error("Saved quiz save failed: \(String(describing: error), privacy: .public)")
            writeFailureMessage = "Your quiz could not be saved."
        }
    }
}
