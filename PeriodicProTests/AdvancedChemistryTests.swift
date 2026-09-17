import Foundation
import Testing
@testable import PeriodicPro

/// Golden values for the calculation questions.
///
/// Every number here was worked out by hand from the IUPAC 2021 weights the
/// app ships and the exact SI Avogadro constant, so a change to either shows
/// up as a failing test rather than as a wrong answer in a learner's round.
/// Nothing compares floating-point values for exact equality.
@Suite("Advanced chemistry arithmetic")
struct AdvancedChemistryTests {
    private let elements = TestCatalog.shared
    private let compounds = TestCompounds.catalog

    private func mass(_ formula: String) -> Double {
        guard let composition = CompoundFormula.parse(formula, catalog: elements),
              let mass = CompoundFormula.molarMass(composition, catalog: elements) else { return .nan }
        return mass
    }

    @Test("Molar masses match the hand-worked values")
    func molarMasses() {
        // 2(1.008) + 15.999
        #expect(abs(mass("H2O") - 18.015) < 0.01)
        // 12.011 + 2(15.999)
        #expect(abs(mass("CO2") - 44.009) < 0.01)
        // 2(1.008) + 32.06 + 4(15.999)
        #expect(abs(mass("H2SO4") - 98.072) < 0.02)
        // 22.99 + 35.45
        #expect(abs(mass("NaCl") - 58.44) < 0.02)
        // 6(12.011) + 12(1.008) + 6(15.999)
        #expect(abs(mass("C6H12O6") - 180.156) < 0.02)
        // 9(12.011) + 8(1.008) + 4(15.999)
        #expect(abs(mass("C9H8O4") - 180.159) < 0.02)
        // 8(12.011) + 10(1.008) + 4(14.007) + 2(15.999)
        #expect(abs(mass("C8H10N4O2") - 194.194) < 0.03)
        // 27(12.011) + 46(1.008) + 15.999
        #expect(abs(mass("C27H46O") - 386.664) < 0.05)
    }

    @Test("Percent composition")
    func percentComposition() {
        // Oxygen in water: 15.999 / 18.015 = 88.81%
        let oxygenInWater = 15.999 / mass("H2O") * 100
        #expect(abs(oxygenInWater - 88.81) < 0.1)
        // Carbon in carbon dioxide: 12.011 / 44.009 = 27.29%
        let carbonInCO2 = 12.011 / mass("CO2") * 100
        #expect(abs(carbonInCO2 - 27.29) < 0.1)
        // And the percentages of a compound add to a hundred.
        guard let glucose = CompoundFormula.parse("C6H12O6", catalog: elements) else {
            Issue.record("C6H12O6 should parse")
            return
        }
        let total = mass("C6H12O6")
        let sum = glucose.reduce(0.0) { running, entry in
            guard let element = elements.element(atomicNumber: entry.key) else { return running }
            return running + element.atomicMass * Double(entry.value) / total * 100
        }
        #expect(abs(sum - 100) < 0.001)
    }

