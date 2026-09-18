import CoreGraphics
import Foundation

/// A piece of chemistry the camera has read.
///
/// The text is normalized — subscripts and superscripts folded to ASCII, the
/// several dash characters collapsed, the OCR confusions chemistry can
/// actually resolve corrected — and `raw` keeps what was on the page, so the
/// interface can show the learner what it read rather than only what it made
/// of it.
struct ScanCandidate: Hashable, Identifiable, Sendable {
    /// What was recognized, after normalization.
    let text: String
    /// What was on the page, before it.
    let raw: String
    /// Which kind of identifier this is.
    let query: ChemicalQuery
    /// Vision's own confidence in the text, 0 to 1.
    let confidence: Double
    /// Where it sits in the frame, in normalized coordinates.
    let bounds: CGRect
    /// The atomic number, when the text names one element exactly — the
    /// symbol as the table spells it, or the element's name.
    ///
    /// This is what makes pointing at a periodic table work. `Na` is a
    /// formula as far as the parser is concerned, and looking it up as a
    /// compound means a PubChem round trip that answers with something that
    /// is not the sodium page; the app has all 118 elements bundled and can
    /// answer instantly and correctly instead.
    var element: Int?

    /// Stable across frames, so the stabilizer can tell "the same thing
    /// again" from "something new".
    var id: String { "\(kindRank)|\(text)" }

    /// How strong a claim this kind of match is.
    ///
    /// An element is the strongest: the app has all 118 of them bundled, so
    /// there is nothing to look up and nothing to be wrong about. Then an
    /// InChIKey, which identifies one structure exactly; a formula, which
    /// identifies a composition; a name, which identifies whatever the index
    /// says it does. When two candidates are in the same frame, the more
    /// specific one wins.
    var kindRank: Int {
        if element != nil { return 0 }
        switch query {
        case .inchiKey: return 1
        case .inchi: return 2
        case .smiles: return 3
        case .cid: return 4
        case .formula: return 5
        case .name: return 6
        case .empty: return 7
        }
    }

    var kindDescription: String {
        element != nil ? "Element" : query.kindDescription
    }

    /// For display: a formula reads better with its subscripts back. An
    /// element symbol has no subscripts to put back, and a name would be
    /// disfigured by the attempt.
    var displayText: String {
        if element != nil { return text }
        if case .formula = query { return CompoundFormula.subscripted(text) }
        return text
    }
}
