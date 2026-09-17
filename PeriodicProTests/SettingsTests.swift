import Foundation
import SwiftUI
import Testing
@testable import PeriodicPro

/// The destinations Settings, the paywall and the share sheet point at.
///
/// These are exact-string assertions on purpose. An App Store listing, a
/// privacy answer and every shared quiz link are built on them, and a typo in
/// one of them is a dead legal link rather than a visual bug.
@Suite("Elemora destinations")
struct ElemoraLinksTests {
    @Test("Every destination is the documented one")
    func destinations() {
        #expect(ElemoraLinks.websiteString == "https://elemora.idlery.com")
        #expect(ElemoraLinks.privacyString == "https://elemora.idlery.com/privacy")
        #expect(ElemoraLinks.termsString == "https://elemora.idlery.com/terms")
        #expect(ElemoraLinks.supportString == "https://elemora.idlery.com/support")
        #expect(ElemoraLinks.supportEmailAddress == "support@idlery.com")
        #expect(ElemoraLinks.quizBaseString == "https://elemora.idlery.com/quiz/")
        #expect(ElemoraLinks.host == "elemora.idlery.com")
    }

    @Test("Every destination is a usable https URL on the one host")
    func wellFormed() throws {
        for url in [ElemoraLinks.website, ElemoraLinks.privacy, ElemoraLinks.terms,
                    ElemoraLinks.support, ElemoraLinks.quizBase] {
            let resolved = try #require(url)
            #expect(resolved.scheme == "https")
            #expect(resolved.host() == ElemoraLinks.host)
        }
    }

    @Test("The support mail is addressed, subjected and carries the build")
    func supportMail() throws {
        let url = try #require(ElemoraLinks.supportMail(version: "3.1.0", build: "42"))
        #expect(url.scheme == "mailto")
        let text = url.absoluteString
        #expect(text.contains(ElemoraLinks.supportEmailAddress))
        #expect(text.contains("Elemora%20Support"))
        #expect(text.contains("3.1.0"))
        #expect(text.contains("42"))
    }

    @Test("A quiz URL is built from the same base the router recognizes")
    func quizURLs() throws {
        let url = try #require(ElemoraLinks.quizURL(payload: "1abcDEF-_"))
        #expect(url.absoluteString == "https://elemora.idlery.com/quiz/1abcDEF-_")
        #expect(ElemoraLinks.quizPayload(from: url) == "1abcDEF-_")
    }
}

/// The appearance preference: three choices, one storage key, and the mapping
/// the root view applies.
@Suite("Appearance")
struct AppAppearanceTests {
    @Test("Three choices, and System means no override")
    func mapping() {
        #expect(AppAppearance.allCases.map(\.rawValue) == ["system", "light", "dark"])
        #expect(AppAppearance.system.colorScheme == nil)
        #expect(AppAppearance.light.colorScheme == .light)
        #expect(AppAppearance.dark.colorScheme == .dark)
        #expect(AppAppearance.storageKey == "appAppearance")
    }

    @Test("The stored value round-trips, and anything unknown falls back to System")
    func storage() {
        let defaults = UserDefaults(suiteName: "elemora.appearance.tests")
        defaults?.removePersistentDomain(forName: "elemora.appearance.tests")
        for appearance in AppAppearance.allCases {
            defaults?.set(appearance.rawValue, forKey: AppAppearance.storageKey)
            let raw = defaults?.string(forKey: AppAppearance.storageKey) ?? ""
            #expect(AppAppearance(rawValue: raw) == appearance)
        }
        #expect(AppAppearance(rawValue: "sepia") == nil)
        defaults?.removePersistentDomain(forName: "elemora.appearance.tests")
    }

    @Test("Every appearance has a symbol the app is allowed to draw")
    @MainActor
    func symbols() {
        for appearance in AppAppearance.allCases {
            #expect(SFSymbolAllowlist.resolved(appearance.symbolName) == appearance.symbolName,
                    "\(appearance.symbolName) does not resolve")
        }
    }
}

/// The app's own version strings, which Settings and the support mail show.
@Suite("App version")
struct AppVersionTests {
    @Test("Version and build read as something, and display combines them")
    func version() {
        #expect(!AppVersion.short.isEmpty)
        #expect(!AppVersion.build.isEmpty)
        #expect(AppVersion.display == "\(AppVersion.short) (\(AppVersion.build))")
    }
}
