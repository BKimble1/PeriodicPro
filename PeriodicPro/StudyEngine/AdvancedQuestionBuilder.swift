import Foundation

/// Builds advanced chemistry questions from data the app can cite.
///
/// Deterministic: the same seed and the same catalogs produce the same
/// questions in the same order, which is what makes the expected values in
/// `AdvancedChemistryTests` assertable rather than approximate.
///
/// Every value is computed. A molar mass is the sum of IUPAC 2021 weights; a
/// percent composition is that sum divided out; a particle count is moles
/// times the exact Avogadro constant; a valence count comes from the group;
/// an electron configuration is the one in `elements.json`. Where a fact
/// cannot be computed or cited it is not asked about — there is no question
/// here whose answer had to be invented to make the question work.
enum AdvancedQuestionBuilder {
    /// The main groups, where the number of valence electrons follows from
    /// the group and the ion's charge follows from that.
    ///
    /// Deliberately not the d block: a transition metal's valence count is
    /// genuinely ambiguous and its common ions do not follow from its group,
    /// so those are asked about only from the curated table below.
    static let mainGroups: Set<Int> = [1, 2, 13, 14, 15, 16, 17, 18]

    /// The common ionic charges every general-chemistry course teaches for
    /// the metals whose charges do not follow from a group.
    ///
    /// Curated rather than derived, and short on purpose: these are the ones
    /// that are universal across textbooks. Anything whose "common" oxidation
    /// state depends on which course you are taking is not in here.
    static let curatedOxidationStates: [String: [Int]] = [
        "Fe": [2, 3], "Cu": [1, 2], "Zn": [2], "Ag": [1], "Cr": [2, 3, 6],
        "Mn": [2, 4, 7], "Co": [2, 3], "Ni": [2], "Sn": [2, 4], "Pb": [2, 4],
        "Hg": [1, 2], "Au": [1, 3], "Pt": [2, 4], "Cd": [2], "Ti": [3, 4],
    ]

    // MARK: - Building a round

    /// A round of advanced questions, drawn across the kinds so a round is a
    /// mix rather than ten molar masses.
    static func round(
        count: Int,
        seed: UInt64,
        kinds: [AdvancedQuestion.Kind] = AdvancedQuestion.Kind.allCases,
        catalog: ElementCatalog,
        compounds: CompoundCatalog
    ) -> [AdvancedQuestion] {
        guard count > 0, !kinds.isEmpty else { return [] }
        var generator = SeededGenerator(seed: seed)
        var questions: [AdvancedQuestion] = []
        var used = Set<String>()
        var pool = kinds.shuffled(using: &generator)
        var index = 0
        var attempts = 0

        while questions.count < count, attempts < count * 12 {
            attempts += 1
            if pool.isEmpty { pool = kinds.shuffled(using: &generator) }
            let kind = pool.removeFirst()
            guard let question = make(
                kind, id: index, generator: &generator, catalog: catalog, compounds: compounds
            ) else { continue }
            let key = "\(kind.rawValue)|\(question.subject.key)"
            guard used.insert(key).inserted else { continue }
            questions.append(question)
            index += 1
        }
        return questions
    }

    // MARK: - One question

    static func make(
        _ kind: AdvancedQuestion.Kind,
        id: Int,
        generator: inout SeededGenerator,
        catalog: ElementCatalog,
        compounds: CompoundCatalog
    ) -> AdvancedQuestion? {
        switch kind {
        case .molarMass: return molarMass(id: id, generator: &generator, compounds: compounds, catalog: catalog)
        case .percentComposition:
            return percentComposition(id: id, generator: &generator, compounds: compounds, catalog: catalog)
        case .molesToParticles:
            return molesToParticles(id: id, generator: &generator, compounds: compounds)
        case .massToMoles: return massToMoles(id: id, generator: &generator, compounds: compounds, catalog: catalog)
        case .empiricalFormula:
            return empiricalFormula(id: id, generator: &generator, compounds: compounds, catalog: catalog)
        case .electronConfiguration:
            return electronConfiguration(id: id, generator: &generator, catalog: catalog)
        case .valenceElectrons: return valenceElectrons(id: id, generator: &generator, catalog: catalog)
        case .electronegativityComparison:
            return electronegativity(id: id, generator: &generator, catalog: catalog)
        case .sharedProperty: return sharedProperty(id: id, generator: &generator, catalog: catalog)
        case .ionicCharge: return ionicCharge(id: id, generator: &generator, catalog: catalog)
        case .oxidationState: return oxidationState(id: id, generator: &generator, catalog: catalog)
        case .formulaForName: return formulaForName(id: id, generator: &generator, compounds: compounds)
        }
    }

