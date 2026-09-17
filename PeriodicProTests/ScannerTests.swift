import CoreGraphics
import Foundation
import Testing
@testable import PeriodicPro

/// The scanner's accuracy lives in a pure function over a string, which is
/// where it can be tested. These are lines as a recognizer hands them over —
/// printed chemistry, OCR confusions and all.
@Suite("Reading chemistry off a page")
struct ChemistryTextRecognizerTests {
    private let catalog = TestCatalog.shared

    private func candidates(_ line: String) -> [ScanCandidate] {
        ChemistryTextRecognizer.candidates(in: line, catalog: catalog)
    }

    private func best(_ line: String) -> ScanCandidate? { candidates(line).first }

    @Test("Printed formulas")
    func printedFormulas() {
        for (line, expected) in [
            ("H2O", "H2O"), ("H₂O", "H₂O"), ("H2SO4", "H2SO4"), ("H₂SO₄", "H₂SO₄"),
            ("C6H12O6", "C6H12O6"), ("NaCl", "NaCl"), ("C8H10N4O2", "C8H10N4O2"),
            ("C9H8O4", "C9H8O4"), ("CO2", "CO2"), ("CaCO3", "CaCO3"),
        ] {
            guard let candidate = best(line) else {
                Issue.record("\(line) was not recognized at all")
                continue
            }
            if case .formula = candidate.query {} else {
                Issue.record("\(line) should be a formula, was \(candidate.kindDescription)")
            }
            #expect(candidate.text == expected)
        }
    }

    @Test("A line with a name and a formula in it yields both")
    func nameAndFormulaOnOneLine() {
        let found = candidates("Sulfuric acid H2SO4")
        #expect(found.contains { if case .formula = $0.query { return $0.text == "H2SO4" } else { return false } })
        #expect(found.contains { if case .name = $0.query { return true } else { return false } })
        // The formula ranks first: it is the more specific claim.
        if case .formula = found.first?.query {} else {
            Issue.record("the formula should be offered first, got \(String(describing: found.first))")
        }
    }

