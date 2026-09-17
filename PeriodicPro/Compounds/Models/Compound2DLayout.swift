import CoreGraphics
import Foundation

/// What a 2D drawing of a compound honestly is.
///
/// Naming matters here. A line-angle drawing is a *skeletal formula*, and that
/// convention only means anything for a carbon skeleton. Sodium chloride has
/// no molecule and no skeleton, so it is never called one — it gets a formula
/// unit and says so.
enum Compound2DRepresentation: String, Hashable, Sendable {
    /// Line-angle notation: carbons are vertices, C–H is implicit.
    case skeletal
    /// Every atom drawn and labeled, which is how H₂O, CO₂ and NH₃ are written.
    case structural
    /// An ionic or network solid: no discrete molecule, so the formula unit is
    /// the honest depiction.
    case formulaUnit
    /// Nothing is known about this composition's structure. Distinct from a
    /// formula unit on purpose: "there is no molecule" is a claim about
    /// chemistry, and "we have no record" is a claim about the database.
    case unknownStructure

    var label: String {
        switch self {
        case .skeletal: return "Skeletal formula"
        case .structural: return "2D structure"
        case .formulaUnit: return "Formula unit"
        case .unknownStructure: return "Composition"
        }
    }

    var caption: String {
        switch self {
        case .skeletal:
            return "Line-angle notation: each unlabeled vertex is a carbon atom, and the hydrogens "
                + "bonded to carbon are implied."
        case .structural:
            return "Every atom is drawn. Bond geometry comes from the compound's own structure record."
        case .formulaUnit:
            return "This compound has no discrete molecule, so there is no skeletal formula to draw. "
                + "The formula unit is the ratio its lattice repeats."
        case .unknownStructure:
            return "No structure is drawn because none is known. Nothing here is inferred from the "
                + "formula."
        }
    }

    /// What is written under the formula when there is no geometry to draw.
    var emptyStateNote: String? {
        switch self {
        case .skeletal, .structural: return nil
        case .formulaUnit: return "No discrete molecule"
        case .unknownStructure: return "No known structure"
        }
    }
}

/// One atom as it is drawn.
struct Compound2DAtom: Hashable, Identifiable, Sendable {
    let id: Int
    let atomicNumber: Int
    /// Position in the drawing's own unit square, y increasing downward.
    let point: CGPoint
    /// What to write at this point, or `nil` for a bare vertex (a carbon in
    /// line-angle notation).
    let label: String?
    let formalCharge: Int
}

/// One bond as it is drawn.
struct Compound2DBond: Hashable, Identifiable, Sendable {
    let id: Int
    let from: CGPoint
    let to: CGPoint
    /// 1, 2 or 3.
    let order: Int
    /// True when either end carries a label, so the line is shortened to make
    /// room for it.
    let startsAtLabel: Bool
    let endsAtLabel: Bool
}

/// A compound reduced to something drawable, and nothing invented.
struct Compound2DDrawing: Hashable, Sendable {
    let representation: Compound2DRepresentation
    let atoms: [Compound2DAtom]
    let bonds: [Compound2DBond]
    /// The formula to show instead of a structure, for a formula unit.
    let formula: String
    /// True when the drawing has geometry worth rendering.
    var hasGeometry: Bool {
        !atoms.isEmpty && representation != .formulaUnit && representation != .unknownStructure
    }
}

/// Turns a compound's real structure record into a 2D depiction.
///
/// Pure arithmetic over the atoms and bonds the record already carries, so
/// nothing here can draw a molecule the data does not describe — and every
/// rule below is a unit test rather than a picture somebody eyeballed.
///
/// The bundled and fetched records are 3D conformers, so a flat drawing needs a
/// plane. Dropping the z coordinate would fold whichever way the conformer
/// happened to be stored; instead the plane of best fit is found from the
/// atoms themselves, which lands exactly on the molecular plane for anything
/// planar (benzene, caffeine, acetic acid) and gives a faithful orthographic
/// view of anything that is not.
enum Compound2DLayout {
    /// Atoms whose hydrogens are written into the label rather than drawn.
    static let heteroatoms: Set<Int> = [7, 8, 15, 16, 9, 17, 35, 53]

    // MARK: - Entry point