    // MARK: - Calculations

    static func molarMass(
        id: Int, generator: inout SeededGenerator, compounds: CompoundCatalog, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        guard let compound = pickCompound(&generator, from: compounds, maximumElements: 4),
              let mass = compound.molarMass else { return nil }
        return AdvancedQuestion(
            id: id, kind: .molarMass, subject: .compound(compound),
            prompt: "What is the molar mass of \(compound.displayFormula)?",
            answer: .numeric(value: mass, unit: "g/mol", tolerance: AdvancedAnswer.defaultTolerance),
            solution: massSteps(compound, catalog: catalog) + [
                SolutionStep(label: "Molar mass", expression: "\(AdvancedAnswer.format(mass)) g/mol"),
            ],
            sourceNote: ChemicalConstants.atomicWeightSource
        )
    }

    static func percentComposition(
        id: Int, generator: inout SeededGenerator, compounds: CompoundCatalog, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        guard let compound = pickCompound(&generator, from: compounds, maximumElements: 4),
              let total = compound.molarMass, total > 0 else { return nil }
        let composition = compound.composition
        guard let entry = composition.sorted(by: { $0.key < $1.key })
            .randomElement(using: &generator),
            let element = catalog.element(atomicNumber: entry.key) else { return nil }
        let count = entry.value
        let part = element.atomicMass * Double(count)
        let percent = part / total * 100
        return AdvancedQuestion(
            id: id, kind: .percentComposition, subject: .compound(compound),
            prompt: "What percent by mass of \(compound.displayFormula) is \(element.name.lowercased())?",
            answer: .numeric(value: percent, unit: "%", tolerance: AdvancedAnswer.defaultTolerance),
            solution: [
                SolutionStep(
                    label: "Mass of \(element.name.lowercased()) per mole",
                    expression: "\(count) × \(AdvancedAnswer.format(element.atomicMass)) "
                        + "= \(AdvancedAnswer.format(part)) g"
                ),
                SolutionStep(label: "Molar mass", expression: "\(AdvancedAnswer.format(total)) g/mol"),
                SolutionStep(
                    label: "Percent by mass",
                    expression: "\(AdvancedAnswer.format(part)) ÷ \(AdvancedAnswer.format(total)) × 100 "
                        + "= \(AdvancedAnswer.format(percent))%"
                ),
            ],
            sourceNote: ChemicalConstants.atomicWeightSource
        )
    }

    static func molesToParticles(
        id: Int, generator: inout SeededGenerator, compounds: CompoundCatalog
    ) -> AdvancedQuestion? {
        guard let compound = pickCompound(&generator, from: compounds, maximumElements: 4) else { return nil }
        let choices = [0.25, 0.5, 1.5, 2.0, 0.1, 3.0]
        guard let moles = choices.randomElement(using: &generator) else { return nil }
        let particles = moles * ChemicalConstants.avogadro
        let unit = compound.bondingClass == .ionic ? "formula units" : "molecules"
        return AdvancedQuestion(
            id: id, kind: .molesToParticles, subject: .compound(compound),
            prompt: "How many \(unit) are in \(AdvancedAnswer.format(moles)) mol of "
                + "\(compound.displayFormula)?",
            answer: .numeric(value: particles, unit: unit, tolerance: AdvancedAnswer.defaultTolerance),
            solution: [
                SolutionStep(label: "Avogadro constant",
                             expression: "6.02214076 × 10²³ per mole (exact, SI)"),
                SolutionStep(
                    label: "Multiply",
                    expression: "\(AdvancedAnswer.format(moles)) × 6.02214076 × 10²³ "
                        + "= \(AdvancedAnswer.format(particles))"
                ),
            ],
            sourceNote: "Avogadro constant, exact by the 2019 SI definition of the mole"
        )
    }