    @Test("The OCR confusions chemistry can resolve, and only those")
    func repairsOnlyWhatItCan() {
        // A zero where an oxygen belongs. Note that "H20" parses perfectly
        // well as twenty hydrogens, which is why "does it parse" is not the
        // question — "does it name something" is.
        #expect(ChemistryTextRecognizer.repaired("H20", catalog: catalog) == "H2O")
        #expect(ChemistryTextRecognizer.repaired("C02", catalog: catalog) == "CO2")
        #expect(ChemistryTextRecognizer.repaired("NaCI", catalog: catalog) == "NaCl")
        #expect(ChemistryTextRecognizer.repaired("H2S04", catalog: catalog) == "H2SO4")
        #expect(ChemistryTextRecognizer.repaired("C6H1206", catalog: catalog) == "C6H12O6")
        // Already names something: never second-guessed. C60 also parses and
        // is buckminsterfullerene, so it has to survive the same rule that
        // rewrites H20.
        #expect(ChemistryTextRecognizer.repaired("C60", catalog: catalog) == nil)
        #expect(ChemistryTextRecognizer.repaired("H2O", catalog: catalog) == nil)
        #expect(ChemistryTextRecognizer.repaired("CO2", catalog: catalog) == nil)
        #expect(ChemistryTextRecognizer.repaired("NaCl", catalog: catalog) == nil)
        // Nothing a substitution can rescue: left exactly as it was read.
        #expect(ChemistryTextRecognizer.repaired("hello", catalog: catalog) == nil)
        #expect(ChemistryTextRecognizer.repaired("2026", catalog: catalog) == nil,
                "a year is not a coefficient and a formula")
    }

    @Test("Typography is folded; subscripts and superscripts are not")
    func normalizing() {
        #expect(ChemistryTextRecognizer.normalize("SO\u{2084}\u{00B2}\u{2212}") == "SO₄²-")
        #expect(ChemistryTextRecognizer.normalize("  H2O  ") == "H2O")
        #expect(ChemistryTextRecognizer.normalize("CuSO4\u{2022}5H2O") == "CuSO4·5H2O")
        // A superscript survives normalizing, because the parser needs to tell
        // it from a subscript: one is a charge and the other is a count.
        let charged = best("SO\u{2084}\u{00B2}\u{2212}")
        if case .formula(let parsed, _) = charged?.query {
            #expect(parsed.charge == -2)
            #expect(parsed.composition == [16: 1, 8: 4])
        } else {
            Issue.record("a printed sulfate ion should read as a formula with a charge")
        }
    }

    @Test("Names that look like names")
    func chemicalNames() {
        for name in ["Caffeine", "Acetylsalicylic acid", "sodium chloride", "ethanol",
                     "2-propanol", "carbon dioxide", "hydrochloric acid", "glucose",
                     "N,N-dimethylformamide", "cholesterol", "beta-carotene"] {
            #expect(ChemistryTextRecognizer.looksLikeChemicalName(name, elements: catalog),
                    "\(name) should read as a chemical name")
        }
    }

    @Test("And prose that does not")
    func prosePassesBy() {
        // Every one of these ends or begins the way a chemical name does, and
        // none of them is one. A name has to carry two signals, not one.
        for text in ["provide", "different", "state", "control", "outside",
                     "the", "and then", "figure", "table of contents",
                     "This chapter describes how reactions proceed in solution"] {
            #expect(!ChemistryTextRecognizer.looksLikeChemicalName(text, elements: catalog),
                    "\(text) should not be taken for a chemical name")
        }
        #expect(candidates("The quick brown fox jumps over the lazy dog").isEmpty)
        #expect(candidates("Chapter 4 — Reactions in aqueous solution").isEmpty)
    }

    @Test("Structure identifiers read off a page")
    func structureIdentifiers() {
        #expect(best("BSYNRYMUTXBXSQ-UHFFFAOYSA-N")?.query == .inchiKey("BSYNRYMUTXBXSQ-UHFFFAOYSA-N"))
        #expect(best("InChI=1S/H2O/h1H2")?.query == .inchi("InChI=1S/H2O/h1H2"))
        #expect(best("CC(=O)OC1=CC=CC=C1C(=O)O")?.query == .smiles("CC(=O)OC1=CC=CC=C1C(=O)O"))
    }

    @Test("A sheet with several formulas offers all of them")
    func multipleFormulasOnOneSheet() {
        let found = candidates("H2O  NaCl  C6H12O6  H2SO4")
        let formulas = found.compactMap { candidate -> String? in
            if case .formula = candidate.query { return candidate.text }
            return nil
        }
        #expect(Set(formulas) == ["H2O", "NaCl", "C6H12O6", "H2SO4"])
    }

    @Test("Nothing pathological is read")
    func hostileLines() {
        #expect(candidates("").isEmpty)
        #expect(candidates("   ").isEmpty)
        #expect(candidates(String(repeating: "C", count: 4_000)).isEmpty)
        // A long token cannot make the repair loop expensive: it is not tried.
        #expect(ChemistryTextRecognizer.repaired(String(repeating: "0", count: 200),
                                                 catalog: catalog) == nil)
        #expect(ChemistryTextRecognizer.maximumVariants <= 64)
    }
}

/// The rule that keeps the scanner from opening a page on the first frame that
/// happens to parse.
@Suite("Deciding the camera has settled")
struct ScanStabilizerTests {
    private func candidate(
        _ text: String, confidence: Double = 1, at origin: CGPoint = CGPoint(x: 0.4, y: 0.4)
    ) -> ScanCandidate {
        ScanCandidate(
            text: text, raw: text,
            query: ChemicalQueryClassifier.classify(text, catalog: TestCatalog.shared),
            confidence: confidence,
            bounds: CGRect(origin: origin, size: CGSize(width: 0.2, height: 0.05))
        )
    }

    @Test("The same thing, several times, over long enough")
    func stableCandidateIsDelivered() {
        var stabilizer = ScanStabilizer()
        let start = ContinuousClock.now
        let water = candidate("H2O")
        #expect(stabilizer.observe(water, at: start) == nil, "one frame is not enough")
        #expect(stabilizer.observe(water, at: start.advanced(by: .milliseconds(150))) == nil)
        // Three sightings, but only 300 ms: the duration floor still holds.
        #expect(stabilizer.observe(water, at: start.advanced(by: .milliseconds(300))) == nil)
        #expect(stabilizer.observe(water, at: start.advanced(by: .milliseconds(450))) != nil)
    }