    @Test("Moles, particles and the exact Avogadro constant")
    func molesAndParticles() {
        #expect(ChemicalConstants.avogadro == 6.022_140_76e23,
                "the Avogadro constant is exact by the 2019 SI definition, not a rounded value")
        let quarterMole = 0.25 * ChemicalConstants.avogadro
        #expect(abs(quarterMole - 1.5055e23) / 1.5055e23 < 0.001)
        // 18.0 g of water is very nearly one mole.
        let moles = 18.0 / mass("H2O")
        #expect(abs(moles - 0.99917) < 0.001)
    }

    @Test("Answers are graded on a tolerance, not on decimal places")
    func numericGrading() {
        let answer = AdvancedAnswer.numeric(value: 98.072, unit: "g/mol", tolerance: 0.01)
        #expect(answer.accepts("98.072"))
        #expect(answer.accepts("98.08"), "rounding the weights on the way is not an error")
        #expect(answer.accepts("98"))
        #expect(answer.accepts("98.1"))
        #expect(!answer.accepts("100"), "a wrong method is still wrong")
        #expect(!answer.accepts("18.02"))
        #expect(!answer.accepts(""))
        #expect(!answer.accepts("ninety-eight"))
    }

    @Test("A power of ten can be written any of the ways people write it")
    func scientificNotation() {
        let answer = AdvancedAnswer.numeric(value: 1.5055e23, unit: "molecules", tolerance: 0.01)
        #expect(answer.accepts("1.5055e23"))
        #expect(answer.accepts("1.5055E23"))
        #expect(answer.accepts("1.51e23"))
        #expect(answer.accepts("1.5055 x 10^23"))
        #expect(answer.accepts("1.5055 × 10^23"))
        #expect(!answer.accepts("1.5055e22"))
        #expect(AdvancedAnswer.parse("not a number") == nil)
        #expect(AdvancedAnswer.parse(String(repeating: "9", count: 80)) == nil)
    }

    @Test("Valence counts and ion charges follow the group, and only where they do")
    func mainGroupRules() {
        #expect(AdvancedQuestionBuilder.valenceCount(group: 1) == 1)
        #expect(AdvancedQuestionBuilder.valenceCount(group: 2) == 2)
        #expect(AdvancedQuestionBuilder.valenceCount(group: 17) == 7)
        #expect(AdvancedQuestionBuilder.valenceCount(group: 18) == 8)
        // Chlorine, the example in the brief: seven.
        #expect(AdvancedQuestionBuilder.valenceCount(group: TestCatalog.element("Cl").group ?? 0) == 7)
        // The d block is not asked about, because the answer is ambiguous.
        for group in 3...12 {
            #expect(AdvancedQuestionBuilder.valenceCount(group: group) == nil,
                    "group \(group) has no unambiguous valence count")
            #expect(AdvancedQuestionBuilder.commonIonCharge(group: group) == nil)
        }
        #expect(AdvancedQuestionBuilder.commonIonCharge(group: 1) == 1)
        #expect(AdvancedQuestionBuilder.commonIonCharge(group: 2) == 2)
        #expect(AdvancedQuestionBuilder.commonIonCharge(group: 16) == -2)
        #expect(AdvancedQuestionBuilder.commonIonCharge(group: 17) == -1)
        // Group 14 takes neither reliably, so it is not offered.
        #expect(AdvancedQuestionBuilder.commonIonCharge(group: 14) == nil)
    }

    @Test("Empirical formulas are the composition divided through")
    func empiricalReduction() {
        // Glucose C6H12O6 reduces to CH2O.
        #expect(AdvancedQuestionBuilder.reduced([6: 6, 1: 12, 8: 6]) == [6: 1, 1: 2, 8: 1])
        // Benzene C6H6 reduces to CH.
        #expect(AdvancedQuestionBuilder.reduced([6: 6, 1: 6]) == [6: 1, 1: 1])
        // Water is already reduced.
        #expect(AdvancedQuestionBuilder.reduced([1: 2, 8: 1]) == [1: 2, 8: 1])
        #expect(AdvancedQuestionBuilder.greatestCommonDivisor(12, 18) == 6)
        #expect(AdvancedQuestionBuilder.greatestCommonDivisor(7, 1) == 1)
    }

    @Test("A round is deterministic, mixed, and never repeats a question")
    func roundGeneration() {
        let first = AdvancedQuestionBuilder.round(
            count: 8, seed: 12_345, catalog: elements, compounds: compounds
        )
        let again = AdvancedQuestionBuilder.round(
            count: 8, seed: 12_345, catalog: elements, compounds: compounds
        )
        #expect(first.count == 8)
        #expect(first.map(\.prompt) == again.map(\.prompt), "the same seed must deal the same round")

        let different = AdvancedQuestionBuilder.round(
            count: 8, seed: 999, catalog: elements, compounds: compounds
        )
        #expect(different.map(\.prompt) != first.map(\.prompt), "a different seed must deal a different round")

        // A mix, not eight molar masses.
        #expect(Set(first.map(\.kind)).count >= 4)
        // And no question twice.
        let keys = first.map { "\($0.kind.rawValue)|\($0.subject.key)" }
        #expect(Set(keys).count == keys.count)
    }

    @Test("Every question a round deals is answerable and shows its working")
    func everyQuestionIsWellFormed() {
        for seed in [UInt64(1), 7, 42, 1_000, 987_654] {
            let round = AdvancedQuestionBuilder.round(
                count: 12, seed: seed, catalog: elements, compounds: compounds
            )
            #expect(!round.isEmpty, "seed \(seed) dealt nothing")
            for question in round {
                #expect(!question.prompt.isEmpty)
                #expect(!question.solution.isEmpty, "\(question.kind) shows no working")
                #expect(!question.sourceNote.isEmpty, "\(question.kind) does not say where its numbers came from")
                switch question.answer {
                case .choice(let options, let index):
                    // Two for a comparison — "which of these two" — and at
                    // least three for anything that is a pick from a field.
                    let minimum = question.kind == .electronegativityComparison ? 2 : 3
                    #expect(options.count >= minimum,
                            "\(question.kind) offers only \(options.count) options")
                    #expect(options.indices.contains(index))
                    #expect(Set(options).count == options.count, "\(question.kind) repeats an option")
                    #expect(question.answer.accepts(options[index]))
                    for (offset, option) in options.enumerated() where offset != index {
                        #expect(!question.answer.accepts(index: offset),
                                "\(question.kind) accepts the wrong option \(option)")
                    }
                case .numeric(let value, _, let tolerance):
                    #expect(value.isFinite)
                    #expect(tolerance > 0)
                    #expect(question.answer.accepts(AdvancedAnswer.format(value)),
                            "\(question.kind) does not accept its own answer, \(value)")
                }
            }
        }
    }

    @Test("The worked solution agrees with the answer")
    func solutionsAgreeWithAnswers() {
        var generator = SeededGenerator(seed: 4_242)
        for _ in 0..<40 {
            guard let question = AdvancedQuestionBuilder.molarMass(
                id: 0, generator: &generator, compounds: compounds, catalog: elements
            ) else { continue }
            guard case .numeric(let value, let unit, _) = question.answer else {
                Issue.record("a molar mass question should be typed, not picked")
                continue
            }
            #expect(unit == "g/mol")
            // The last step of the working is the answer.
            let last = question.solution.last?.expression ?? ""
            #expect(last.contains(AdvancedAnswer.format(value)),
                    "the working ends with \(last) but the answer is \(value)")
            // And the compound's own molar mass is what was asked about.
            #expect(abs((question.subject.compound?.molarMass ?? 0) - value) < 0.001)
        }
    }

    @Test("Curated oxidation states are curated, not derived")
    func oxidationStatesAreCurated() {
        // Every symbol in the table is a real element, and every state is one
        // a general-chemistry course teaches.
        for (symbol, states) in AdvancedQuestionBuilder.curatedOxidationStates {
            #expect(TestCatalog.shared.element(symbol: symbol) != nil, "\(symbol) is not an element")
            #expect(!states.isEmpty)
            #expect(states.allSatisfy { $0 >= 1 && $0 <= 8 })
        }
        #expect(AdvancedQuestionBuilder.curatedOxidationStates["Fe"] == [2, 3])
        #expect(AdvancedQuestionBuilder.curatedOxidationStates["Cu"] == [1, 2])
        // Nothing in the main group is in here: those follow from the group.
        #expect(AdvancedQuestionBuilder.curatedOxidationStates["Na"] == nil)
        #expect(AdvancedQuestionBuilder.curatedOxidationStates["Cl"] == nil)
    }

    @Test("Advanced is a mode of its own and is not behind Pro")
    func modeShape() {
        #expect(StudyMode.allCases.contains(.advanced))
        #expect(!StudyMode.advanced.requiresPro)
        #expect(!StudyMode.advanced.opensSetup)
        #expect(StudyMode.advanced.isAdvanced)
        #expect(StudyMode.advanced.fullTitle == "Advanced Chemistry")
        // Every mode's salt is distinct, so two modes never deal the same
        // material in the same order on the same day.
        #expect(Set(StudyMode.allCases.map(\.seedSalt)).count == StudyMode.allCases.count)
    }
}
