import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// The `.elemoraquiz` document: JSON with a declared shape, so Files,
    /// AirDrop and Messages know which app opens it.
    static let elemoraQuiz = UTType(exportedAs: "com.idlery.elemora.quiz", conformingTo: .json)
}

/// Why a package was refused, in words a learner can act on.
enum QuizPackageError: Error, Hashable, Sendable {
    case tooLarge
    case notAQuiz
    case unsupportedVersion(Int)
    case invalidName
    case unknownElement(Int)
    case invalidCompoundReference(String)
    case tooManyItems

    var userMessage: String {
        switch self {
        case .tooLarge: return "That file is too large to be an Elemora quiz."
        case .notAQuiz: return "That file is not an Elemora quiz."
        case .unsupportedVersion(let version):
            return "This quiz was made with a newer version of Elemora (format \(version)). "
                + "Update the app to open it."
        case .invalidName: return "The quiz has no usable name."
        case .unknownElement(let number): return "The quiz refers to an element (\(number)) that does not exist."
        case .invalidCompoundReference(let id): return "The quiz refers to a compound (\(id)) that cannot be shared."
        case .tooManyItems: return "The quiz lists more items than a quiz can hold."
        }
    }
}

/// The shareable form of a saved quiz.
///
/// Only the name and the configuration travel. No progress, no favorites, no
/// history, no identifiers of the person who made it — and `decode` refuses
/// anything oversized, of the wrong format, of a newer schema, or pointing at
/// elements or compounds that do not exist or are private to one device.
struct ElemoraQuizPackage: Codable, Hashable, Sendable {
    static let format = "elemora-quiz"
    static let schemaVersion = 1
    static let maximumBytes = 256 * 1024
    static let fileExtension = "elemoraquiz"

    let format: String
    let schemaVersion: Int
    let name: String
    let exportedAt: String
    let configuration: QuizConfiguration

    init(quiz: SavedQuiz) {
        format = Self.format
        schemaVersion = Self.schemaVersion
        name = SavedQuiz.cleanName(quiz.name)
        exportedAt = CompoundFormula.today()
        configuration = quiz.configuration.sanitized()
    }

    /// A file name for the share sheet: the quiz name, made safe.
    var suggestedFileName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let safe = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let base = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: " -"))
        return (base.isEmpty ? "Elemora quiz" : base) + "." + Self.fileExtension
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Writes the package to a temporary file for the share sheet.
    func writeTemporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ElemoraQuizShare", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(suggestedFileName)
        try encoded().write(to: url, options: .atomic)
        return url
    }

    /// Decodes and validates. Every rule here is a test.
    static func decode(_ data: Data, catalog: ElementCatalog) throws -> ElemoraQuizPackage {
        guard data.count <= maximumBytes else { throw QuizPackageError.tooLarge }
        let decoded: ElemoraQuizPackage
        do {
            decoded = try JSONDecoder().decode(ElemoraQuizPackage.self, from: data)
        } catch {
            throw QuizPackageError.notAQuiz
        }
        guard decoded.format == format else { throw QuizPackageError.notAQuiz }
        guard decoded.schemaVersion == schemaVersion else {
            throw QuizPackageError.unsupportedVersion(decoded.schemaVersion)
        }
        let name = decoded.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw QuizPackageError.invalidName }

        let configuration = decoded.configuration
        guard configuration.customElementIDs.count <= QuizConfiguration.maximumCustomItems,
              configuration.customCompoundIDs.count <= QuizConfiguration.maximumCustomItems else {
            throw QuizPackageError.tooManyItems
        }
        for number in configuration.customElementIDs where catalog.element(atomicNumber: number) == nil {
            throw QuizPackageError.unknownElement(number)
        }
        for id in configuration.customCompoundIDs where !isShareableCompoundID(id) {
            throw QuizPackageError.invalidCompoundReference(id)
        }
        return ElemoraQuizPackage(
            format: decoded.format, schemaVersion: decoded.schemaVersion, name: SavedQuiz.cleanName(name),
            exportedAt: decoded.exportedAt, configuration: configuration.sanitized()
        )
    }

    /// Only PubChem-backed identifiers travel. A hypothetical composition is
    /// private to the device that made it and has nothing to ask about.
    static func isShareableCompoundID(_ id: String) -> Bool {
        id.range(of: "^pubchem-[0-9]{1,9}$", options: .regularExpression) != nil
    }

    private init(format: String, schemaVersion: Int, name: String, exportedAt: String,
                 configuration: QuizConfiguration) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.name = name
        self.exportedAt = exportedAt
        self.configuration = configuration
    }
}

extension ElemoraQuizPackage: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .elemoraQuiz) { package in
            SentTransferredFile(try package.writeTemporaryFile())
        }
    }
}