    static func massToMoles(
        id: Int, generator: inout SeededGenerator, compounds: CompoundCatalog, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        guard let compound = pickCompound(&generator, from: compounds, maximumElements: 4),
              let molar = compound.molarMass, molar > 0 else { return nil }
        let multipliers = [0.5, 1.0, 2.0, 0.25]
        guard let multiplier = multipliers.randomElement(using: &generator) else { return nil }
        let grams = (molar * multiplier * 10).rounded() / 10
        let moles = grams / molar
        return AdvancedQuestion(
            id: id, kind: .massToMoles, subject: .compound(compound),
            prompt: "How many moles are in \(AdvancedAnswer.format(grams)) g of \(compound.displayFormula)?",
            answer: .numeric(value: moles, unit: "mol", tolerance: AdvancedAnswer.defaultTolerance),
            solution: [
                SolutionStep(label: "Molar mass", expression: "\(AdvancedAnswer.format(molar)) g/mol"),
                SolutionStep(
                    label: "Divide the mass by the molar mass",
                    expression: "\(AdvancedAnswer.format(grams)) ÷ \(AdvancedAnswer.format(molar)) "
                        + "= \(AdvancedAnswer.format(moles)) mol"
                ),
            ],
            sourceNote: ChemicalConstants.atomicWeightSource
        )
    }

    static func empiricalFormula(
        id: Int, generator: inout SeededGenerator, compounds: CompoundCatalog, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        guard let compound = pickCompound(&generator, from: compounds, maximumElements: 3),
              let total = compound.molarMass, total > 0 else { return nil }
        let composition = compound.composition
        guard composition.count >= 2 else { return nil }
        let empirical = reduced(composition)
        let empiricalFormula = CompoundFormula.hill(empirical, catalog: catalog)

        let percentages = composition.sorted { $0.key < $1.key }.compactMap { number, count -> String? in
            guard let element = catalog.element(atomicNumber: number) else { return nil }
            let percent = element.atomicMass * Double(count) / total * 100
            return "\(AdvancedAnswer.format(percent))% \(element.name.lowercased())"
        }
        guard percentages.count == composition.count else { return nil }

        var options = [empiricalFormula]
        // Distractors are real alternative ratios of the same elements, not
        // formulas of something else: the question is about working the ratio
        // out, so the wrong answers have to be other ratios.
        for scale in [2, 3] {
            let scaled = empirical.mapValues { $0 * scale }
            let text = CompoundFormula.hill(scaled, catalog: catalog)
            if !options.contains(text) { options.append(text) }
        }
        if let first = empirical.keys.sorted().first {
            var shifted = empirical
            shifted[first, default: 1] += 1
            let text = CompoundFormula.hill(shifted, catalog: catalog)
            if !options.contains(text) { options.append(text) }
        }
        guard options.count >= 3 else { return nil }
        options.shuffle(using: &generator)
        guard let correct = options.firstIndex(of: empiricalFormula) else { return nil }

        return AdvancedQuestion(
            id: id, kind: .empiricalFormula, subject: .compound(compound),
            prompt: "A compound is \(percentages.joined(separator: ", ")) by mass. "
                + "What is its empirical formula?",
            answer: .choice(options: options, correctIndex: correct),
            solution: [
                SolutionStep(label: "Assume 100 g and divide each mass by its atomic weight",
                             expression: "that gives the mole ratio"),
                SolutionStep(label: "Divide through by the smallest",
                             expression: "whole-number ratio \(empiricalFormula)"),
                SolutionStep(label: "Empirical formula", expression: empiricalFormula),
            ],
            sourceNote: "\(ChemicalConstants.atomicWeightSource); composition of "
                + "\(compound.preferredName)"
        )
    }

