import Foundation

/// Why a shared quiz was refused, in words a learner can act on.
enum QuizLinkError: Error, Hashable, Sendable {
    case tooLarge
    case notAQuiz
    case unsupportedVersion(Int)
    case invalidName
    case unknownElement(Int)
    case invalidCompoundReference(String)
    case tooManyItems

    var userMessage: String {
        switch self {
        case .tooLarge:
            return "That quiz is too large to share as a link. Choose fewer items and try again."
        case .notAQuiz:
            return "That link is not an Elemora quiz."
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

/// What travels inside a shared quiz link.
///
/// Only the schema version, the quiz's name and its configuration. No
/// progress, no favorites, no history, no identifier of the person who made it
/// and nothing about their device. The keys are one letter each because every
/// byte becomes three characters of URL.
struct QuizSharePayload: Codable, Hashable, Sendable {
    /// Schema version.
    let v: Int
    /// Quiz name.
    let n: String
    /// The configuration.
    let c: QuizConfiguration

    init(version: Int = QuizShareLink.schemaVersion, name: String, configuration: QuizConfiguration) {
        v = version
        n = name
        c = configuration
    }

    var schemaVersion: Int { v }
    var name: String { n }
    var configuration: QuizConfiguration { c }
}

/// Turns a saved quiz into a link, and a link back into a saved quiz.
///
/// Pure and free of UIKit, SwiftUI and any store, so every rule below is a
/// unit test rather than something felt for by sending yourself a message.
///
/// The wire format is one version character followed by base64url of the
/// zlib-compressed JSON payload. Compression matters because a custom quiz can
/// name two hundred compounds, and the version character means a future format
/// can change everything after it without a link from today becoming garbage.
/// Nothing is uploaded anywhere: the link *is* the quiz.
enum QuizShareLink {
    static let schemaVersion = 1
    /// The marker the encoded payload starts with, for format version 1.
    static let formatMarker: Character = "1"
    /// The longest encoded payload a link may carry. A URL much beyond this
    /// starts being truncated by the places people paste it, so an oversized
    /// quiz is refused with a message rather than shared as a broken link.
    static let maximumEncodedLength = 1_600
    /// A bound on what the compressed payload is allowed to expand into, so a
    /// hostile link cannot ask the app to allocate megabytes.
    static let maximumDecodedBytes = 64 * 1024

    // MARK: - Encoding

    /// The encoded payload for a quiz, or a refusal if it is too large.
    static func encode(name: String, configuration: QuizConfiguration) throws -> String {
        let payload = QuizSharePayload(
            name: SavedQuiz.cleanName(name),
            configuration: configuration.sanitized()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(payload)
        let compressed = try compress(json)
        let encoded = String(formatMarker) + base64URLEncoded(compressed)
        guard encoded.count <= maximumEncodedLength else { throw QuizLinkError.tooLarge }
        return encoded
    }

    /// The shareable https URL for a quiz.
    static func url(name: String, configuration: QuizConfiguration) throws -> URL {
        let encoded = try encode(name: name, configuration: configuration)
        guard let url = ElemoraLinks.quizURL(payload: encoded) else { throw QuizLinkError.notAQuiz }
        return url
    }

    // MARK: - Decoding

    /// Validates an encoded payload and returns what it describes.
    ///
    /// Every rule is checked before anything is created: the size, the format
    /// marker, the base64 alphabet, the compression, the JSON, the schema
    /// version, the name, the list lengths, that every element exists and that
    /// every compound reference is a PubChem identifier rather than something
    /// private to one device.
    static func decode(_ encoded: String, catalog: ElementCatalog) throws -> QuizSharePayload {
        guard encoded.count <= maximumEncodedLength else { throw QuizLinkError.tooLarge }
        guard let marker = encoded.first else { throw QuizLinkError.notAQuiz }
        guard marker == formatMarker else {
            // A digit that is not ours is a format from a newer Elemora;
            // anything else is not one of our links at all.
            guard let version = Int(String(marker)), version > schemaVersion else {
                throw QuizLinkError.notAQuiz
            }
            throw QuizLinkError.unsupportedVersion(version)
        }
        guard let compressed = base64URLDecoded(String(encoded.dropFirst())) else {
            throw QuizLinkError.notAQuiz
        }
        let json = try decompress(compressed)
        guard json.count <= maximumDecodedBytes else { throw QuizLinkError.tooLarge }
        guard let payload = try? JSONDecoder().decode(QuizSharePayload.self, from: json) else {
            throw QuizLinkError.notAQuiz
        }
        guard payload.schemaVersion == schemaVersion else {
            throw QuizLinkError.unsupportedVersion(payload.schemaVersion)
        }
        let name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw QuizLinkError.invalidName }

        let configuration = payload.configuration
        guard configuration.customElementIDs.count <= QuizConfiguration.maximumCustomItems,
              configuration.customCompoundIDs.count <= QuizConfiguration.maximumCustomItems else {
            throw QuizLinkError.tooManyItems
        }
        for number in configuration.customElementIDs where catalog.element(atomicNumber: number) == nil {
            throw QuizLinkError.unknownElement(number)
        }
        for id in configuration.customCompoundIDs where !isShareableCompoundID(id) {
            throw QuizLinkError.invalidCompoundReference(id)
        }
        return QuizSharePayload(
            version: payload.schemaVersion,
            name: SavedQuiz.cleanName(name),
            configuration: configuration.sanitized()
        )
    }

    /// The quiz an incoming URL describes, or `nil` when the URL is not an
    /// Elemora quiz link at all. A link that *is* one but cannot be read
    /// throws, so the difference between "not for us" and "broken" survives.
    static func payload(from url: URL, catalog: ElementCatalog) throws -> QuizSharePayload? {
        guard let encoded = ElemoraLinks.quizPayload(from: url) else { return nil }
        return try decode(encoded, catalog: catalog)
    }

    /// Only PubChem-backed identifiers travel. A hypothetical composition is
    /// private to the device that made it and has nothing to ask about.
    static func isShareableCompoundID(_ id: String) -> Bool {
        id.range(of: "^pubchem-[0-9]{1,9}$", options: .regularExpression) != nil
    }

    // MARK: - base64url

    /// RFC 4648 §5: the URL-safe alphabet, with the padding removed.
    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecoded(_ string: String) -> Data? {
        guard !string.isEmpty else { return nil }
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    // MARK: - Compression

    private static func compress(_ data: Data) throws -> Data {
        do {
            return try (data as NSData).compressed(using: .zlib) as Data
        } catch {
            throw QuizLinkError.notAQuiz
        }
    }

    private static func decompress(_ data: Data) throws -> Data {
        do {
            return try (data as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw QuizLinkError.notAQuiz
        }
    }
}
