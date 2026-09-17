import CoreGraphics
import Foundation

/// The seam where optical chemical structure recognition would plug in.
///
/// Reading a skeletal diagram — a bond-line drawing with implicit carbons —
/// is not text recognition, and no amount of Vision's OCR understands one.
/// It is a separate discipline, OCSR, whose production-quality models
/// (MolScribe, DECIMER Image Transformer, and the rest) are image-to-sequence
/// networks that output a SMILES string, not glyphs.
///
/// Build 5 ships this protocol and no implementation of it. The investigation
/// is written up in `OCSR.md`; the short version is that shipping a confident
/// structure reader means shipping a converted model and a benchmark that
/// says how often it is right, and neither can be produced without the model
/// weights and a device to measure on. A scanner that returned a molecule it
/// had guessed at, with no measured accuracy behind it, would be worse than
/// one that says it cannot read diagrams — which is what this one says.
///
/// When a recognizer does arrive it conforms here, `ChemistryScannerModel`
/// asks it only for a region that has held still, and the result goes through
/// the same PubChem identity lookup as a pasted SMILES string: recognized is
/// not the same as identified, and the interface keeps them apart.
protocol StructureRecognizer: Sendable {
    /// Whether this recognizer can run at all on this device.
    var isAvailable: Bool { get }
    /// Below this confidence a reading is never shown, whatever it says.
    var reliabilityThreshold: Double { get }
    /// Reads a cropped structure diagram.
    func recognize(_ image: CGImage) async throws -> RecognizedStructure?
}

/// What an OCSR model returns: a machine-readable structure and how sure it is.
struct RecognizedStructure: Hashable, Sendable {
    let smiles: String
    let confidence: Double
    /// The model and version that produced it, for the attribution line.
    let modelIdentifier: String
}

/// What Elemora has instead of a structure reader.
///
/// Says so, rather than approximating one. `isAvailable` is false, the
/// scanner never offers a skeletal result, and the interface tells the
/// learner what it can read — names, formulas and structure identifiers —
/// instead of pretending to read the diagram beside them.
struct UnavailableStructureRecognizer: StructureRecognizer {
    var isAvailable: Bool { false }
    /// High, and unused. Kept as a statement of the bar a recognizer would
    /// have to clear before anything it produced reached a learner.
    var reliabilityThreshold: Double { 0.90 }

    func recognize(_ image: CGImage) async throws -> RecognizedStructure? { nil }
}

/// What the scanner tells a learner about diagrams.
enum StructureRecognitionAvailability {
    static let unavailableTitle = "Structure diagrams are not read yet"
    static let unavailableMessage =
        "Elemora reads chemical names, molecular formulas, SMILES, InChI and InChIKey from the page. "
        + "Reading a skeletal diagram — working a molecule out from a bond-line drawing — needs a "
        + "different kind of model, and Elemora does not ship one yet. It would rather say so than "
        + "show you a molecule it guessed at."
}
