import Foundation
import Testing
@testable import PeriodicPro

/// Every syntax `ChemicalFormulaParser` claims to read, read.
///
/// The type's documentation makes a list of promises. This is that list,
/// asserted — including the two the documentation is careful to limit.
@Suite("Reading a molecular formula")
struct ChemicalFormulaParserTests {
    private let catalog = TestCatalog.shared

    private func parse(_ text: String) -> ParsedFormula? {
        ChemicalFormulaParser.parse(text, catalog: catalog)
    }

    private func composition(_ text: String) -> [Int: Int]? { parse(text)?.composition }

    @Test("ASCII counts, including the ones the old builder refused")
    func asciiCounts() {
        #expect(composition("H2O") == [1: 2, 8: 1])
        #expect(composition("NaCl") == [11: 1, 17: 1])
        #expect(composition("C6H12O6") == [6: 6, 1: 12, 8: 6])
        #expect(composition("C27H46O") == [6: 27, 1: 46, 8: 1])
        #expect(composition("C40H56") == [6: 40, 1: 56])
        #expect(composition("C55H72MgN4O5") == [6: 55, 1: 72, 12: 1, 7: 4, 8: 5])
    }

    @Test("Unicode subscripts read the same as the digits they stand for")
    func unicodeSubscripts() {
        #expect(composition("H₂O") == composition("H2O"))
        #expect(composition("C₆H₁₂O₆") == composition("C6H12O6"))
        #expect(composition("C₂H₆O") == [6: 2, 1: 6, 8: 1])
    }

    @Test("Two-letter symbols beat one-letter ones, so Co is cobalt and CO is not")
    func symbolsAreGreedy() {
        #expect(composition("Co") == [27: 1])
        #expect(composition("CO") == [6: 1, 8: 1])
        #expect(composition("CoCl2") == [27: 1, 17: 2])
        #expect(composition("Nao") == nil, "No is nobelium and Nao is nothing")
        #expect(composition("Xx2") == nil)
        #expect(composition("h2o") == nil, "symbols are case-sensitive")
        #expect(composition("") == nil)
        #expect(composition("water") == nil)
    }

    @Test("Parentheses and brackets, nested")
    func brackets() {
        #expect(composition("Ca(OH)2") == [20: 1, 8: 2, 1: 2])
        #expect(composition("Al2(SO4)3") == [13: 2, 16: 3, 8: 12])
        #expect(composition("K4[Fe(CN)6]") == [19: 4, 26: 1, 6: 6, 7: 6])
        #expect(composition("(NH4)2SO4") == [7: 2, 1: 8, 16: 1, 8: 4])
        #expect(composition("Ca(OH") == nil, "an unclosed bracket is not a formula")
        #expect(composition("Ca(OH))2") == nil)
    }

    @Test("Hydrates, with every separator people write and with coefficients")
    func hydrates() {
        let pentahydrate: [Int: Int] = [29: 1, 16: 1, 8: 9, 1: 10]
        #expect(composition("CuSO4·5H2O") == pentahydrate)
        #expect(composition("CuSO4*5H2O") == pentahydrate)
        #expect(composition("CuSO4.5H2O") == pentahydrate)
        #expect(composition("CuSO4•5H2O") == pentahydrate)
        #expect(composition("Na2CO3.10H2O") == [11: 2, 6: 1, 8: 13, 1: 20])
        #expect(composition("MgSO4*7H2O") == [12: 1, 16: 1, 8: 11, 1: 14])
    }

    @Test("The four unambiguous ways of writing a charge")
    func charges() {
        // Sign first, which is PubChem's own notation.
        #expect(parse("SO4-2")?.charge == -2)
        #expect(parse("SO4-2")?.composition == [16: 1, 8: 4])
        #expect(parse("Fe+3")?.charge == 3)
        #expect(parse("Fe+3")?.composition == [26: 1])
        // Superscripts.
        #expect(parse("SO4²⁻")?.charge == -2)
        #expect(parse("SO4²⁻")?.composition == [16: 1, 8: 4])
        #expect(parse("NH4⁺")?.charge == 1)
        #expect(parse("NH4⁺")?.composition == [7: 1, 1: 4])
        // A caret, which says the digits are not a subscript.
        #expect(parse("SO4^2-")?.charge == -2)
        #expect(parse("SO4^2-")?.composition == [16: 1, 8: 4])
        // Brackets, which say the same thing.
        #expect(parse("[SO4]2-")?.charge == -2)
        #expect(parse("[SO4]2-")?.composition == [16: 1, 8: 4])
        #expect(parse("[Fe(CN)6]3-")?.charge == -3)
        #expect(parse("[Fe(CN)6]3-")?.composition == [26: 1, 6: 6, 7: 6])
        // A bare sign is one.
        #expect(parse("Cl-")?.charge == -1)
        #expect(parse("Na+")?.charge == 1)
    }