    @Test("A camera moving across a page never accumulates a result")
    func movingCameraIsRejected() {
        var stabilizer = ScanStabilizer()
        let start = ContinuousClock.now
        // Three different readings in a row, as a pan produces.
        #expect(stabilizer.observe(candidate("H2O"), at: start) == nil)
        #expect(stabilizer.observe(candidate("NaCl"), at: start.advanced(by: .milliseconds(200))) == nil)
        #expect(stabilizer.observe(candidate("CO2"), at: start.advanced(by: .milliseconds(400))) == nil)
        #expect(stabilizer.observe(candidate("H2O"), at: start.advanced(by: .milliseconds(600))) == nil,
                "the count restarted when the reading changed")
    }

    @Test("The same text drifting across the frame is a different thing")
    func driftResetsTheCount() {
        var stabilizer = ScanStabilizer()
        let start = ContinuousClock.now
        _ = stabilizer.observe(candidate("H2O", at: CGPoint(x: 0.1, y: 0.1)), at: start)
        _ = stabilizer.observe(candidate("H2O", at: CGPoint(x: 0.12, y: 0.1)),
                               at: start.advanced(by: .milliseconds(200)))
        // A jump most of the way across the frame: not the same sighting.
        #expect(stabilizer.observe(candidate("H2O", at: CGPoint(x: 0.9, y: 0.8)),
                                   at: start.advanced(by: .milliseconds(400))) == nil)
        #expect(stabilizer.observe(candidate("H2O", at: CGPoint(x: 0.9, y: 0.8)),
                                   at: start.advanced(by: .milliseconds(600))) == nil)
    }

    @Test("A low-confidence reading is never acted on")
    func lowConfidenceIsRejected() {
        var stabilizer = ScanStabilizer()
        let start = ContinuousClock.now
        for step in 0..<6 {
            let result = stabilizer.observe(
                candidate("H2O", confidence: 0.2),
                at: start.advanced(by: .milliseconds(200 * step))
            )
            #expect(result == nil, "a reading below the confidence floor must never settle")
        }
    }

    @Test("Nothing in frame resets the count")
    func nothingInFrameResets() {
        var stabilizer = ScanStabilizer()
        let start = ContinuousClock.now
        _ = stabilizer.observe(candidate("H2O"), at: start)
        _ = stabilizer.observe(candidate("H2O"), at: start.advanced(by: .milliseconds(200)))
        _ = stabilizer.observe(nil, at: start.advanced(by: .milliseconds(300)))
        #expect(stabilizer.observe(candidate("H2O"), at: start.advanced(by: .milliseconds(500))) == nil)
    }

    @Test("After a result the scanner holds, so the sheet is not replaced at once")
    func resultsAreFollowedByAPause() {
        var stabilizer = ScanStabilizer()
        let start = ContinuousClock.now
        let water = candidate("H2O")
        for step in 0..<3 { _ = stabilizer.observe(water, at: start.advanced(by: .milliseconds(200 * step))) }
        #expect(stabilizer.observe(water, at: start.advanced(by: .milliseconds(600))) != nil)
        // Straight afterwards, everything is ignored.
        for step in 4..<8 {
            #expect(stabilizer.observe(candidate("NaCl"), at: start.advanced(by: .milliseconds(200 * step))) == nil)
        }
    }

    @Test("Progress reads as progress")
    func progressGrows() {
        var stabilizer = ScanStabilizer()
        #expect(stabilizer.progress == 0)
        let start = ContinuousClock.now
        _ = stabilizer.observe(candidate("H2O"), at: start)
        #expect(stabilizer.progress > 0 && stabilizer.progress < 1)
    }
}

/// What the scanner does with a result: the device first, then the network,
/// then a clear answer either way.
@MainActor
@Suite("Resolving what the scanner read")
struct ChemistryScannerModelTests {
    private let elements = TestCatalog.shared

    private func offlineStore() -> CompoundStore {
        CompoundStore(container: nil, catalog: TestCompounds.catalog, isOnlineLookupEnabled: false)
    }