    static func drawing(
        for compound: ChemicalCompound,
        catalog: ElementCatalog = .bundledOrEmpty
    ) -> Compound2DDrawing {
        let formula = compound.displayFormula
        guard let structure = compound.structure, !structure.atoms.isEmpty else {
            return Compound2DDrawing(
                representation: .unknownStructure, atoms: [], bonds: [], formula: formula
            )
        }
        let representation = self.representation(for: compound, structure: structure)
        guard representation != .formulaUnit else {
            return Compound2DDrawing(
                representation: .formulaUnit, atoms: [], bonds: [], formula: formula
            )
        }

        let hidden = hiddenHydrogens(structure: structure, representation: representation)
        let implicitHydrogens = implicitHydrogenCounts(structure: structure, hidden: hidden)
        let visible = structure.atoms.filter { !hidden.contains($0.id) }
        guard !visible.isEmpty else {
            return Compound2DDrawing(
                representation: .formulaUnit, atoms: [], bonds: [], formula: formula
            )
        }

        let projected = project(visible)
        var pointsByID: [Int: CGPoint] = [:]
        for (atom, point) in zip(visible, projected) { pointsByID[atom.id] = point }

        let atoms = visible.map { atom -> Compound2DAtom in
            Compound2DAtom(
                id: atom.id,
                atomicNumber: atom.atomicNumber,
                point: pointsByID[atom.id] ?? .zero,
                label: label(
                    for: atom,
                    representation: representation,
                    implicitHydrogens: implicitHydrogens[atom.id] ?? 0,
                    catalog: catalog
                ),
                formalCharge: atom.formalCharge
            )
        }
        let labeled = Set(atoms.filter { $0.label != nil }.map(\.id))

        let bonds = structure.bonds.compactMap { bond -> Compound2DBond? in
            guard !bond.isContact else { return nil }
            guard let from = pointsByID[bond.from], let to = pointsByID[bond.to] else { return nil }
            return Compound2DBond(
                id: bond.id,
                from: from,
                to: to,
                order: min(max(bond.order, 1), 3),
                startsAtLabel: labeled.contains(bond.from),
                endsAtLabel: labeled.contains(bond.to)
            )
        }
        return Compound2DDrawing(
            representation: representation, atoms: atoms, bonds: bonds, formula: formula
        )
    }

    // MARK: - Which depiction

    static func representation(
        for compound: ChemicalCompound,
        structure: CompoundStructure
    ) -> Compound2DRepresentation {
        if structure.source == .curatedLattice { return .formulaUnit }
        if compound.bondingClass == .ionic || compound.bondingClass == .networkSolid {
            return .formulaUnit
        }
        if structure.bonds.allSatisfy(\.isContact) { return .formulaUnit }
        // Line-angle notation draws a carbon skeleton. One carbon is not a
        // skeleton, so methanol, methane and carbon dioxide are written out in
        // full rather than reduced to a single unlabeled point.
        let carbons = structure.atoms.filter { $0.atomicNumber == 6 }.count
        return carbons >= 2 ? .skeletal : .structural
    }

    // MARK: - Hydrogens

