import Foundation
import Testing
@testable import PeriodicPro

@Suite("Search")
struct SearchTests {
    private let elements = TestCatalog.shared.elements

    @Test("An exact symbol wins, whatever the case")
    func exactSymbolRanksFirst() {
        for query in ["O", "o"] {
            let results = ElementSearch.results(for: query, in: elements)
            #expect(results.first?.symbol == "O", "\(query) should find Oxygen first")
        }
        #expect(ElementSearch.results(for: "Na", in: elements).first?.name == "Sodium")
        #expect(ElementSearch.results(for: "fe", in: elements).first?.name == "Iron")
    }

    @Test("An atomic number finds exactly that element first")
    func atomicNumberSearch() {
        #expect(ElementSearch.results(for: "8", in: elements).first?.symbol == "O")
        #expect(ElementSearch.results(for: "26", in: elements).first?.symbol == "Fe")
        #expect(ElementSearch.results(for: "118", in: elements).first?.symbol == "Og")
        #expect(ElementSearch.results(for: "1", in: elements).first?.symbol == "H")
    }

    @Test("A name prefix beats a name that merely contains the query")
    func namePrefixRanking() {
        let results = ElementSearch.results(for: "car", in: elements)
        #expect(results.first?.name == "Carbon")

        let genResults = ElementSearch.results(for: "gen", in: elements).map(\.name)
        #expect(genResults.contains("Hydrogen"))
        #expect(genResults.contains("Nitrogen"))
        #expect(genResults.contains("Oxygen"))
    }

    @Test("Partial names match progressively")
    func partialNameSearch() {
        #expect(ElementSearch.results(for: "oxy", in: elements).first?.symbol == "O")
        #expect(ElementSearch.results(for: "magn", in: elements).first?.symbol == "Mg")
        #expect(ElementSearch.results(for: "tung", in: elements).first?.symbol == "W")
    }

    @Test("Family names are searchable")
    func categorySearch() {
        let results = ElementSearch.results(for: "noble", in: elements)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.category == .nobleGas })
    }

    @Test("Blank and nonsense queries return nothing")
    func emptyAndUnmatchedQueries() {
        #expect(ElementSearch.results(for: "", in: elements).isEmpty)
        #expect(ElementSearch.results(for: "   ", in: elements).isEmpty)
        #expect(ElementSearch.results(for: "zzzzz", in: elements).isEmpty)
        #expect(ElementSearch.results(for: "999", in: elements).isEmpty)
        #expect(ElementSearch.results(for: "0", in: elements).isEmpty)
    }

    @Test("Results are capped and deterministic")
    func resultsAreCappedAndStable() {
        let results = ElementSearch.results(for: "i", in: elements, limit: 5)
        #expect(results.count <= 5)
        let again = ElementSearch.results(for: "i", in: elements, limit: 5)
        #expect(results.map(\.atomicNumber) == again.map(\.atomicNumber))
    }

    @Test("Surrounding whitespace is ignored")
    func whitespaceIsTrimmed() {
        #expect(ElementSearch.results(for: "  gold  ", in: elements).first?.symbol == "Au")
    }

    @Test("No element appears twice in one result set")
    func resultsAreUnique() {
        for query in ["c", "n", "s", "iron", "12"] {
            let results = ElementSearch.results(for: query, in: elements)
            #expect(Set(results.map(\.atomicNumber)).count == results.count,
                    "Duplicate results for \(query)")
        }
    }
}

@Suite("Filtering")
struct FilterTests {
    private let catalog = TestCatalog.shared

    @Test("The default filter passes everything")
    func allFilterMatchesEverything() {
        let filter = ElementFilter.all
        #expect(!filter.isActive)
        #expect(filter.apply(to: catalog.elements).count == 118)
        #expect(filter.summary == "All")
    }

    @Test("Family filters split the table into metals, nonmetals and metalloids")
    func familyFilters() {
        let metals = ElementFilter(family: .metal, categories: []).apply(to: catalog.elements)
        let nonmetals = ElementFilter(family: .nonmetal, categories: []).apply(to: catalog.elements)
        let metalloids = ElementFilter(family: .metalloid, categories: []).apply(to: catalog.elements)

        #expect(metals.count + nonmetals.count + metalloids.count == 118)
        #expect(metalloids.count == 6)
        #expect(nonmetals.count == 20)
        #expect(metals.count == 92)
        #expect(metals.allSatisfy { $0.category.family == .metal })
    }

    @Test("Selecting families overrides the family chip")
    func categoryFilterTakesPrecedence() {
        let filter = ElementFilter(family: .metal, categories: [.nobleGas])
        let results = filter.apply(to: catalog.elements)
        #expect(results.count == 7)
        #expect(results.allSatisfy { $0.category == .nobleGas })
        #expect(filter.summary == "Noble Gases")
    }

    @Test("Multiple families combine")
    func multipleCategories() {
        let filter = ElementFilter(family: nil, categories: [.alkaliMetal, .halogen])
        #expect(filter.apply(to: catalog.elements).count == 12)
        #expect(filter.summary == "2 families")
    }
}
