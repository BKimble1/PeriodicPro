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

    @Test("An element symbol is read as that element")
    func elementSymbols() {
        for (symbol, number) in [("Na", 11), ("Fe", 26), ("C", 6), ("Cl", 17), ("Co", 27)] {
            let read = best(symbol)
            #expect(read?.element == number,
                    "\(symbol) should read as element \(number), got \(String(describing: read))")
            #expect(read?.kindDescription == "Element")
        }
    }

    @Test("A symbol has to be spelled the way the table spells it")
    func symbolCaseMatters() {
        // AT, IN, NO, BE, AS, AM and HE are English words in capitals. Reading
        // them as astatine, indium, nobelium, beryllium, arsenic, americium
        // and helium would make a page of prose a stream of wrong answers.
        for shouting in ["NA", "IN", "NO", "BE", "AS", "HE", "AT", "na", "fe"] {
            #expect(candidates(shouting).allSatisfy { $0.element == nil },
                    "\(shouting) is not how the table spells an element symbol")
        }
    }

    @Test("An element's name, on a line of its own, is that element")
    func elementNames() {
        #expect(best("Sodium")?.element == 11)
        #expect(best("sodium")?.element == 11)
        #expect(best("IRON")?.element == 26)
        #expect(best("Chlorine")?.element == 17)
        #expect(best("Carbon")?.element == 6)
        // A periodic table cell is a line each: the number, the symbol, the
        // name and the mass. Any of the three readable ones lands on sodium.
        #expect(best("Na")?.element == best("Sodium")?.element)
    }

    @Test("An element's name inside a sentence is the word, not the element")
    func elementNamesInProse() {
        for sentence in [
            "The lead pipe was replaced",
            "a gold standard for this",
            "iron out the differences",
        ] {
            #expect(candidates(sentence).allSatisfy { $0.element == nil },
                    "\(sentence) is prose, and lead, gold and iron are words in it")
        }
    }

    @Test("A formula that happens to start with a symbol is still a formula")
    func formulasAreNotElements() {
        // Every one of these would be a wrong answer as an element: C60 is
        // buckminsterfullerene, O2 is dioxygen, CO is carbon monoxide and
        // sodium chloride is a salt.
        for formula in ["C60", "O2", "H2O", "CO", "Fe2O3"] {
            #expect(best(formula)?.element == nil, "\(formula) is a formula, not an element")
        }
        #expect(best("Sodium chloride")?.element == nil)
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
            bounds: CGRect(origin: origin, size: CGSize(width: 0.2, height: 0.05)),
            element: nil
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
        // Two sightings, deliberately: a third at 400 ms would already span
        // `minimumDuration` and deliver, and the result being tested here is
        // the one at 600.
        _ = stabilizer.observe(water, at: start)
        _ = stabilizer.observe(water, at: start.advanced(by: .milliseconds(200)))
        #expect(stabilizer.observe(water, at: start.advanced(by: .milliseconds(600))) != nil)
        // Straight afterwards, everything is ignored for `settleAfterResult`.
        for step in 1...4 {
            #expect(stabilizer.observe(candidate("NaCl"),
                                       at: start.advanced(by: .milliseconds(600 + 200 * step))) == nil)
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

    /// Built the way the recognizer builds one, element tag and all, so a
    /// test that hands the model a candidate hands it the same thing the
    /// camera would.
    private func candidate(_ text: String) -> ScanCandidate {
        ChemistryTextRecognizer.candidates(in: text, catalog: elements).first
            ?? ScanCandidate(
                text: text, raw: text,
                query: ChemicalQueryClassifier.classify(text, catalog: elements),
                confidence: 1, bounds: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.05),
                element: nil
            )
    }

    @Test("A formula the device knows resolves with the phone offline")
    func localFirst() {
        let model = ChemistryScannerModel()
        let store = offlineStore()
        model.select(candidate("H2O"), store: store, catalog: elements)
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
        model.select(candidate("Nh2O3"), store: offlineStore(), catalog: elements)
        guard case .notFound = model.phase else {
            Issue.record("an unknown formula offline should be not-found, got \(model.phase)")
            return
        }
    }

    @Test("A name reaches PubChem only after it has settled")
    func remoteLookup() async {
        let model = ChemistryScannerModel()
        model.select(candidate("caffeine"), store: stubbedStore(), catalog: elements)
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

    @Test("Pointing at an element identifies it, offline and with no request")
    func elementResolvesFromTheBundle() {
        let model = ChemistryScannerModel()
        model.select(candidate("Na"), store: offlineStore(), catalog: elements)
        guard case .foundElement(_, let element) = model.phase else {
            Issue.record("Na should identify sodium, got \(model.phase)")
            return
        }
        #expect(element.atomicNumber == 11)
        #expect(element.name == "Sodium")
    }

    @Test("And by its name as well as its symbol")
    func elementNameResolves() {
        let model = ChemistryScannerModel()
        model.select(candidate("Sodium"), store: offlineStore(), catalog: elements)
        guard case .foundElement(_, let element) = model.phase else {
            Issue.record("the word Sodium should identify sodium, got \(model.phase)")
            return
        }
        #expect(element.atomicNumber == 11)
    }

    @Test("Three steady frames on a table cell open the element")
    func elementSettlesFromFrames() {
        let model = ChemistryScannerModel(phase: .scanning)
        let store = offlineStore()
        let start = ContinuousClock.now
        let cell = CGRect(x: 0.45, y: 0.44, width: 0.1, height: 0.04)
        for offset in [0, 200, 500] {
            model.observe(lines: [("Fe", 1, cell)], catalog: elements, store: store,
                          at: start.advanced(by: .milliseconds(offset)))
        }
        guard case .foundElement(_, let element) = model.phase else {
            Issue.record("holding on Fe should identify iron, got \(model.phase)")
            return
        }
        #expect(element.symbol == "Fe")
    }

    @Test("An element outranks everything else on the same cell")
    func elementWinsTheFrame() {
        let model = ChemistryScannerModel(phase: .scanning)
        // A periodic table cell, as a recognizer hands it over: the atomic
        // number, the symbol, the name and the mass, each its own line.
        model.observe(
            lines: [
                ("11", 1, CGRect(x: 0.42, y: 0.40, width: 0.04, height: 0.03)),
                ("Na", 1, CGRect(x: 0.46, y: 0.44, width: 0.08, height: 0.05)),
                ("Sodium", 1, CGRect(x: 0.44, y: 0.50, width: 0.12, height: 0.03)),
                ("22.990", 1, CGRect(x: 0.44, y: 0.54, width: 0.12, height: 0.03)),
            ],
            catalog: elements, store: offlineStore()
        )
        #expect(model.visible.first?.element == 11,
                "the element is the most specific thing on the cell and should lead")
        #expect(model.visible.allSatisfy { $0.element == nil || $0.element == 11 })
    }

    @Test("A lookup that already missed is not made a second time")
    func missesAreRemembered() async {
        let model = ChemistryScannerModel()
        let store = stubbedStore()
        model.select(candidate("Nh2O3"), store: store, catalog: elements)
        await model.waitForPendingLookup()
        guard case .notFound = model.phase else {
            Issue.record("an unknown formula should be not-found, got \(model.phase)")
            return
        }
        // Second time: the answer is known, so the phase is the answer rather
        // than another spell in `.resolving` waiting on the same request.
        model.select(candidate("Nh2O3"), store: store, catalog: elements)
        guard case .notFound = model.phase else {
            Issue.record("a remembered miss should answer at once, got \(model.phase)")
            return
        }
    }

    @Test("Resuming clears the result and starts looking again")
    func resuming() {
        let model = ChemistryScannerModel()
        model.select(candidate("H2O"), store: offlineStore(), catalog: elements)
        guard case .found = model.phase else {
            Issue.record("expected a result to resume from")
            return
        }
        model.resume()
        #expect(model.phase == .scanning)
        #expect(model.visible.isEmpty)
        #expect(model.progress == 0)
    }

    @Test("Only the middle of the frame is read")
    func regionOfInterestIsTheMiddleBand() {
        let region = LiveTextScannerView.regionOfInterest
        // Inside the frame, and actually a band rather than the whole thing:
        // a region that covered the frame would be the bug this replaced.
        #expect(region.minX >= 0)
        #expect(region.minY >= 0)
        #expect(region.maxX <= 1)
        #expect(region.maxY <= 1)
        #expect(region.width < 1)
        #expect(region.height < 0.5)
        // Centered vertically, because that is where the reticle is drawn and
        // where somebody aiming a phone puts the thing they mean.
        let center = region.midY
        #expect(center > 0.35)
        #expect(center < 0.65)
    }
}
