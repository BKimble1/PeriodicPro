import Foundation

/// The wire shapes of PubChem's PUG REST JSON, and nothing else.
///
/// These decode the service's envelopes verbatim and are converted to the
/// app's own types in `PubChemClient`. No view reads one of these.

/// `/compound/<domain>/<id>/property/<list>/JSON`
struct PubChemPropertyTableDTO: Decodable, Sendable {
    let propertyTable: Table

    struct Table: Decodable, Sendable {
        let properties: [PubChemPropertiesDTO]

        enum CodingKeys: String, CodingKey {
            case properties = "Properties"
        }
    }

    enum CodingKeys: String, CodingKey {
        case propertyTable = "PropertyTable"
    }
}

/// One row of a property table. Every field but the CID is optional, because
/// PubChem omits a property it does not have rather than sending null.
struct PubChemPropertiesDTO: Decodable, Sendable {
    let cid: Int
    let molecularFormula: String?
    /// PUG REST serializes the weight as a string; older captures used a
    /// number. Both are accepted.
    let molecularWeight: Double?
    let iupacName: String?
    let title: String?
    let charge: Int?

    enum CodingKeys: String, CodingKey {
        case cid = "CID"
        case molecularFormula = "MolecularFormula"
        case molecularWeight = "MolecularWeight"
        case iupacName = "IUPACName"
        case title = "Title"
        case charge = "Charge"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cid = try container.decode(Int.self, forKey: .cid)
        molecularFormula = try container.decodeIfPresent(String.self, forKey: .molecularFormula)
        if let text = try? container.decodeIfPresent(String.self, forKey: .molecularWeight) {
            molecularWeight = Double(text)
        } else {
            molecularWeight = try container.decodeIfPresent(Double.self, forKey: .molecularWeight)
        }
        iupacName = try container.decodeIfPresent(String.self, forKey: .iupacName)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        charge = try container.decodeIfPresent(Int.self, forKey: .charge)
    }
}

/// `/compound/<domain>/<id>/cids/JSON`
struct PubChemIdentifierListDTO: Decodable, Sendable {
    let identifierList: List

    struct List: Decodable, Sendable {
        let cid: [Int]

        enum CodingKeys: String, CodingKey {
            case cid = "CID"
        }
    }

    enum CodingKeys: String, CodingKey {
        case identifierList = "IdentifierList"
    }
}

/// `…/rest/autocomplete/compound/<term>/JSON` — the Auto-Complete Search
/// Service.
///
/// Terms, not records: what comes back is a list of chemical names PubChem
/// indexes that start with what was typed. Selecting one is what performs a
/// lookup, so nothing here is ever shown as a compound the app has found.
struct PubChemAutocompleteDTO: Decodable, Sendable {
    let total: Int
    let dictionaryTerms: Terms

    struct Terms: Decodable, Sendable {
        let compound: [String]
    }

    enum CodingKeys: String, CodingKey {
        case total
        case dictionaryTerms = "dictionary_terms"
    }
}

/// `/compound/cid/<cid>/JSON` — the full record, 2D or 3D.
struct PubChemRecordResponseDTO: Decodable, Sendable {
    let compounds: [PubChemRecordDTO]

    enum CodingKeys: String, CodingKey {
        case compounds = "PC_Compounds"
    }
}

/// One compound record: atoms, bonds and one or more coordinate sets.
struct PubChemRecordDTO: Decodable, Sendable {
    let id: Identifier
    let atoms: Atoms?
    let bonds: Bonds?
    let coords: [Coordinates]?
    let charge: Int?

    struct Identifier: Decodable, Sendable {
        let id: Inner
        struct Inner: Decodable, Sendable {
            let cid: Int
        }
    }

    struct Atoms: Decodable, Sendable {
        let aid: [Int]
        let element: [Int]
        let charge: [Charge]?

        struct Charge: Decodable, Sendable {
            let aid: Int
            let value: Int
        }
    }

    struct Bonds: Decodable, Sendable {
        let aid1: [Int]
        let aid2: [Int]
        let order: [Int]
    }

    struct Coordinates: Decodable, Sendable {
        /// PubChem's coordinate-type flags. 2 = 3D, 1 = 2D (among others).
        let type: [Int]
        let aid: [Int]
        let conformers: [Conformer]

