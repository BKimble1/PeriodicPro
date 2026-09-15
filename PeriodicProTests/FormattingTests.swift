import Foundation
import Testing
@testable import PeriodicPro

@Suite("Presentation formatting")
struct FormattingTests {
    private let catalog = TestCatalog.shared

    @Test("Electron configurations render with real superscripts")
    func superscriptFormatting() {
        #expect(SuperscriptFormatter.applyingSuperscripts(to: "[Ne] 3s1") == "[Ne] 3s\u{00B9}")
        #expect(SuperscriptFormatter.applyingSuperscripts(to: "1s2 2s2 2p6")
                == "1s\u{00B2} 2s\u{00B2} 2p\u{2076}")
        #expect(SuperscriptFormatter.applyingSuperscripts(to: "[Xe] 4f14 5d10 6s1")
                == "[Xe] 4f\u{00B9}\u{2074} 5d\u{00B9}\u{2070} 6s\u{00B9}")
    }

    @Test("Shell numbers are never turned into superscripts")
    func principalQuantumNumbersStayInline() {
        let formatted = SuperscriptFormatter.applyingSuperscripts(to: "[Ar] 3d10 4s2 4p3")
        #expect(formatted.hasPrefix("[Ar] 3d"))
        #expect(formatted.contains("4s"))
        #expect(!formatted.contains("\u{2074}s"))
    }

    @Test("Every bundled configuration formats without losing characters")
    func allConfigurationsFormat() {
        for element in catalog.elements {
            let formatted = element.formattedElectronConfiguration
            #expect(formatted.count == element.electronConfiguration.count,
                    "\(element.name) lost characters while formatting")
            #expect(!formatted.isEmpty)
        }
    }

    @Test("Atomic mass shows decimals for weighted elements and a whole number otherwise")
    func atomicMassFormatting() {
        let oxygen = TestCatalog.element("O")
        #expect(oxygen.formattedAtomicMass.hasSuffix(" u"))
        #expect(oxygen.formattedAtomicMass.contains("."))
        #expect(oxygen.atomicMassFootnote == nil)

        let technetium = TestCatalog.element("Tc")
        #expect(technetium.atomicMassIsMassNumber)
        #expect(!technetium.formattedAtomicMass.contains("."))
        #expect(technetium.atomicMassFootnote != nil)
    }

    @Test("Temperatures show both kelvin and celsius")
    func temperatureFormatting() {
        let iron = TestCatalog.element("Fe")
        guard let display = iron.temperatureDisplay(iron.meltingPointK) else {
            Issue.record("Iron should have a melting point")
            return
        }
        #expect(display.contains("K"))
        #expect(display.contains("\u{00B0}C"))
        #expect(iron.temperatureDisplay(nil) == nil)
    }

    @Test("Densities use g/cm³ for solids and g/L for gases")
    func densityFormatting() {
        let osmium = TestCatalog.element("Os")
        #expect(osmium.densityDisplay?.contains("g/cm") == true)

        let oxygen = TestCatalog.element("O")
        #expect(oxygen.densityDisplay?.contains("g/L") == true)
    }

    @Test("Group display falls back to an em dash on the f-block")
    func groupDisplay() {
        #expect(TestCatalog.element("Fe").groupDisplay == "8")
        #expect(TestCatalog.element("Ce").groupDisplay == "\u{2014}")
        #expect(TestCatalog.element("U").isInnerTransition)
    }

    @Test("Discovery lines combine the person and the year when both are known")
    func discoveryDisplay() {
        for element in catalog.elements {
            let display = element.discoveryDisplay
            if element.discoveryYear == nil && element.discoveredBy == nil {
                #expect(display == nil)
            } else {
                #expect(display?.isEmpty == false)
            }
        }
    }

    @Test("VoiceOver spells out symbols instead of reading them as words")
    func accessibilityLabels() {
        #expect("Na".spelledOutForVoiceOver == "N a")
        let sodium = TestCatalog.element("Na")
        #expect(sodium.accessibilityDescription.contains("Sodium"))
        #expect(sodium.accessibilityDescription.contains("atomic number 11"))
        #expect(sodium.accessibilityDescription.contains("Alkali Metal"))
    }

    @Test("Every element exposes a complete accessibility description")
    func allElementsHaveAccessibilityDescriptions() {
        for element in catalog.elements {
            let description = element.accessibilityDescription
            #expect(description.contains(element.name))
            #expect(description.contains("\(element.atomicNumber)"))
        }
    }

    @Test("Session results read back sensibly")
    func studyResultSummaries() {
        let perfect = StudyResult(mode: .quiz, correct: 10, total: 10)
        #expect(perfect.accuracy == 1)
        #expect(perfect.headline == "Perfect round.")

        let none = StudyResult(mode: .flashcards, correct: 0, total: 10)
        #expect(none.accuracy == 0)
        #expect(!none.message.isEmpty)

        let empty = StudyResult(mode: .identify, correct: 0, total: 0)
        #expect(empty.accuracy == 0, "An empty session must not divide by zero")
    }

    @Test("Categories expose a distinct non-color glyph")
    func categoryGlyphsAreDistinct() {
        let glyphs = ElementCategory.allCases.map(\.glyph)
        #expect(Set(glyphs).count == ElementCategory.allCases.count,
                "Families must be distinguishable without relying on color")
        #expect(ElementCategory.displayOrder.count == ElementCategory.allCases.count)
    }
}