    @Test("The ambiguous form resolves the way a chemist reads it")
    func theAmbiguousCase() {
        // Digits before a trailing sign are the charge when one atom is left.
        #expect(parse("Fe3+")?.composition == [26: 1])
        #expect(parse("Fe3+")?.charge == 3)
        #expect(parse("Ca2+")?.composition == [20: 1])
        #expect(parse("Ca2+")?.charge == 2)
        #expect(parse("O2-")?.composition == [8: 1])
        #expect(parse("O2-")?.charge == -2)
        // And a count when more than one atom is left.
        #expect(parse("NH4+")?.composition == [7: 1, 1: 4])
        #expect(parse("NH4+")?.charge == 1)
        #expect(parse("CO3-2")?.composition == [6: 1, 8: 3])
        #expect(parse("CO3-2")?.charge == -2)
    }

    @Test("A charge written, and a charge merely absent, are different answers")
    func explicitCharge() {
        #expect(parse("H2O")?.hasExplicitCharge == false)
        #expect(parse("H2O")?.charge == 0)
        #expect(parse("NH4+")?.hasExplicitCharge == true)
        #expect(parse("Na+")?.hasExplicitCharge == true)
    }

    @Test("Bond symbols and other structure syntax are not a formula")
    func structureStringsAreRejected() {
        #expect(parse("CC(=O)OC1=CC=CC=C1C(=O)O") == nil)
        #expect(parse("c1ccccc1") == nil)
        #expect(parse("C[C@H](N)C(=O)O") == nil)
        #expect(parse("H2O; DROP TABLE") == nil)
        #expect(parse("H2O!") == nil)
    }

    @Test("The limits are resource limits and they hold")
    func limits() {
        #expect(parse(String(repeating: "C", count: 300)) == nil, "too long")
        #expect(parse(String(repeating: "(", count: 20) + "C" + String(repeating: ")", count: 20)) == nil,
                "too deeply nested")
        // Deep enough for real chemistry, all the same.
        #expect(parse("K4[Fe(CN)6]") != nil)
        #expect(ChemicalFormulaParser.maximumLength >= 200)
    }

    @Test("Hill order comes back out of what was read")
    func hillRoundTrip() {
        #expect(parse("C27H46O")?.hill(catalog: catalog) == "C27H46O")
        #expect(parse("Ca(OH)2")?.hill(catalog: catalog) == "CaH2O2")
        #expect(parse("H₂SO₄")?.hill(catalog: catalog) == "H2O4S")
        #expect(parse("O2-")?.isMonatomic == true)
        #expect(parse("H2O")?.atomCount == 3)
        #expect(parse("C27H46O")?.elementCount == 3)
    }
}

/// One field, every identifier a chemistry learner might be holding.
@Suite("Recognizing what was typed")
struct ChemicalQueryClassifierTests {
    private let catalog = TestCatalog.shared

    private func classify(_ text: String) -> ChemicalQuery {
        ChemicalQueryClassifier.classify(text, catalog: catalog)
    }

    @Test("Names")
    func names() {
        #expect(classify("water") == .name("water"))
        #expect(classify("acetylsalicylic acid") == .name("acetylsalicylic acid"))
        #expect(classify("sodium chloride") == .name("sodium chloride"))
        #expect(classify("caffeine") == .name("caffeine"))
        #expect(classify("beta-carotene") == .name("beta-carotene"))
        #expect(classify("N,N-dimethylformamide") == .name("N,N-dimethylformamide"))
        #expect(classify("  ") == .empty)
        #expect(classify("") == .empty)
    }