    // MARK: - Structure and trends

    static func electronConfiguration(
        id: Int, generator: inout SeededGenerator, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        let pool = catalog.elements.filter { $0.atomicNumber <= 38 }
        guard let element = pool.randomElement(using: &generator) else { return nil }
        var options = [element.electronConfiguration]
        for neighbor in [element.atomicNumber - 1, element.atomicNumber + 1, element.atomicNumber + 2] {
            guard let other = catalog.element(atomicNumber: neighbor),
                  !options.contains(other.electronConfiguration) else { continue }
            options.append(other.electronConfiguration)
        }
        guard options.count >= 3 else { return nil }
        options.shuffle(using: &generator)
        guard let correct = options.firstIndex(of: element.electronConfiguration) else { return nil }
        return AdvancedQuestion(
            id: id, kind: .electronConfiguration, subject: .element(element),
            prompt: "Which electron configuration is correct for \(element.name) (\(element.symbol))?",
            answer: .choice(options: options, correctIndex: correct),
            solution: [
                SolutionStep(label: "\(element.name) has \(element.atomicNumber) electrons",
                             expression: element.electronConfiguration),
                SolutionStep(label: "Shells", expression: element.shellElectrons.map(String.init)
                    .joined(separator: ", ")),
            ],
            sourceNote: "Ground-state configurations in Elemora's element dataset"
        )
    }

    static func valenceElectrons(
        id: Int, generator: inout SeededGenerator, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        let pool = catalog.elements.filter { element in
            guard let group = element.group else { return false }
            return mainGroups.contains(group) && element.atomicNumber <= 54
        }
        guard let element = pool.randomElement(using: &generator),
              let group = element.group,
              let valence = valenceCount(group: group) else { return nil }
        return AdvancedQuestion(
            id: id, kind: .valenceElectrons, subject: .element(element),
            prompt: "How many valence electrons does \(element.name.lowercased()) have?",
            answer: .numeric(value: Double(valence), unit: "", tolerance: 0.001),
            solution: [
                SolutionStep(label: "\(element.name) is in group \(group)",
                             expression: group <= 2 ? "group \(group) → \(valence)"
                                : "group \(group) → \(group) − 10 = \(valence)"),
                SolutionStep(label: "Valence electrons", expression: "\(valence)"),
            ],
            sourceNote: "Main-group valence counts follow from the group number"
        )
    }

    /// Main-group only: groups 1 and 2 give their number, 13 to 18 give it
    /// less ten. The d block is deliberately excluded, because there the
    /// count is genuinely ambiguous.
    static func valenceCount(group: Int) -> Int? {
        switch group {
        case 1, 2: return group
        case 13...18: return group - 10
        default: return nil
        }
    }

    static func electronegativity(
        id: Int, generator: inout SeededGenerator, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        let pool = catalog.elements.filter { $0.electronegativity != nil && $0.atomicNumber <= 56 }
        guard pool.count >= 2, let first = pool.randomElement(using: &generator) else { return nil }
        let others = pool.filter {
            $0.atomicNumber != first.atomicNumber
                && abs(($0.electronegativity ?? 0) - (first.electronegativity ?? 0)) >= 0.3
        }
        guard let second = others.randomElement(using: &generator),
              let left = first.electronegativity, let right = second.electronegativity else { return nil }
        let winner = left > right ? first : second
        let options = [first.name, second.name].sorted()
        guard let correct = options.firstIndex(of: winner.name) else { return nil }
        return AdvancedQuestion(
            id: id, kind: .electronegativityComparison, subject: .element(winner),
            prompt: "Which has the greater electronegativity, \(options[0]) or \(options[1])?",
            answer: .choice(options: options, correctIndex: correct),
            solution: [
                SolutionStep(label: first.name, expression: "\(AdvancedAnswer.format(left)) (Pauling)"),
                SolutionStep(label: second.name, expression: "\(AdvancedAnswer.format(right)) (Pauling)"),
            ],
            sourceNote: "Pauling electronegativities in Elemora's element dataset"
        )
    }