        struct Conformer: Decodable, Sendable {
            let x: [Double]
            let y: [Double]
            let z: [Double]?
        }

        var is3D: Bool { type.contains(2) || conformers.contains { $0.z != nil } }
    }

    var cid: Int { id.id.cid }
}

/// The error envelope PubChem returns with a 4xx or 5xx status.
struct PubChemFaultDTO: Decodable, Sendable {
    let fault: Body

    struct Body: Decodable, Sendable {
        let code: String
        let message: String?
        let details: [String]?

        enum CodingKeys: String, CodingKey {
            case code = "Code"
            case message = "Message"
            case details = "Details"
        }
    }

    enum CodingKeys: String, CodingKey {
        case fault = "Fault"
    }
}

// MARK: - Conversion

extension PubChemRecordDTO {
    /// The atoms, bonds and coordinates of this record as the app's own type,
    /// or `nil` when the record has no atoms at all.
    ///
    /// Handles what the service actually sends: a single-atom record has no
    /// `bonds`; a 2D record has no `z`; a record can carry several coordinate
    /// sets, of which the 3D one is preferred.
    func compoundStructure() -> CompoundStructure? {
        guard let atoms, !atoms.aid.isEmpty, atoms.aid.count == atoms.element.count else { return nil }
        let charges = Dictionary((atoms.charge ?? []).map { ($0.aid, $0.value) },
                                 uniquingKeysWith: { first, _ in first })

        let set = coords?.first { $0.is3D } ?? coords?.first
        let conformer = set?.conformers.first
        var positions: [Int: (Double, Double, Double)] = [:]
        if let set, let conformer, conformer.x.count == set.aid.count, conformer.y.count == set.aid.count {
            for (index, aid) in set.aid.enumerated() {
                let z = conformer.z.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? 0
                positions[aid] = (conformer.x[index], conformer.y[index], z)
            }
        }
        let is3D = set?.is3D ?? false

        let idIndex = Dictionary(atoms.aid.enumerated().map { ($0.element, $0.offset) },
                                 uniquingKeysWith: { first, _ in first })
        let compoundAtoms = atoms.aid.enumerated().map { index, aid in
            let position = positions[aid] ?? (0, 0, 0)
            return CompoundAtom(
                id: index,
                atomicNumber: atoms.element[index],
                x: position.0, y: position.1, z: position.2,
                formalCharge: charges[aid] ?? 0
            )
        }

        var compoundBonds: [CompoundBond] = []
        if let bonds, bonds.aid1.count == bonds.aid2.count, bonds.aid1.count == bonds.order.count {
            for index in bonds.aid1.indices {
                guard let from = idIndex[bonds.aid1[index]], let to = idIndex[bonds.aid2[index]] else { continue }
                // 1–3 are covalent orders; PubChem's 4 (quadruple), 5 (dative),
                // 6 (complex), 7 (ionic) and 255 (unknown) are drawn as single.
                let order = (1...3).contains(bonds.order[index]) ? bonds.order[index] : 1
                compoundBonds.append(CompoundBond(
                    id: compoundBonds.count, from: from, to: to, order: order,
                    isContact: bonds.order[index] == 7
                ))
            }
        }

        let cid = self.id.id.cid
        return CompoundStructure(
            is3D: is3D,
            source: is3D ? .pubChem3D : .pubChem2D,
            note: is3D
                ? "PubChem computed 3D conformer: real connectivity and bond orders; a calculated "
                    + "geometry, not a measured one."
                : "PubChem 2D record: real connectivity and bond orders, drawn flat.",
            atoms: compoundAtoms,
            bonds: compoundBonds,
            // Recorded rather than inferred later: which record was asked for,
            // where each set of coordinates came from, and when.
            provenance: CompoundStructureProvenance(
                pubChemCID: cid,
                recordType: is3D ? "3d" : "2d",
                twoDSource: is3D ? .generatedFromConnectivity : .pubChemDepiction2D,
                threeDSource: is3D ? .pubChemConformer3D : nil,
                retrieved: CompoundFormula.today()
            )
        )
    }
}
