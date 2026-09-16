import Foundation
import Observation
import OSLog
import SwiftData

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
    /// The outcome of the last import, for the screen to show.
    var lastImportMessage: String?

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

    /// The package for a quiz: its name and configuration, nothing else.
    func package(for quiz: SavedQuiz) -> ElemoraQuizPackage {
        ElemoraQuizPackage(quiz: quiz)
    }

    /// Validates and imports a package, returning the new quiz.
    @discardableResult
    func importPackage(_ data: Data, catalog: ElementCatalog, date: Date = Date()) throws -> SavedQuiz {
        let package = try ElemoraQuizPackage.decode(data, catalog: catalog)
        return create(name: package.name, configuration: package.configuration, date: date)
    }

    /// Reads a file the learner picked or opened, and records the outcome in
    /// `lastImportMessage` for the interface.
    func importFile(at url: URL, catalog: ElementCatalog) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let quiz = try importPackage(data, catalog: catalog)
            lastImportMessage = "Imported \u{201C}\(quiz.name)\u{201D}."
        } catch let error as QuizPackageError {
            lastImportMessage = error.userMessage
        } catch {
            lastImportMessage = "That file could not be read."
        }
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
