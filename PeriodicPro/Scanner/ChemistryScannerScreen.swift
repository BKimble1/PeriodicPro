import SwiftUI
import UIKit

/// Point the phone at a page and Elemora reads the chemistry on it.
///
/// No shutter button: the camera analyzes continuously, and a result appears
/// when the same thing has been read several times in a row from the same
/// place — which is the difference between a scanner and a camera with a
/// chemistry filter over it.
///
/// What it reads is names, molecular formulas, SMILES, InChI and InChIKey —
/// chemistry written as letters and numbers. Only the band inside the reticle
/// is read, so what the learner frames is what gets looked up.
struct ChemistryScannerScreen: View {
    @Environment(\.elementCatalog) private var catalog
    @Environment(CompoundStore.self) private var store: CompoundStore
    @Environment(ProgressStore.self) private var progress: ProgressStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = ChemistryScannerModel()
    @State private var startFailure: String?
    @State private var manualQuery = ""
    @State private var path = NavigationPath()

    /// The simulator has no camera to run live text on, and neither does
    /// hardware without the Neural Engine.
    private var isSupported: Bool {
        LiveTextScannerView.isSupported && !RuntimeFlags.isUITesting
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .navigationTitle("Scan Chemistry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("scanner.done")
                }
            }
            .navigationDestination(for: CompoundMatchCandidate.self) { candidate in
                CompoundDetailScreen(candidate: candidate)
            }
        }
        .tint(AppColor.accent)
        .task { await model.start(isSupported: isSupported) }
        .onDisappear { model.stop() }
        .accessibilityIdentifier("scanner.screen")
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .requestingPermission:
            waiting
        case .unsupported:
            unavailable(
                symbol: "camera.viewfinder",
                title: "Live scanning is not available here",
                message: "This device cannot run live text recognition. You can still search for a "
                    + "compound by name, formula or identifier."
            )
        case .denied(let state):
            deniedView(state)
        case .scanning, .resolving, .found, .notFound, .failed:
            camera
        }
    }

    private var waiting: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView().tint(.white)
            Text("Preparing the camera…")
                .font(AppFont.footnote)
                .foregroundStyle(.white.opacity(0.75))
        }
        .accessibilityIdentifier("scanner.preparing")
    }

    // MARK: - Camera

    private var camera: some View {
        ZStack(alignment: .bottom) {
            if let startFailure {
                unavailable(
                    symbol: "exclamationmark.triangle",
                    title: "The camera could not start",
                    message: startFailure
                )
            } else {
                LiveTextScannerView(
                    onRecognize: { lines in
                        model.observe(lines: lines, catalog: catalog, store: store)
                    },
                    onFailure: { startFailure = $0 }
                )
                .ignoresSafeArea()
                .accessibilityIdentifier("scanner.camera")

                // The same rectangle the recognizer is restricted to. Drawn
                // from the one constant, so what is framed cannot drift from
                // what is read.
                ScannerReticle(region: LiveTextScannerView.regionOfInterest)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            overlay
        }
    }

    @ViewBuilder
    private var overlay: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer(minLength: 0)
            switch model.phase {
            case .scanning:
                if model.visible.count > 1 {
                    chooser
                }
                guidance
            case .resolving(let candidate):
                resultCard(candidate) {
                    HStack(spacing: Theme.Spacing.s) {
                        ProgressView().controlSize(.mini)
                        Text("Looking it up…")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
            case .found(let candidate, let match):
                resultCard(candidate) {
                    foundBody(match)
                }
            case .notFound(let candidate):
                resultCard(candidate) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("No compound with this \(candidate.kindDescription.lowercased()) was found "
                             + "in Elemora or PubChem.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        resumeButton
                    }
                    .accessibilityIdentifier("scanner.notFound")
                }
            case .failed(let candidate, let message):
                resultCard(candidate) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(message)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("The text was read; it could not be looked up.")
                            .font(AppFont.caption2)
                            .foregroundStyle(AppColor.tertiaryText)
                        resumeButton
                    }
                    .accessibilityIdentifier("scanner.failed")
                }
            case .idle, .requestingPermission, .denied, .unsupported:
                EmptyView()
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.l)
        .animation(reduceMotion ? nil : Theme.Motion.soft, value: model.phase)
    }

    private var guidance: some View {
        VStack(spacing: Theme.Spacing.s) {
            // Fills as the scanner grows sure, so holding still reads as
            // progress rather than as nothing happening.
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .tint(AppColor.accent)
                .frame(maxWidth: 160)
                .opacity(model.progress > 0 ? 1 : 0)
                .accessibilityHidden(true)

            Text(model.visible.isEmpty
                 ? "Point at a chemical name, formula or identifier."
                 : "Hold steady on \(model.visible[0].displayText)")
                .font(AppFont.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background { Capsule().fill(.black.opacity(0.55)) }
                .accessibilityIdentifier("scanner.guidance")
                .accessibilityLabel(model.visible.isEmpty
                                    ? "Point the camera at a chemical name, formula or identifier"
                                    : "Reading \(model.visible[0].displayText). Hold steady.")
        }
    }

    /// A page with several formulas on it: the learner picks.
    private var chooser: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(model.visible.prefix(6)) { candidate in
                    Button {
                        model.select(candidate, store: store)
                    } label: {
                        VStack(spacing: 1) {
                            Text(candidate.displayText)
                                .font(.system(.subheadline, weight: .semibold))
                                .lineLimit(1)
                            Text(candidate.kindDescription)
                                .font(.system(size: 10))
                                .opacity(0.7)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                        .background { Capsule().fill(.black.opacity(0.6)) }
                        .overlay { Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.7) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scanner.candidate")
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recognized on this page")
        .accessibilityIdentifier("scanner.candidates")
    }

    private func resultCard<Body: View>(
        _ candidate: ScanCandidate, @ViewBuilder body: () -> Body
    ) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(candidate.displayText)
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(candidate.kindDescription)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                }
                body()
            }
        }
        .accessibilityIdentifier("scanner.result")
    }

    private func foundBody(_ match: CompoundMatchCandidate) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.name)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(1)
                    Text(match.displayFormula)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                Spacer(minLength: 0)
                VerifiedBadge(source: match.isLocal ? .curated : .pubChem)
            }
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    Haptics.tap()
                    path.append(match)
                } label: {
                    Text("Open")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.minimumTouchTarget)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(AppColor.accent)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scanner.open")

                resumeButton
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanner.found")
    }

    private var resumeButton: some View {
        Button {
            Haptics.tap()
            model.resume()
        } label: {
            Text("Resume scan")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(AppColor.accent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scanner.resume")
    }

    // MARK: - When there is no camera

    private func deniedView(_ state: CameraAuthorization.State) -> some View {
        unavailable(
            symbol: "camera.viewfinder",
            title: state == .restricted ? "The camera is restricted" : "Camera access is off",
            message: state == .restricted
                ? "This device does not allow camera access, so scanning is unavailable. You can "
                    + "still search for a compound by name, formula or identifier."
                : "Elemora uses the camera to read chemical names, formulas and identifiers you point "
                    + "at. Nothing is recorded or uploaded. You can turn access on in Settings, or "
                    + "search for a compound instead.",
            showsSettings: state != .restricted
        )
    }

    /// Every dead end offers the same way forward: type it instead.
    private func unavailable(
        symbol: String, title: String, message: String, showsSettings: Bool = false
    ) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                Image(systemName: symbol)
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(AppFont.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if showsSettings {
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    } label: {
                        Text("Open Settings")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.minimumTouchTarget)
                            .background {
                                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                    .fill(AppColor.accent)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scanner.openSettings")
                }

                manualFallback
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: Theme.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scanner.unavailable")
    }

    /// The fallback, on every dead end: search for it by hand.
    private var manualFallback: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Search instead")
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(.white)
            CompoundSearchField(query: $manualQuery)
                .accessibilityIdentifier("scanner.manualSearch")
            Button {
                Haptics.tap()
                searchManually()
            } label: {
                Text("Look it up")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(manualQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("scanner.manualLookUp")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func searchManually() {
        let text = manualQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let query = ChemicalQueryClassifier.classify(text, catalog: catalog)
        let candidate = ScanCandidate(
            text: text, raw: text, query: query, confidence: 1,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        model.select(candidate, store: store)
    }
}


/// The frame drawn over the camera, marking the band that is actually read.
///
/// Corner brackets rather than a full rectangle: a closed box over a page
/// reads as a thing to line text up inside, which is exactly right, while a
/// solid border competes with the text for attention.
struct ScannerReticle: View {
    let region: CGRect

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(
                x: proxy.size.width * region.minX,
                y: proxy.size.height * region.minY,
                width: proxy.size.width * region.width,
                height: proxy.size.height * region.height
            )
            let corner: CGFloat = min(28, rect.height / 2)
            ZStack {
                // Everything outside the band, dimmed, so the eye goes to the
                // part that counts.
                Rectangle()
                    .fill(.black.opacity(0.35))
                    .mask {
                        Rectangle()
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }

                ReticleCorners(rect: rect, arm: corner)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
    }
}

/// Four corner brackets around a rectangle.
struct ReticleCorners: Shape {
    let rect: CGRect
    let arm: CGFloat

    func path(in _: CGRect) -> Path {
        var path = Path()
        for (corner, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
            (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
        }
        return path
    }
}
