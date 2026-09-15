import Foundation
import Testing
@testable import PeriodicPro

@Suite("Element dataset")
struct ElementDataTests {
    private let catalog = TestCatalog.shared

    @Test("Contains exactly the 118 confirmed elements")
    func elementCount() {
        #expect(catalog.count == 118)
    }

    @Test("Atomic numbers are 1...118 with no gaps or duplicates")
    func atomicNumbersAreComplete() {
        let numbers = catalog.elements.map(\.atomicNumber)
        #expect(Set(numbers).count == 118)
        #expect(numbers == Array(1...118))
    }

    @Test("Chemical symbols are unique and correctly cased")
    func symbolsAreUniqueAndValid() {
        let symbols = catalog.elements.map(\.symbol)
        #expect(Set(symbols).count == 118)

        for element in catalog.elements {
            #expect((1...3).contains(element.symbol.count),
                    "\(element.name) has an implausible symbol: \(element.symbol)")
            #expect(element.symbol.first?.isUppercase == true,
                    "\(element.symbol) should start with an uppercase letter")
            #expect(element.symbol.dropFirst().allSatisfy { $0.isLowercase },
                    "\(element.symbol) should have lowercase letters after the first")
        }
    }

    @Test("Names are unique and non-empty")
    func namesAreUnique() {
        let names = catalog.elements.map(\.name)
        #expect(Set(names).count == 118)
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    @Test("A handful of well-known symbols map to the right element")
    func spotCheckSymbols() {
        let expected: [Int: String] = [
            1: "H", 2: "He", 6: "C", 8: "O", 11: "Na", 19: "K", 26: "Fe",
            29: "Cu", 47: "Ag", 74: "W", 79: "Au", 80: "Hg", 82: "Pb",
            92: "U", 118: "Og",
        ]
        for (number, symbol) in expected {
            #expect(catalog.element(atomicNumber: number)?.symbol == symbol)
            #expect(catalog.element(symbol: symbol)?.atomicNumber == number)
        }
    }

    @Test("Every table position is inside the 18-column grid and unique")
    func gridPositionsAreValid() {
        var seen = Set<String>()
        for element in catalog.elements {
            #expect((1...18).contains(element.gridX), "\(element.name) has gridX \(element.gridX)")
            #expect((1...7).contains(element.gridY) || (9...10).contains(element.gridY),
                    "\(element.name) has gridY \(element.gridY)")
            let key = "\(element.gridX),\(element.gridY)"
            #expect(!seen.contains(key), "\(element.name) collides at \(key)")
            seen.insert(key)
        }
        #expect(seen.count == 118)
    }

    @Test("The f-block rows hold exactly the lanthanides and actinides")
    func innerTransitionRows() {
        #expect(catalog.lanthanideRow.map(\.atomicNumber) == Array(57...71))
        #expect(catalog.actinideRow.map(\.atomicNumber) == Array(89...103))
        #expect(catalog.mainTableElements.count == 88)
    }

    @Test("Every element belongs to exactly one family and the families total 118")
    func categoriesPartitionTheTable() {
        let total = ElementCategory.allCases.reduce(0) { $0 + catalog.elements(in: $1).count }
        #expect(total == 118)
        #expect(catalog.elements(in: .alkaliMetal).count == 6)
        #expect(catalog.elements(in: .alkalineEarthMetal).count == 6)
        #expect(catalog.elements(in: .transitionMetal).count == 38)
        #expect(catalog.elements(in: .lanthanide).count == 15)
        #expect(catalog.elements(in: .actinide).count == 15)
        #expect(catalog.elements(in: .nobleGas).count == 7)
        #expect(catalog.elements(in: .halogen).count == 6)
        #expect(catalog.elements(in: .metalloid).count == 6)
    }

    @Test("Group numbers match the column, except on the f-block")
    func groupsMatchColumns() {
        for element in catalog.elements {
            if element.isInnerTransition {
                #expect(element.group == nil, "\(element.name) should have no group number")
            } else {
                #expect(element.group == element.gridX,
                        "\(element.name) group \(String(describing: element.group)) vs column \(element.gridX)")
            }
        }
    }

    @Test("Periods follow the standard row boundaries")
    func periodsAreCorrect() {
        let upperBounds = [2, 10, 18, 36, 54, 86, 118]
        for element in catalog.elements {
            let expected = (upperBounds.firstIndex { element.atomicNumber <= $0 } ?? 6) + 1
            #expect(element.period == expected, "\(element.name) period \(element.period)")
        }
    }

    @Test("Shell electron counts sum to the atomic number")
    func shellElectronsSumToAtomicNumber() {
        for element in catalog.elements {
            let total = element.shellElectrons.reduce(0, +)
            #expect(total == element.atomicNumber,
                    "\(element.name): shells \(element.shellElectrons) sum to \(total), expected \(element.atomicNumber)")
            #expect(element.shellElectrons.allSatisfy { $0 > 0 },
                    "\(element.name) has an empty shell")
            if element.symbol == "Pd" {
                // Palladium is the one element whose outermost s subshell is
                // empty, so it occupies one fewer shell than its period.
                #expect(element.shellElectrons.count == 4,
                        "Palladium should occupy 4 shells, not \(element.shellElectrons.count)")
            } else {
                #expect(element.shellElectrons.count == element.period,
                        "\(element.name) should occupy \(element.period) shells")
            }
        }
    }

    @Test("Shell occupancies never exceed 2n squared")
    func shellsObeyCapacityLimit() {
        for element in catalog.elements {
            for (index, count) in element.shellElectrons.enumerated() {
                let n = index + 1
                let capacity = 2 * n * n
                #expect(count <= capacity,
                        "\(element.name) shell \(n) holds \(count), capacity \(capacity)")
            }
        }
    }

    @Test("Electron configurations are well formed and account for every electron")
    func electronConfigurationsParse() {
        for element in catalog.elements {
            let configuration = element.electronConfiguration
            #expect(!configuration.isEmpty, "\(element.name) has no configuration")

            var total = 0
            if let range = configuration.range(of: #"\[[A-Z][a-z]?\]"#, options: .regularExpression) {
                let core = String(configuration[range]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                guard let noble = catalog.element(symbol: core) else {
                    Issue.record("\(element.name) references unknown core [\(core)]")
                    continue
                }
                #expect(noble.category == .nobleGas,
                        "\(element.name) uses a non-noble-gas core [\(core)]")
                #expect(noble.atomicNumber < element.atomicNumber,
                        "\(element.name) uses a heavier core [\(core)]")
                total += noble.atomicNumber
            }

            for token in configuration.split(separator: " ") {
                guard !token.hasPrefix("[") else { continue }
                let characters = Array(token)
                #expect(characters.count >= 3, "\(element.name) has malformed token \(token)")
                guard characters.count >= 3 else { continue }
                #expect(characters[0].isNumber, "\(element.name) token \(token) lacks a shell number")
                #expect("spdf".contains(characters[1]),
                        "\(element.name) token \(token) has an unknown subshell")
                guard let count = Int(String(characters[2...])) else {
                    Issue.record("\(element.name) token \(token) has no electron count")
                    continue
                }
                let capacity = ["s": 2, "p": 6, "d": 10, "f": 14][String(characters[1])] ?? 0
                #expect(count >= 1 && count <= capacity,
                        "\(element.name) token \(token) exceeds subshell capacity")
                total += count
            }

            #expect(total == element.atomicNumber,
                    "\(element.name) configuration \(configuration) accounts for \(total) electrons")
        }
    }

    @Test("Known electron-configuration anomalies are preserved")
    func anomalousConfigurations() {
        let expected: [String: String] = [
            "Cr": "[Ar] 3d5 4s1",
            "Cu": "[Ar] 3d10 4s1",
            "Nb": "[Kr] 4d4 5s1",
            "Mo": "[Kr] 4d5 5s1",
            "Ru": "[Kr] 4d7 5s1",
            "Rh": "[Kr] 4d8 5s1",
            "Pd": "[Kr] 4d10",
            "Ag": "[Kr] 4d10 5s1",
            "Pt": "[Xe] 4f14 5d9 6s1",
            "Au": "[Xe] 4f14 5d10 6s1",
        ]
        for (symbol, configuration) in expected {
            #expect(TestCatalog.element(symbol).electronConfiguration == configuration,
                    "\(symbol) should be \(configuration)")
        }
    }

    @Test("Only mercury and bromine are liquid at room temperature")
    func phasesAreCorrect() {
        let liquids = catalog.elements.filter { $0.phase == .liquid }.map(\.symbol).sorted()
        #expect(liquids == ["Br", "Hg"])

        let gases = Set(catalog.elements.filter { $0.phase == .gas }.map(\.symbol))
        #expect(gases == ["H", "He", "N", "O", "F", "Ne", "Cl", "Ar", "Kr", "Xe", "Rn"])
    }

    @Test("Temperatures are in kelvin and ordered")
    func temperaturesArePlausible() {
        for element in catalog.elements {
            if let melting = element.meltingPointK {
                #expect(melting > 0, "\(element.name) melting point must be above absolute zero")
                #expect(melting < 4_500, "\(element.name) melting point \(melting) K looks wrong")
            }
            if let boiling = element.boilingPointK {
                #expect(boiling > 0, "\(element.name) boiling point must be above absolute zero")
                #expect(boiling < 6_500, "\(element.name) boiling point \(boiling) K looks wrong")
            }
            if let melting = element.meltingPointK, let boiling = element.boilingPointK {
                #expect(melting <= boiling,
                        "\(element.name) melts at \(melting) K but boils at \(boiling) K")
            }
        }
    }

    @Test("Standard atomic weights increase apart from the three classic inversions")
    func atomicMassesAreOrdered() {
        // Below bismuth every element has a IUPAC standard atomic weight, and
        // mass rises with atomic number except at Ar/K, Co/Ni and Te/I. Above
        // it, masses are mass numbers of the most stable isotope and legitimately
        // jump around, so ordering is not asserted there.
        let allowedInversions: Set<Int> = [18, 27, 52]
        let ordered = catalog.elements.filter { $0.atomicNumber <= 83 }
        for pair in zip(ordered, ordered.dropFirst()) {
            if allowedInversions.contains(pair.0.atomicNumber) { continue }
            #expect(pair.0.atomicMass < pair.1.atomicMass,
                    "\(pair.0.name) (\(pair.0.atomicMass)) should be lighter than \(pair.1.name) (\(pair.1.atomicMass))")
        }
        // ...and the three inversions really are inversions.
        for number in allowedInversions {
            guard let lighter = catalog.element(atomicNumber: number),
                  let heavier = catalog.element(atomicNumber: number + 1) else {
                Issue.record("Missing element around \(number)")
                continue
            }
            #expect(lighter.atomicMass > heavier.atomicMass,
                    "\(lighter.name) should outweigh \(heavier.name)")
        }
    }

    @Test("Atomic masses are at least the atomic number and never absurd")
    func atomicMassesArePlausible() {
        for element in catalog.elements {
            #expect(element.atomicMass >= Double(element.atomicNumber),
                    "\(element.name) mass \(element.atomicMass) is below its proton count")
            #expect(element.atomicMass <= Double(element.atomicNumber) * 3.1,
                    "\(element.name) mass \(element.atomicMass) is implausibly high")
        }
    }

    @Test("Elements without a stable isotope report a whole mass number")
    func massNumberFlagIsConsistent() {
        // Technetium and promethium have no stable isotope, and neither does
        // anything past polonium. Thorium, protactinium and uranium are the
        // exception: they are radioactive but do have IUPAC standard atomic
        // weights, so either representation is defensible there.
        let radiogenicButWeighted: Set<Int> = [90, 91, 92]
        for element in catalog.elements {
            let mustUseMassNumber = (element.atomicNumber >= 84 || [43, 61].contains(element.atomicNumber))
                && !radiogenicButWeighted.contains(element.atomicNumber)
            if mustUseMassNumber {
                #expect(element.atomicMassIsMassNumber,
                        "\(element.name) has no stable isotope and should use a mass number")
            }
            if element.atomicMassIsMassNumber {
                #expect(element.atomicMass == element.atomicMass.rounded(),
                        "\(element.name) mass number should be a whole number")
            } else {
                #expect(element.atomicNumber < 84 || radiogenicButWeighted.contains(element.atomicNumber),
                        "\(element.name) should not claim a standard atomic weight")
            }
        }
    }

    @Test("Electronegativity, when present, is on the Pauling scale")
    func electronegativityRange() {
        for element in catalog.elements {
            guard let value = element.electronegativity else { continue }
            #expect(value >= 0.7 && value <= 3.98,
                    "\(element.name) electronegativity \(value) is outside the Pauling scale")
        }
        #expect(TestCatalog.element("F").electronegativity == 3.98)
    }

    @Test("Densities are positive, in g/cm³, and within known extremes")
    func densityRange() {
        for element in catalog.elements {
            guard let density = element.densityGramsPerCm3 else { continue }
            #expect(density > 0, "\(element.name) has a non-positive density")
            #expect(density < 41, "\(element.name) density \(density) exceeds any known element")

            if element.phase == .gas {
                // Stored in g/cm³ throughout; the detail screen converts to g/L
                // for display. A value above 0.02 means someone stored g/L.
                #expect(density < 0.02,
                        "\(element.name) gas density \(density) looks like g/L, not g/cm³")
            } else if element.phase == .solid || element.phase == .liquid {
                #expect(density > 0.05,
                        "\(element.name) is condensed matter but has density \(density)")
            }
        }
        // Spot-check the extremes so a wholesale unit slip cannot pass.
        #expect((22.0...23.2).contains(TestCatalog.element("Os").densityGramsPerCm3 ?? 0))
        #expect((0.4...0.7).contains(TestCatalog.element("Li").densityGramsPerCm3 ?? 0))
    }

    @Test("Discovery years are historically plausible")
    func discoveryYears() {
        for element in catalog.elements {
            guard let year = element.discoveryYear else { continue }
            #expect(year >= 1250 && year <= 2025,
                    "\(element.name) discovery year \(year) is out of range")
        }
    }

    @Test("Every element ships complete editorial copy")
    func editorialCopyIsComplete() {
        for element in catalog.elements {
            #expect(!element.tagline.isEmpty, "\(element.name) has no tagline")
            #expect(element.tagline.count <= 72,
                    "\(element.name) tagline is \(element.tagline.count) characters")
            #expect(element.about.count >= 120,
                    "\(element.name) about text is too short (\(element.about.count))")
            #expect(element.about.count <= 460,
                    "\(element.name) about text is too long (\(element.about.count))")
            #expect(!element.memoryHook.isEmpty, "\(element.name) has no memory hook")
            #expect(element.memoryHook.count <= 190,
                    "\(element.name) memory hook is \(element.memoryHook.count) characters")
            #expect(!element.elementalForm.isEmpty, "\(element.name) has no elemental form")
            #expect(element.elementalForm.count <= 52,
                    "\(element.name) elemental form is \(element.elementalForm.count) characters")
        }
    }

    @Test("Copy avoids the planetary-orbit misconception and hype")
    func copyAvoidsScientificErrors() {
        let banned = ["orbits the nucleus", "orbit the nucleus", "did you know", "!"]
        for element in catalog.elements {
            let text = (element.about + " " + element.memoryHook + " " + element.tagline).lowercased()
            for phrase in banned {
                #expect(!text.contains(phrase),
                        "\(element.name) copy contains \u{201C}\(phrase)\u{201D}")
            }
        }
    }

    @Test("Each element has three to five uses with real SF Symbol names")
    func usesAreWellFormed() {
        for element in catalog.elements {
            #expect((3...5).contains(element.uses.count),
                    "\(element.name) has \(element.uses.count) uses")
            var titles = Set<String>()
            for use in element.uses {
                #expect(!use.title.isEmpty && use.title.count <= 20,
                        "\(element.name) use title \u{201C}\(use.title)\u{201D}")
                #expect(!use.detail.isEmpty && use.detail.count <= 30,
                        "\(element.name) use detail \u{201C}\(use.detail)\u{201D}")
                #expect(SFSymbolAllowlist.contains(use.symbolName),
                        "\(element.name) uses unknown SF Symbol \u{201C}\(use.symbolName)\u{201D}")
                #expect(!titles.contains(use.title),
                        "\(element.name) repeats the use \u{201C}\(use.title)\u{201D}")
                titles.insert(use.title)
            }
        }
    }

    @Test("Structure kinds are chemically appropriate")
    func structuresAreAppropriate() {
        let diatomic = Set(["H", "N", "O", "F", "Cl", "Br", "I"])
        let nobleGases = Set(catalog.elements(in: .nobleGas).map(\.symbol))

        for element in catalog.elements {
            if diatomic.contains(element.symbol) {
                #expect(element.structure == .diatomic,
                        "\(element.name) should be diatomic")
            }
            if nobleGases.contains(element.symbol), element.phase == .gas {
                #expect(element.structure == .monatomicGas,
                        "\(element.name) should be a monatomic gas")
            }
            if element.category.family == .metal, element.atomicNumber <= 103 {
                #expect(element.structure == .metallicLattice,
                        "\(element.name) is a metal and should form a metallic lattice")
            }
        }
    }
}
