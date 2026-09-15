import Foundation
import Testing
import UIKit
@testable import PeriodicPro

@MainActor
@Suite("SF Symbols")
struct SFSymbolTests {
    private let catalog = TestCatalog.shared

    @Test("Every allowlisted symbol exists in this OS release")
    func allowlistResolves() {
        for name in SFSymbolAllowlist.names.sorted() {
            #expect(UIImage(systemName: name) != nil,
                    "\(name) is not an SF Symbol on this OS; it would render blank")
        }
    }

    @Test("The fallback symbol always exists")
    func fallbackResolves() {
        #expect(UIImage(systemName: SFSymbolAllowlist.fallback) != nil)
    }

    @Test("Every symbol the dataset references resolves to a real glyph")
    func datasetSymbolsResolve() {
        for element in catalog.elements {
            for use in element.uses {
                #expect(SFSymbolAllowlist.contains(use.symbolName),
                        "\(element.name) references unlisted symbol \(use.symbolName)")
                #expect(SFSymbolAllowlist.resolved(use.symbolName) == use.symbolName,
                        "\(element.name) would fall back instead of showing \(use.symbolName)")
            }
        }
    }

    @Test("An unknown name degrades to the fallback rather than to nothing")
    func unknownNameFallsBack() {
        #expect(SFSymbolAllowlist.resolved("definitely.not.a.symbol") == SFSymbolAllowlist.fallback)
        #expect(!SFSymbolAllowlist.contains("definitely.not.a.symbol"))
    }

    @Test("Category glyphs and phase glyphs resolve too")
    func uiGlyphsResolve() {
        for category in ElementCategory.allCases {
            #expect(UIImage(systemName: category.glyph) != nil, "\(category.glyph) is missing")
        }
        for phase in MatterPhase.allCases {
            #expect(UIImage(systemName: phase.symbolName) != nil, "\(phase.symbolName) is missing")
        }
        for level in MasteryLevel.allCases {
            #expect(UIImage(systemName: level.symbolName) != nil, "\(level.symbolName) is missing")
        }
        for mode in StudyMode.allCases {
            #expect(UIImage(systemName: mode.symbolName) != nil, "\(mode.symbolName) is missing")
        }
        for tab in AppTab.allCases {
            #expect(UIImage(systemName: tab.symbolName) != nil, "\(tab.symbolName) is missing")
        }
    }
}

@Suite("Catalog indexes")
struct ElementCatalogTests {
    private let catalog = TestCatalog.shared

    @Test("Lookups are consistent with the element list")
    func lookupsAgreeWithTheList() {
        for element in catalog.elements {
            #expect(catalog.element(atomicNumber: element.atomicNumber) == element)
            #expect(catalog.element(symbol: element.symbol) == element)
            #expect(catalog.element(symbol: element.symbol.lowercased()) == element)
            #expect(catalog.element(symbol: element.symbol.uppercased()) == element)
        }
        #expect(catalog.element(atomicNumber: 0) == nil)
        #expect(catalog.element(atomicNumber: 119) == nil)
        #expect(catalog.element(symbol: "Zz") == nil)
    }

    @Test("Family counts match the grouped lists")
    func familyCountsMatch() {
        for category in ElementCategory.allCases {
            #expect(catalog.count(of: category) == catalog.elements(in: category).count)
            #expect(catalog.elements(in: category).allSatisfy { $0.category == category })
        }
    }

    @Test("The three table row groups partition the table")
    func rowsPartitionTheTable() {
        let total = catalog.mainTableElements.count
            + catalog.lanthanideRow.count
            + catalog.actinideRow.count
        #expect(total == catalog.count)
    }

    @Test("Duplicate atomic numbers are collapsed rather than producing duplicate IDs")
    func duplicatesAreCollapsed() {
        let oxygen = TestCatalog.element("O")
        let duplicated = ElementCatalog(elements: [oxygen, oxygen, TestCatalog.element("H")])
        #expect(duplicated.count == 2)
        #expect(Set(duplicated.elements.map(\.atomicNumber)).count == duplicated.count)
        #expect(duplicated.elements.map(\.atomicNumber) == [1, 8], "Elements should come out sorted")
    }

    @Test("An empty catalog behaves instead of crashing")
    func emptyCatalog() {
        let empty = ElementCatalog(elements: [])
        #expect(empty.isEmpty)
        #expect(empty.count == 0)
        #expect(empty.element(atomicNumber: 1) == nil)
        #expect(empty.search("oxygen").isEmpty)
        #expect(empty.elements(in: .nobleGas).isEmpty)
        #expect(empty.count(of: .nobleGas) == 0)
    }

    @Test("Catalog search matches the standalone search function")
    func catalogSearchMatchesEngine() {
        for query in ["oxygen", "Fe", "26", "noble", "car", "zzz"] {
            #expect(catalog.search(query).map(\.atomicNumber)
                    == ElementSearch.results(for: query, in: catalog.elements).map(\.atomicNumber),
                    "Mismatch for \(query)")
        }
    }
}

@Suite("Search edge cases")
struct SearchEdgeCaseTests {
    private let catalog = TestCatalog.shared

    @Test("Family search matches whole words, so metals and nonmetals do not blur")
    func familySearchUsesWordPrefixes() {
        let metals = catalog.search("metal")
        #expect(!metals.isEmpty)
        #expect(metals.allSatisfy { $0.category.family != .nonmetal },
                "Searching \u{201C}metal\u{201D} must not return nonmetals")

        let nonmetals = catalog.search("nonmetal")
        #expect(nonmetals.allSatisfy { $0.category == .reactiveNonmetal })

        #expect(catalog.search("halogen").allSatisfy { $0.category == .halogen })
        #expect(catalog.search("lanthan").allSatisfy { $0.category == .lanthanide })
    }

    @Test("A non-positive or oversized limit is handled instead of trapping")
    func limitIsClamped() {
        #expect(catalog.search("o", limit: 0).isEmpty)
        #expect(catalog.search("o", limit: -5).isEmpty)
        #expect(catalog.search("o", limit: 10_000).count <= catalog.count)
    }

    @Test("Prefolded entries and on-the-fly folding agree for accented input")
    func foldingIsStable() {
        #expect(ElementSearch.normalize("  Oxygen  ") == "oxygen")
        #expect(ElementSearch.normalize("  IRON  ") == "iron")
        #expect(ElementSearch.normalize("\u{00C9}tain") == "etain")
    }

    @Test("Searching is stable across repeated calls")
    func repeatedSearchesAgree() {
        for query in ["s", "si", "sil", "silv", "silver"] {
            #expect(catalog.search(query).map(\.atomicNumber)
                    == catalog.search(query).map(\.atomicNumber))
        }
        #expect(catalog.search("silver").first?.symbol == "Ag")
    }
}
