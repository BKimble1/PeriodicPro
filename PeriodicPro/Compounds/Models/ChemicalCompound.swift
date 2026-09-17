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

/// Where the coordinates in a structure came from, separately in each
/// dimension.
///
/// The 2D drawing and the 3D scene are built from the same atoms and bonds —
/// that is what makes it impossible for them to disagree about connectivity —
/// but their *coordinates* can have different provenance, and a learner is
/// owed the difference. PubChem's own 2D layout is a depiction a chemist drew
/// the rules for; a 2D layout projected from a 3D conformer is the same
/// molecule seen flat, which is honest but is not a skeletal formula anyone
/// published.
enum CompoundCoordinateSource: String, Codable, Hashable, Sendable {
    /// PubChem's standardized 2D depiction coordinates.
    case pubChemDepiction2D
    /// PubChem's computed 3D conformer.
    case pubChemConformer3D
    /// The bundled catalog's own computed conformer.
    case computedConformer
    /// A generated unit cell from tabulated lattice parameters.
    case curatedLattice
    /// Laid out by the app from the real connectivity graph, because
    /// coordinates were not available. The molecule is the record's; the
    /// arrangement on the page is not.
    case generatedFromConnectivity

    var displayName: String {
        switch self {
        case .pubChemDepiction2D: return "PubChem 2D depiction"
        case .pubChemConformer3D: return "PubChem 3D conformer"
        case .computedConformer: return "Computed conformer"
        case .curatedLattice: return "Representative unit cell"
        case .generatedFromConnectivity: return "Layout generated from the published connectivity"
        }
    }
}

/// What a structure record is, where it came from and when.
///
/// Carried so the interface never has to infer it. A compound with no 3D
/// source says "3D conformer not available" rather than showing a flattened
/// molecule and calling it a geometry.
struct CompoundStructureProvenance: Codable, Hashable, Sendable {
    /// The PubChem record this came from, when it came from one.
    var pubChemCID: Int?
    /// PubChem's own record type — "2d" or "3d" — as requested.
    var recordType: String?
    var twoDSource: CompoundCoordinateSource?
    var threeDSource: CompoundCoordinateSource?
    /// ISO 8601 date, as a string so the record round-trips unchanged.
    var retrieved: String?

    /// Whether a real three-dimensional geometry exists for this compound.
    var hasThreeDCoordinates: Bool { threeDSource != nil }
}

/// Atoms, bonds and coordinates, with a source that says what they are.
struct CompoundStructure: Codable, Hashable, Sendable {
    let is3D: Bool
    let source: CompoundStructureSource
    let note: String?
    let atoms: [CompoundAtom]
    let bonds: [CompoundBond]
    /// Where these coordinates came from, in each dimension, and when.
    ///
    /// Optional so that a record written by an earlier build decodes
    /// unchanged; `resolvedProvenance` fills in what can be derived from
    /// `source` when it is absent, so nothing in the interface has to handle
    /// the nil case.
    var provenance: CompoundStructureProvenance?

    init(
        is3D: Bool,
        source: CompoundStructureSource,
        note: String?,
        atoms: [CompoundAtom],
        bonds: [CompoundBond],
        provenance: CompoundStructureProvenance? = nil
    ) {
        self.is3D = is3D
        self.source = source
        self.note = note
        self.atoms = atoms
        self.bonds = bonds
        self.provenance = provenance
    }

    /// Atomic number → count, from the atoms actually present.
    var composition: [Int: Int] {
        var counts: [Int: Int] = [:]
        for atom in atoms { counts[atom.atomicNumber, default: 0] += 1 }
        return counts
    }

    /// The provenance, derived from `source` when the record predates it.
    var resolvedProvenance: CompoundStructureProvenance {
        if let provenance { return provenance }
        switch source {
        case .pubChem3D:
            return CompoundStructureProvenance(
                recordType: "3d",
                twoDSource: .generatedFromConnectivity,
                threeDSource: .pubChemConformer3D
            )
        case .pubChem2D:
            return CompoundStructureProvenance(
                recordType: "2d", twoDSource: .pubChemDepiction2D, threeDSource: nil
            )
        case .computedConformer:
            return CompoundStructureProvenance(
                twoDSource: .generatedFromConnectivity, threeDSource: .computedConformer
            )
        case .curatedLattice:
            return CompoundStructureProvenance(
                twoDSource: .generatedFromConnectivity, threeDSource: .curatedLattice
            )
        }
    }

    /// Whether a real three-dimensional geometry exists.
    ///
    /// When this is false the 3D view says so and keeps the accurate 2D
    /// structure, rather than giving the flat graph a z of zero and
    /// presenting the result as a conformer.
    var hasThreeDGeometry: Bool {
        guard is3D else { return false }
        // Three points always define a plane, so a record of three atoms or
        // fewer cannot be judged by its depth at all: water is bent, carbon
        // dioxide is linear, and both have real bond angles and no z. Past
        // three atoms, a conformer with every atom at z = 0 is a flat
        // depiction wearing a 3D label, which is the thing worth catching.
        if atoms.count <= 3 { return true }
        return atoms.contains { $0.z != 0 }
    }

    /// How many atoms are worth drawing one at a time.
    ///
    /// A composition may name thousands of atoms; a RealityKit scene made of
    /// thousands of entities is a slideshow. Past this the viewer says the
    /// molecule is too large to draw atom by atom rather than trying and
    /// failing — which is a limit of the renderer and is described as one,
    /// not as a limit of the chemistry.
    static let renderableAtomLimit = 600

    var isRenderable: Bool { !atoms.isEmpty && atoms.count <= Self.renderableAtomLimit }
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

    /// Atomic number → count, per formula unit.
    ///
    /// From the molecular structure when there is one, so the count can never
    /// disagree with the picture; from the formula for a lattice, whose cell
    /// holds several formula units, and for a record with no structure.
    var composition: [Int: Int] {
        if let structure, !structure.atoms.isEmpty, structure.source != .curatedLattice {
            return structure.composition
        }
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