    static func sharedProperty(
        id: Int, generator: inout SeededGenerator, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        let families: [ElementCategory] = [
            .alkaliMetal, .alkalineEarthMetal, .halogen, .nobleGas, .transitionMetal,
        ]
        guard let family = families.randomElement(using: &generator) else { return nil }
        let members = catalog.elements(in: family).filter { $0.atomicNumber <= 56 }
        guard members.count >= 3 else { return nil }
        let chosen = Array(members.shuffled(using: &generator).prefix(3))
        let names = chosen.map(\.name).sorted()

        var options = [family.displayName]
        for other in families where other != family && !options.contains(other.displayName) {
            options.append(other.displayName)
        }
        options = Array(options.prefix(4)).shuffled(using: &generator)
        guard let correct = options.firstIndex(of: family.displayName) else { return nil }
        return AdvancedQuestion(
            id: id, kind: .sharedProperty, subject: .element(chosen[0]),
            prompt: "\(names.joined(separator: ", ")) — what do these elements have in common?",
            answer: .choice(options: options, correctIndex: correct),
            solution: chosen.map {
                SolutionStep(label: $0.name, expression: "\($0.category.displayName), period \($0.period)")
            },
            sourceNote: "Family classifications in Elemora's element dataset"
        )
    }

    static func ionicCharge(
        id: Int, generator: inout SeededGenerator, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        // Only where the charge follows from the group: the alkali and
        // alkaline earth metals, and the p-block nonmetals that take
        // electrons. Nothing here is a guess about a transition metal.
        let pool = catalog.elements.filter { element in
            guard let group = element.group, element.atomicNumber <= 56 else { return false }
            return [1, 2, 13, 15, 16, 17].contains(group) && element.atomicNumber > 2
        }
        guard let element = pool.randomElement(using: &generator),
              let group = element.group,
              let charge = commonIonCharge(group: group) else { return nil }
        let text = charge > 0 ? "+\(charge)" : "\(charge)"
        var options = [text]
        for other in [1, 2, 3, -1, -2, -3] where options.count < 4 {
            let candidate = other > 0 ? "+\(other)" : "\(other)"
            if !options.contains(candidate) { options.append(candidate) }
        }
        options.shuffle(using: &generator)
        guard let correct = options.firstIndex(of: text) else { return nil }
        return AdvancedQuestion(
            id: id, kind: .ionicCharge, subject: .element(element),
            prompt: "What charge does a \(element.name.lowercased()) ion usually carry?",
            answer: .choice(options: options, correctIndex: correct),
            solution: [
                SolutionStep(label: "\(element.name) is in group \(group)",
                             expression: charge > 0
                                ? "loses \(charge) electron\(charge == 1 ? "" : "s") to reach a full shell"
                                : "gains \(-charge) electron\(charge == -1 ? "" : "s") to reach a full shell"),
                SolutionStep(label: "Ion", expression: "\(element.symbol)\(text)"),
            ],
            sourceNote: "Main-group ion charges follow from the group number"
        )
    }

    /// The charge a main-group ion carries, where the group decides it.
    static func commonIonCharge(group: Int) -> Int? {
        switch group {
        case 1: return 1
        case 2: return 2
        case 13: return 3
        case 15: return -3
        case 16: return -2
        case 17: return -1
        default: return nil
        }
    }

