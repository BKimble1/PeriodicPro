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

    /// Stable across frames, so the stabilizer can tell "the same thing
    /// again" from "something new".
    var id: String { "\(kindRank)|\(text)" }

    /// How strong a claim this kind of match is.
    ///
    /// An InChIKey identifies one structure exactly; a formula identifies a
    /// composition; a name identifies whatever the index says it does. When
    /// two candidates are in the same frame, the more specific one wins.
    var kindRank: Int {
        switch query {
        case .inchiKey: return 0
        case .inchi: return 1
        case .smiles: return 2
        case .cid: return 3
        case .formula: return 4
        case .name: return 5
        case .empty: return 6
        }
    }

    var kindDescription: String { query.kindDescription }

    /// For display: a formula reads better with its subscripts back.
    var displayText: String {
        if case .formula = query { return CompoundFormula.subscripted(text) }
        return text
    }
}