    /// The hydrogens a skeletal drawing leaves out: all of them, because a
    /// hydrogen on carbon is implied by the convention and a hydrogen on a
    /// heteroatom is written into that atom's label instead.
    static func hiddenHydrogens(
        structure: CompoundStructure,
        representation: Compound2DRepresentation
    ) -> Set<Int> {
        guard representation == .skeletal else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: structure.atoms.map { ($0.id, $0) })
        var hidden: Set<Int> = []
        for atom in structure.atoms where atom.atomicNumber == 1 {
            // A hydrogen with more than one bond is doing something unusual
            // (a bridge); it stays visible rather than being quietly dropped.
            let bonds = structure.bonds.filter { !$0.isContact && ($0.from == atom.id || $0.to == atom.id) }
            guard bonds.count == 1, let bond = bonds.first else { continue }
            let partnerID = bond.from == atom.id ? bond.to : bond.from
            guard let partner = byID[partnerID] else { continue }
            if partner.atomicNumber == 6 || heteroatoms.contains(partner.atomicNumber) {
                hidden.insert(atom.id)
            }
        }
        return hidden
    }

    /// How many hidden hydrogens each remaining atom has to write into its
    /// label — the "H" in an –OH, the "H₂" in an –NH₂.
    static func implicitHydrogenCounts(
        structure: CompoundStructure,
        hidden: Set<Int>
    ) -> [Int: Int] {
        guard !hidden.isEmpty else { return [:] }
        var counts: [Int: Int] = [:]
        for bond in structure.bonds where !bond.isContact {
            let other: Int
            if hidden.contains(bond.from) {
                other = bond.to
            } else if hidden.contains(bond.to) {
                other = bond.from
            } else {
                continue
            }
            guard !hidden.contains(other) else { continue }
            counts[other, default: 0] += 1
        }
        return counts
    }

    /// What is written at an atom, or `nil` for a bare carbon vertex.
    static func label(
        for atom: CompoundAtom,
        representation: Compound2DRepresentation,
        implicitHydrogens: Int,
        catalog: ElementCatalog = .bundledOrEmpty
    ) -> String? {
        let symbol = catalog.element(atomicNumber: atom.atomicNumber)?.symbol ?? "?"
        guard representation == .skeletal else { return symbol }
        // A carbon is the vertex itself; anything else is spelled out, with
        // the hydrogens the convention hides folded into its label. A carbon
        // carrying a charge is labeled, because the charge has to be readable.
        if atom.atomicNumber == 6, atom.formalCharge == 0 { return nil }
        guard implicitHydrogens > 0 else { return symbol }
        // Subscripted as one string: `subscripted` only lowers a digit that
        // follows a letter, so subscripting "2" on its own gives back "2".
        let count = implicitHydrogens > 1 ? String(implicitHydrogens) : ""
        return CompoundFormula.subscripted(symbol + "H" + count)
    }

    // MARK: - Projection

    /// Projects atoms onto their own plane of best fit, then normalizes into
    /// the unit square with y increasing downward (screen order).
    static func project(_ atoms: [CompoundAtom]) -> [CGPoint] {
        guard !atoms.isEmpty else { return [] }
        let positions = atoms.map { SIMD3<Double>($0.x, $0.y, $0.z) }
        let center = positions.reduce(SIMD3<Double>.zero, +) / Double(positions.count)
        let centered = positions.map { $0 - center }
        let (first, second) = principalAxes(centered)
        let planar = centered.map { CGPoint(x: dot($0, first), y: dot($0, second)) }
        return normalize(planar)
    }

    /// The two directions the atoms spread out in most: the eigenvectors of
    /// their covariance matrix with the two largest eigenvalues.
    static func principalAxes(
        _ points: [SIMD3<Double>]
    ) -> (SIMD3<Double>, SIMD3<Double>) {
        var covariance = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for point in points {
            let value = [point.x, point.y, point.z]
            for row in 0..<3 {
                for column in 0..<3 {
                    covariance[row][column] += value[row] * value[column]
                }
            }
        }
        let (values, vectors) = jacobiEigen(covariance)
        let order = (0..<3).sorted { values[$0] > values[$1] }
        let first = SIMD3<Double>(vectors[0][order[0]], vectors[1][order[0]], vectors[2][order[0]])
        let second = SIMD3<Double>(vectors[0][order[1]], vectors[1][order[1]], vectors[2][order[1]])
        return (normalized(first), normalized(second))
    }

    /// Cyclic Jacobi rotation for a symmetric 3 × 3 matrix. Returns the
    /// eigenvalues and the matrix whose columns are the eigenvectors.
    static func jacobiEigen(_ input: [[Double]]) -> ([Double], [[Double]]) {
        var matrix = input
        var vectors = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        for index in 0..<3 { vectors[index][index] = 1 }

        for _ in 0..<24 {
            // The largest off-diagonal magnitude decides which plane to rotate.
            var pivotRow = 0
            var pivotColumn = 1
            var largest = abs(matrix[0][1])
            for (row, column) in [(0, 2), (1, 2)] where abs(matrix[row][column]) > largest {
                largest = abs(matrix[row][column])
                pivotRow = row
                pivotColumn = column
            }
            if largest < 1e-12 { break }

            let difference = matrix[pivotColumn][pivotColumn] - matrix[pivotRow][pivotRow]
            let theta = 0.5 * atan2(2 * matrix[pivotRow][pivotColumn], difference)
            let cosine = cos(theta)
            let sine = sin(theta)

            var rotated = matrix
            for index in 0..<3 {
                let row = matrix[index][pivotRow]
                let column = matrix[index][pivotColumn]
                rotated[index][pivotRow] = cosine * row - sine * column
                rotated[index][pivotColumn] = sine * row + cosine * column
            }
            var result = rotated
            for index in 0..<3 {
                let row = rotated[pivotRow][index]
                let column = rotated[pivotColumn][index]
                result[pivotRow][index] = cosine * row - sine * column
                result[pivotColumn][index] = sine * row + cosine * column
            }
            matrix = result

            var updated = vectors
            for index in 0..<3 {
                let row = vectors[index][pivotRow]
                let column = vectors[index][pivotColumn]
                updated[index][pivotRow] = cosine * row - sine * column
                updated[index][pivotColumn] = sine * row + cosine * column
            }
            vectors = updated
        }
        return ([matrix[0][0], matrix[1][1], matrix[2][2]], vectors)
    }

    /// Scales points into the unit square, preserving aspect ratio and
    /// centering whichever axis is shorter. A single atom lands in the middle.
    static func normalize(_ points: [CGPoint]) -> [CGPoint] {
        guard let first = points.first else { return [] }
        var minimum = first
        var maximum = first
        for point in points {
            minimum.x = min(minimum.x, point.x)
            minimum.y = min(minimum.y, point.y)
            maximum.x = max(maximum.x, point.x)
            maximum.y = max(maximum.y, point.y)
        }
        let width = maximum.x - minimum.x
        let height = maximum.y - minimum.y
        let span = max(width, height)
        guard span > 1e-9 else {
            return points.map { _ in CGPoint(x: 0.5, y: 0.5) }
        }
        let offsetX = (span - width) / 2
        let offsetY = (span - height) / 2
        return points.map { point in
            CGPoint(
                x: (point.x - minimum.x + offsetX) / span,
                // Chemistry coordinates run y upward; a canvas runs it down.
                y: 1 - (point.y - minimum.y + offsetY) / span
            )
        }
    }

    private static func dot(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private static func normalized(_ vector: SIMD3<Double>) -> SIMD3<Double> {
        let length = (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).squareRoot()
        guard length > 1e-12 else { return SIMD3<Double>(1, 0, 0) }
        return vector / length
    }
}
