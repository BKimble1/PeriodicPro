import SwiftUI
import VisionKit

/// The camera half of the scanner: VisionKit's live text recognizer, wrapped.
///
/// `DataScannerViewController` is the same machinery Live Text uses. It runs
/// the camera, recognizes text continuously, and hands back every item it can
/// see on every update — which is what a scanner with no shutter button needs.
/// Nothing is captured, written or uploaded: frames are analyzed in the
/// controller and discarded, and the only thing that leaves this view is the
/// text it read.
///
/// Highlighting and guidance are off because the app draws its own overlay:
/// the learner needs to see which of several formulas on a page is being
/// tracked, and how close it is to settling, which VisionKit's own highlight
/// does not say.
struct LiveTextScannerView: UIViewControllerRepresentable {
    /// Every text item currently visible, as normalized rectangles.
    let onRecognize: ([(text: String, confidence: Double, bounds: CGRect)]) -> Void
    /// Reported when the controller could not start, which is a state the
    /// screen has to show rather than a crash.
    let onFailure: (String) -> Void

    /// Whether this device can run live text recognition at all.
    ///
    /// False on the simulator and on hardware without the Neural Engine, so
    /// the screen has an honest unsupported state rather than a black
    /// rectangle.
    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    /// Whether it can run *now* — which also depends on camera permission.
    static var isAvailable: Bool {
        DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["en-US"])],
            // Accurate rather than fast: a formula is short, dense and
            // case-sensitive, and reading H2SO4 as H2S04 is the failure that
            // matters here.
            qualityLevel: .accurate,
            // On, and then narrowed by `regionOfInterest` below. A page often
            // prints the name and the formula on consecutive lines and the
            // learner means whichever one they aimed at, so both are read and
            // the region decides which count.
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        return controller
    }

    /// The band of the frame that counts, as a fraction of the view.
    ///
    /// Everything outside it is not read at all. Without this the scanner
    /// considers every word in shot — on a textbook page that is the running
    /// head, the caption, the paragraph and the figure label, all competing
    /// with the formula the learner is actually pointing at, and the one that
    /// settles first wins. Narrowing to the middle is the difference between
    /// reading a page and reading what somebody aimed at, and it is the single
    /// biggest thing standing between this scanner and a right answer.
    ///
    /// Wide, because a chemical name can be long, and shallow, because a
    /// formula is one line. `ScannerReticle` draws exactly this rectangle, so
    /// what is framed on screen is what is being read.
    static let regionOfInterest = CGRect(x: 0.06, y: 0.36, width: 0.88, height: 0.20)

    private static func regionOfInterest(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.width * regionOfInterest.minX,
            y: bounds.height * regionOfInterest.minY,
            width: bounds.width * regionOfInterest.width,
            height: bounds.height * regionOfInterest.height
        )
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onRecognize = onRecognize
        // Re-applied on every update: the view has no size on the first pass,
        // and the region has to be re-cut when the device is turned.
        let bounds = controller.view.bounds
        if bounds.width > 0, bounds.height > 0 {
            controller.regionOfInterest = Self.regionOfInterest(in: bounds)
        }
        guard !controller.isScanning else { return }
        do {
            try controller.startScanning()
        } catch {
            onFailure(String(describing: error))
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onRecognize: onRecognize) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onRecognize: ([(text: String, confidence: Double, bounds: CGRect)]) -> Void

        init(onRecognize: @escaping ([(text: String, confidence: Double, bounds: CGRect)]) -> Void) {
            self.onRecognize = onRecognize
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(allItems, in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(allItems, in: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didRemove removedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(allItems, in: scanner)
        }

        /// VisionKit does not publish a per-item confidence, so every item
        /// arrives at 1. The stabilizer's confidence floor is therefore not
        /// what gates a VisionKit reading — its consecutive-sightings,
        /// duration and drift rules are, and those are what make a formula
        /// caught mid-pan fail to settle.
        private func report(_ items: [RecognizedItem], in scanner: DataScannerViewController) {
            let size = scanner.view.bounds.size
            guard size.width > 0, size.height > 0 else { return }
            let lines = items.compactMap { item -> (text: String, confidence: Double, bounds: CGRect)? in
                guard case .text(let text) = item else { return nil }
                let transcript = text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else { return nil }
                return (transcript, 1, Self.normalized(item.bounds, in: size))
            }
            onRecognize(lines)
        }

        /// The item's four corners, as a rectangle in the frame's own 0–1
        /// coordinates, so the stabilizer's drift rule means the same thing on
        /// every device.
        private static func normalized(_ bounds: RecognizedItem.Bounds, in size: CGSize) -> CGRect {
            let xs = [bounds.topLeft.x, bounds.topRight.x, bounds.bottomLeft.x, bounds.bottomRight.x]
            let ys = [bounds.topLeft.y, bounds.topRight.y, bounds.bottomLeft.y, bounds.bottomRight.y]
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return .zero }
            return CGRect(
                x: minX / size.width,
                y: minY / size.height,
                width: (maxX - minX) / size.width,
                height: (maxY - minY) / size.height
            )
        }
    }
}
