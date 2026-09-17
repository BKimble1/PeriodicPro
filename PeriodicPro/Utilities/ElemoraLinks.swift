import Foundation

/// Every web destination and address the app can open, in one place.
///
/// Settings, the paywall and the quiz share sheet all read from here rather
/// than carrying their own copies of a URL string. One source of truth means a
/// domain change is one edit, and a test can assert the exact strings the App
/// Store listing and the privacy answers are built on.
enum ElemoraLinks {
    /// The host every Elemora web destination lives on, and the one the
    /// associated-domains entitlement claims.
    static let host = "elemora.idlery.com"

    /// The path prefix a shared quiz link uses. Anything outside it is not a
    /// quiz and is ignored by the incoming-link route.
    static let quizPathPrefix = "/quiz/"

    static let websiteString = "https://elemora.idlery.com"
    static let privacyString = "https://elemora.idlery.com/privacy"
    static let termsString = "https://elemora.idlery.com/terms"
    static let supportString = "https://elemora.idlery.com/support"
    static let supportEmailAddress = "support@idlery.com"
    /// What a shared quiz URL is built on: this plus the encoded payload.
    static let quizBaseString = "https://elemora.idlery.com/quiz/"

    static var website: URL? { URL(string: websiteString) }
    static var privacy: URL? { URL(string: privacyString) }
    static var terms: URL? { URL(string: termsString) }
    static var support: URL? { URL(string: supportString) }
    static var quizBase: URL? { URL(string: quizBaseString) }

    /// A pre-addressed support mail with the app version in the body, so a
    /// report arrives with the one fact that is always needed. Nothing about
    /// the person is collected or filled in.
    static func supportMail(version: String, build: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmailAddress
        let body = """
            Please describe the problem here.

            ---
            Elemora \(version) (\(build))
            """
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Elemora Support"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    /// The share URL for an encoded quiz payload.
    static func quizURL(payload: String) -> URL? {
        URL(string: quizBaseString + payload)
    }

    /// The payload in an incoming quiz link, or `nil` when the URL is not one.
    ///
    /// Pure and total: it is the whole of the routing decision, so every rule
    /// below — the scheme, the host, the path prefix, an empty payload, a
    /// payload with a slash in it — is a unit test rather than something felt
    /// for by tapping links on a device.
    static func quizPayload(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        guard url.host()?.lowercased() == host else { return nil }
        let path = url.path()
        guard path.hasPrefix(quizPathPrefix) else { return nil }
        let payload = String(path.dropFirst(quizPathPrefix.count))
        guard !payload.isEmpty, !payload.contains("/") else { return nil }
        return payload
    }
}

/// The app's version and build, read from the bundle once.
enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// "3.1.0 (12)".
    static var display: String { "\(short) (\(build))" }
}