    @Test("Formulas")
    func formulas() {
        if case .formula(let parsed, let text) = classify("C9H8O4") {
            #expect(parsed.composition == [6: 9, 1: 8, 8: 4])
            #expect(text == "C9H8O4")
        } else {
            Issue.record("C9H8O4 should be recognized as a formula")
        }
        if case .formula = classify("H₂O") {} else { Issue.record("H₂O is a formula") }
        if case .formula = classify("Ca(OH)2") {} else { Issue.record("Ca(OH)2 is a formula") }
        if case .formula = classify("NaCl") {} else { Issue.record("NaCl is a formula") }
        if case .formula = classify("NH4+") {} else { Issue.record("NH4+ is a formula") }
    }

    @Test("CIDs, bare and labeled")
    func cids() {
        #expect(classify("2244") == .cid(2244))
        #expect(classify("CID 2244") == .cid(2244))
        #expect(classify("cid:2244") == .cid(2244))
        #expect(classify("CID2244") == .cid(2244))
        #expect(classify("962") == .cid(962))
        #expect(ChemicalQueryClassifier.cid(in: "0") == nil)
        #expect(ChemicalQueryClassifier.cid(in: "-4") == nil)
    }

    @Test("Structure strings")
    func structures() {
        #expect(classify("CC(=O)OC1=CC=CC=C1C(=O)O") == .smiles("CC(=O)OC1=CC=CC=C1C(=O)O"))
        #expect(classify("c1ccccc1") == .smiles("c1ccccc1"))
        #expect(classify("C[C@H](N)C(=O)O") == .smiles("C[C@H](N)C(=O)O"))
        #expect(classify("InChI=1S/H2O/h1H2") == .inchi("InChI=1S/H2O/h1H2"))
        #expect(classify("BSYNRYMUTXBXSQ-UHFFFAOYSA-N") == .inchiKey("BSYNRYMUTXBXSQ-UHFFFAOYSA-N"))
        // Case does not matter, and the key comes back normalized.
        #expect(classify("bsynrymutxbxsq-uhfffaoysa-n") == .inchiKey("BSYNRYMUTXBXSQ-UHFFFAOYSA-N"))
    }

    @Test("An oxidation state is a name, not three iodines")
    func oxidationStates() {
        // Every letter of a Roman numeral is also an element symbol, so
        // without the special case Fe(III) parses cleanly into iron triiodide.
        #expect(classify("Fe(III)") == .name("Fe(III)"))
        #expect(classify("Cu(II) sulfate") == .name("Cu(II) sulfate"))
        #expect(classify("Mn(VII)") == .name("Mn(VII)"))
        #expect(ChemicalFormulaParser.parse("Fe(III)", catalog: catalog) != nil,
                "the parser itself would read it; the classifier is what declines to")
    }

    @Test("A formula wins over a SMILES string that spells the same letters")
    func formulaBeatsSmiles() {
        // CO is carbon monoxide's formula and methanol's SMILES. In a periodic
        // table app it is carbon monoxide, and the app says which it decided.
        if case .formula = ChemicalQueryClassifier.classify("CO", catalog: catalog) {} else {
            Issue.record("CO should be read as a formula here")
        }
        #expect(ChemicalQuery.formula(
            ParsedFormula(composition: [6: 1, 8: 1], charge: 0, hasExplicitCharge: false), text: "CO"
        ).kindDescription == "Molecular formula")
    }

    @Test("Suggestions are offered for names and for nothing else")
    func suggestionEligibility() {
        #expect(classify("acet").acceptsSuggestions)
        #expect(!classify("C9H8O4").acceptsSuggestions)
        #expect(!classify("2244").acceptsSuggestions)
        #expect(!classify("InChI=1S/H2O/h1H2").acceptsSuggestions)
    }

    @Test("Nothing pathological gets through")
    func hostileInput() {
        #expect(classify(String(repeating: "a", count: 5_000)) == .empty)
        #expect(classify("<script>alert(1)</script>") == .name("<script>alert(1)</script>"),
                "a name it is, and PubChemClient.isPlausibleName is what stops it being sent")
        #expect(!PubChemClient.isPlausibleName("<script>alert(1)</script>"))
        #expect(!PubChemClient.isPlausibleFormula("H2O; DROP"))
    }
}
