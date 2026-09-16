import Foundation

/// Where a compound record came from.
enum CompoundDataSource: String, Codable, Hashable, Sendable {
    /// Bundled in `compounds.json`, verified and sourced.
    case curated
    /// Fetched from PubChem at the learner's request and cached.
    case pubChem
    /// A composition the learner built that matched nothing. Never given a
    /// name, a structure or any property beyond its formula.
    case hypothetical

    var displayName: String {
        switch self {
        case .curated: return "Elemora catalog"
        case .pubChem: return "PubChem"
        case .hypothetical: return "Hypothetical composition"
        }
    }
}

/// Where a compound's atoms, bonds and coordinates came from — which decides
/// how honestly the app can label the picture.
enum CompoundStructureSource: String, Codable, Hashable, Sendable {
    /// A PubChem 3D conformer: real connectivity, computed coordinates.
    case pubChem3D
    /// PubChem's 2D record: real connectivity, no depth.
    case pubChem2D
    /// The bundled catalog's computed conformer (RDKit, MMFF94).
    case computedConformer
    /// A generated unit cell from tabulated lattice parameters.
    case curatedLattice

    var displayName: String {
        switch self {
        case .pubChem3D: return "PubChem 3D conformer"
        case .pubChem2D: return "2D structure"
        case .computedConformer: return "Computed conformer"
        case .curatedLattice: return "Representative unit cell"
        }
    }

    /// The honesty label on the structure viewer.
    var representationLabel: String {
        switch self {
        case .pubChem3D, .computedConformer: return "Representative molecular structure"
        case .pubChem2D: return "2D structure"
        case .curatedLattice: return "Representative crystal unit cell"
        }
    }
}

/// The primary structural classification, applied only where the constituents
/// make it clear.
enum CompoundBondingClass: String, Codable, CaseIterable, Hashable, Sendable {
    case molecular
    case ionic
    case networkSolid
    case coordination
    case unknown

    var displayName: String {
        switch self {
        case .molecular: return "Molecular (covalent)"
        case .ionic: return "Ionic"
        case .networkSolid: return "Network solid"
        case .coordination: return "Coordination complex"
        case .unknown: return "Not classified"
        }
    }
}

/// Secondary labels. Shown only when the record's classification source backs
/// them — a compound is never called an acid because it contains hydrogen.
enum CompoundTag: String, Codable, CaseIterable, Hashable, Sendable {
    case acid
    case base
    case salt
    case organic
    case inorganic

    var displayName: String {
        switch self {
        case .acid: return "Acid"
        case .base: return "Base"
        case .salt: return "Salt"
        case .organic: return "Organic"
        case .inorganic: return "Inorganic"
        }
    }
}

/// One atom of a compound's structure, in ångströms.
struct CompoundAtom: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let atomicNumber: Int
    let x: Double
    let y: Double
    let z: Double
    let formalCharge: Int
}

/// One bond, or — in a lattice — one ionic contact.
struct CompoundBond: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let from: Int
    let to: Int
    /// 1, 2 or 3. PubChem's rarer values (dative, complex) are read as 1.
    let order: Int
    /// A nearest-neighbor contact in an ionic lattice rather than a covalent
    /// bond. Drawn thinner and never called a bond.
    let isContact: Bool
}

/// Atoms, bonds and coordinates, with a source that says what they are.
struct CompoundStructure: Codable, Hashable, Sendable {
    let is3D: Bool
    let source: CompoundStructureSource
    let note: String?
    let atoms: [CompoundAtom]
    let bonds: [CompoundBond]

    /// Atomic number → count, from the atoms actually present.
    var composition: [Int: Int] {
        var counts: [Int: Int] = [:]
        for atom in atoms { counts[atom.atomicNumber, default: 0] += 1 }
        return counts
    }
}

/// A chemical compound as the app understands it.
///
/// Deliberately a domain type: PubChem's JSON is decoded into DTOs in
/// `PubChemDTO.swift` and converted into this, so nothing in the interface
/// ever reads a raw network record.
struct ChemicalCompound: Codable, Hashable, Identifiable, Sendable {
    /// Stable local identifier: `pubchem-<cid>` for anything PubChem knows,
    /// `hypothetical-<uuid>` for a saved composition with no match.
    let id: String
    let pubChemCID: Int?
    let preferredName: String
    /// The conventional formula as chemists write it: NaCl, H₂O.
    let formula: String
    /// The Hill-order formula PubChem indexes: ClNa, H2O.
    let hillFormula: String
    let iupacName: String?
    /// Grams per mole. `nil` only for a hypothetical composition whose
    /// elements the app does not know.
    let molarMass: Double?
    let canonicalSMILES: String?
    let charge: Int
    let bondingClass: CompoundBondingClass
    let tags: [CompoundTag]
    let alternateNames: [String]
    /// One curated sentence. Never copied from a third-party description.
    let summary: String?
    let classificationSource: String?
    let dataSource: CompoundDataSource
    let isLocalCurated: Bool
    /// ISO 8601 date, as a string so the record round-trips through any
    /// JSON encoder unchanged.
    let lastUpdated: String?
    let structure: CompoundStructure?

    // MARK: - Derived

    /// The formula with real subscripts: C₂H₆O.
    var displayFormula: String { CompoundFormula.subscripted(formula) }

    /// Atomic number → count. From the structure when there is one, so the
    /// count can never disagree with the picture; from the formula otherwise.
    var composition: [Int: Int] {
        if let structure, !structure.atoms.isEmpty { return structure.composition }
        return CompoundFormula.parse(hillFormula) ?? [:]
    }

    var hasStructure: Bool { !(structure?.atoms.isEmpty ?? true) }

    var isHypothetical: Bool { dataSource == .hypothetical }

    /// "Data source: PubChem" — the attribution line on the detail page.
    var attribution: String {
        switch dataSource {
        case .curated: return "Data: Elemora catalog, PubChem CID \(pubChemCID.map(String.init) ?? "—")"
        case .pubChem: return "Data source: PubChem, CID \(pubChemCID.map(String.init) ?? "—")"
        case .hypothetical: return "No database match. Saved as a hypothetical composition."
        }
    }

    var molarMassDisplay: String? {
        guard let molarMass else { return nil }
        let rounded = (molarMass * 100).rounded() / 100
        return "\(rounded) g/mol"
    }

    /// Spoken description for VoiceOver.
    var accessibilityDescription: String {
        var parts = ["\(preferredName), formula \(CompoundFormula.spoken(formula))"]
        if bondingClass != .unknown { parts.append(bondingClass.displayName) }
        if let molarMassDisplay { parts.append("molar mass \(molarMassDisplay)") }
        return parts.joined(separator: ", ")
    }

    /// A hypothetical composition: only what the learner typed, nothing invented.
    static func hypothetical(composition: [Int: Int], catalog: ElementCatalog) -> ChemicalCompound {
        let formula = CompoundFormula.display(composition, catalog: catalog)
        return ChemicalCompound(
            id: "hypothetical-\(UUID().uuidString.lowercased())",
            pubChemCID: nil,
            preferredName: CompoundFormula.subscripted(formula),
            formula: formula,
            hillFormula: CompoundFormula.hill(composition, catalog: catalog),
            iupacName: nil,
            molarMass: CompoundFormula.molarMass(composition, catalog: catalog),
            canonicalSMILES: nil,
            charge: 0,
            bondingClass: .unknown,
            tags: [],
            alternateNames: [],
            summary: nil,
            classificationSource: nil,
            dataSource: .hypothetical,
            isLocalCurated: false,
            lastUpdated: CompoundFormula.today(),
            structure: nil
        )
    }
}