    static func oxidationState(
        id: Int, generator: inout SeededGenerator, catalog: ElementCatalog
    ) -> AdvancedQuestion? {
        let symbols = curatedOxidationStates.keys.sorted()
        guard let symbol = symbols.randomElement(using: &generator),
              let element = catalog.element(symbol: symbol),
              let states = curatedOxidationStates[symbol],
              let state = states.randomElement(using: &generator) else { return nil }
        let text = "+\(state)"
        var options = [text]
        for other in [1, 2, 3, 4, 6, 7] where options.count < 4 {
            let candidate = "+\(other)"
            if !options.contains(candidate), !states.contains(other) { options.append(candidate) }
        }
        options.shuffle(using: &generator)
        guard let correct = options.firstIndex(of: text) else { return nil }
        let all = states.map { "+\($0)" }.joined(separator: " and ")
        return AdvancedQuestion(
            id: id, kind: .oxidationState, subject: .element(element),
            prompt: "Which of these is a common oxidation state of \(element.name.lowercased())?",
            answer: .choice(options: options, correctIndex: correct),
            solution: [
                SolutionStep(label: "\(element.name) commonly shows", expression: all),
                SolutionStep(label: "Why several",
                             expression: "a d-block metal's outer d and s electrons are close in "
                                + "energy, so more than one is available"),
            ],
            sourceNote: "Curated common oxidation states; see DATA_SOURCES.md"
        )
    }

    static func formulaForName(
        id: Int, generator: inout SeededGenerator, compounds: CompoundCatalog
    ) -> AdvancedQuestion? {
        let pool = compounds.compounds.filter { !$0.isHypothetical && $0.formula.count <= 12 }
        guard pool.count >= 4, let compound = pool.randomElement(using: &generator) else { return nil }
        var options = [compound.formula]
        for other in pool.shuffled(using: &generator) where options.count < 4 {
            if !options.contains(other.formula) { options.append(other.formula) }
        }
        let displayed = options.map(CompoundFormula.subscripted).shuffled(using: &generator)
        guard let correct = displayed.firstIndex(of: compound.displayFormula) else { return nil }
        return AdvancedQuestion(
            id: id, kind: .formulaForName, subject: .compound(compound),
            prompt: "What is the formula for \(compound.preferredName.lowercased())?",
            answer: .choice(options: displayed, correctIndex: correct),
            solution: [
                SolutionStep(label: compound.preferredName, expression: compound.displayFormula),
                SolutionStep(label: "Molar mass",
                             expression: compound.molarMassDisplay ?? "not available"),
            ],
            sourceNote: "Elemora's curated compound catalog"
        )
    }

    // MARK: - Helpers

    private static func pickCompound(
        _ generator: inout SeededGenerator, from compounds: CompoundCatalog, maximumElements: Int
    ) -> ChemicalCompound? {
        let pool = compounds.compounds.filter {
            !$0.isHypothetical && $0.molarMass != nil
                && (1...maximumElements).contains($0.composition.count)
        }
        return pool.randomElement(using: &generator)
    }

    private static func massSteps(
        _ compound: ChemicalCompound, catalog: ElementCatalog
    ) -> [SolutionStep] {
        let parts = compound.composition.sorted { $0.key < $1.key }.compactMap { number, count -> String? in
            guard let element = catalog.element(atomicNumber: number) else { return nil }
            let weight = AdvancedAnswer.format(element.atomicMass)
            return count > 1 ? "\(count)(\(weight))" : weight
        }
        return [SolutionStep(label: "Add the atomic weights", expression: parts.joined(separator: " + "))]
    }

    /// The composition divided through by the greatest common divisor of its
    /// counts — which is what an empirical formula is.
    static func reduced(_ composition: [Int: Int]) -> [Int: Int] {
        let counts = composition.values.filter { $0 > 0 }
        guard let first = counts.first else { return composition }
        let divisor = counts.dropFirst().reduce(first) { greatestCommonDivisor($0, $1) }
        guard divisor > 1 else { return composition }
        return composition.mapValues { $0 / divisor }
    }

    static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = abs(lhs)
        var b = abs(rhs)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}