    private func stubbedStore() -> CompoundStore {
        CompoundStore(
            container: nil, catalog: TestCompounds.catalog,
            client: PubChemClient(transport: CatalogBackedStubTransport(catalog: TestCompounds.catalog),
                                  maximumRetries: 0, minimumGap: .zero)
        )
    }

    private func candidate(_ text: String) -> ScanCandidate {
        ScanCandidate(
            text: text, raw: text,
            query: ChemicalQueryClassifier.classify(text, catalog: elements),
            confidence: 1, bounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.05)
        )
    }

    @Test("A formula the device knows resolves with the phone offline")
    func localFirst() {
        let model = ChemistryScannerModel()
        let store = offlineStore()
        model.select(candidate("H2O"), store: store)
        guard case .found(_, let match) = model.phase else {
            Issue.record("H2O should resolve from the catalog, got \(model.phase)")
            return
        }
        #expect(match.name == "Water")
        #expect(match.isLocal, "a catalog match is a local record, and needs no network")
    }

    @Test("A formula nothing knows, with no network, is a clear not-found")
    func offlineMiss() {
        let model = ChemistryScannerModel()
        model.select(candidate("Nh2O3"), store: offlineStore())
        guard case .notFound = model.phase else {
            Issue.record("an unknown formula offline should be not-found, got \(model.phase)")
            return
        }
    }

    @Test("A name reaches PubChem only after it has settled")
    func remoteLookup() async {
        let model = ChemistryScannerModel()
        model.select(candidate("caffeine"), store: stubbedStore())
        await model.waitForPendingLookup()
        guard case .found(_, let match) = model.phase else {
            Issue.record("caffeine should resolve, got \(model.phase)")
            return
        }
        #expect(match.name.lowercased().contains("caffeine"))
    }

    @Test("Frames alone never start a lookup; settling does")
    func framesDoNotResolve() {
        let model = ChemistryScannerModel(phase: .scanning)
        let store = offlineStore()
        let start = ContinuousClock.now

        // Two frames: read, but not settled.
        model.observe(lines: [("H2O", 1, CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.05))],
                      catalog: elements, store: store, at: start)
        #expect(model.phase == .scanning)
        #expect(!model.visible.isEmpty, "it read the line even though it has not acted on it")

        model.observe(lines: [("H2O", 1, CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.05))],
                      catalog: elements, store: store, at: start.advanced(by: .milliseconds(200)))
        #expect(model.phase == .scanning)

        // The third, past the duration floor, settles it.
        model.observe(lines: [("H2O", 1, CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.05))],
                      catalog: elements, store: store, at: start.advanced(by: .milliseconds(500)))
        guard case .found = model.phase else {
            Issue.record("three steady frames should settle, got \(model.phase)")
            return
        }
    }

    @Test("A page with several formulas offers all of them to choose from")
    func multipleCandidatesAreOffered() {
        let model = ChemistryScannerModel(phase: .scanning)
        model.observe(
            lines: [
                ("H2O", 1, CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)),
                ("NaCl", 1, CGRect(x: 0.1, y: 0.3, width: 0.2, height: 0.05)),
                ("C6H12O6", 1, CGRect(x: 0.1, y: 0.5, width: 0.3, height: 0.05)),
            ],
            catalog: elements, store: offlineStore()
        )
        let texts = Set(model.visible.map(\.text))
        #expect(texts.isSuperset(of: ["H2O", "NaCl", "C6H12O6"]))
    }

    @Test("Resuming clears the result and starts looking again")
    func resuming() {
        let model = ChemistryScannerModel()
        model.select(candidate("H2O"), store: offlineStore())
        guard case .found = model.phase else {
            Issue.record("expected a result to resume from")
            return
        }
        model.resume()
        #expect(model.phase == .scanning)
        #expect(model.visible.isEmpty)
        #expect(model.progress == 0)
    }

    @Test("Skeletal diagrams are not read, and the app says so")
    func structureRecognitionIsHonest() {
        let model = ChemistryScannerModel()
        #expect(!model.readsStructureDiagrams)
        #expect(!UnavailableStructureRecognizer().isAvailable)
        let message = StructureRecognitionAvailability.unavailableMessage
        #expect(message.contains("does not ship one yet"))
        for claim in ["recognizes structures", "reads diagrams", "new compound"] {
            #expect(!message.lowercased().contains(claim))
        }
    }
}
