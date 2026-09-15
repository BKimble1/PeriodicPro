import SwiftUI

/// The immersive structure explorer, presented as a full-screen cover from the
/// element detail page.
///
/// Every gesture the brief asks for lives here rather than in the detail card:
/// drag to turn, pinch to zoom, double tap to reframe, tap a part to inspect
/// it, and a slow idle drift that stops the moment the learner touches the
/// model or selects something.
struct StructureExplorerView: View {
    let element: ChemicalElement

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var representation: StructureSceneBuilder.Representation
    @State private var selection: StructureSelection = .none

    init(element: ChemicalElement) {
        self.element = element
        _representation = State(
            initialValue: StructureSceneBuilder.representations(for: element).first ?? .atom
        )
    }

    private var representations: [StructureSceneBuilder.Representation] {
        StructureSceneBuilder.representations(for: element)
    }

    private var scene: StructureScene {
        StructureSceneBuilder.scene(for: element, representation: representation)
    }

    private var facts: StructureFacts? {
        StructureFactsBuilder.facts(for: selection, in: scene, element: element)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if representations.count > 1 {
                    Picker("View", selection: $representation) {
                        ForEach(representations) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Spacing.screenMargin)
                    .padding(.bottom, Theme.Spacing.m)
                    .accessibilityIdentifier("explorer.representation")
                }

                viewer

                partsRow

                inspector
            }
            .background(backdrop)
            .navigationTitle(element.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("explorer.done")
                }
            }
        }
        .tint(AppColor.accent)
        .onChange(of: representation) { _, _ in selection = .none }
    }

    // MARK: - Viewer

    private var viewer: some View {
        StructureRealityView(
            scene: scene,
            accent: element.category.accentColor,
            selection: $selection
        )
        // A floor as well as a ceiling: at an accessibility text size the
        // caption and inspector below could otherwise squeeze the model, which
        // is the whole point of the screen, down to nothing.
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { hintChip }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StructureFactsBuilder.summary(of: scene, element: element))
        .accessibilityIdentifier("explorer.viewer")
    }

    /// One short line telling the learner the model is theirs to move. Fades
    /// away once they have selected something, by which point they know.
    @ViewBuilder
    private var hintChip: some View {
        if selection.isEmpty && !dynamicTypeSize.isAccessibilitySize {
            Text("Drag to turn · Pinch to zoom · Tap a part")
                .font(AppFont.caption2)
                .foregroundStyle(AppColor.secondaryText)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 6)
                .background { Capsule().fill(.ultraThinMaterial) }
                .padding(Theme.Spacing.m)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Parts

    private var partsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(StructurePartList.parts(of: scene)) { part in
                    Button {
                        Haptics.tap()
                        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
                            selection = selection == part.selection ? .none : part.selection
                        }
                    } label: {
                        Text(part.label)
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(selection == part.selection
                                             ? Color.white
                                             : AppColor.primaryText)
                            .padding(.horizontal, Theme.Spacing.l)
                            .frame(minHeight: Theme.minimumTouchTarget)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(selection == part.selection
                                          ? AppColor.accent
                                          : AppColor.surface)
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        selection == part.selection ? .clear : AppColor.hairline,
                                        lineWidth: 0.8
                                    )
                            }
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        selection == part.selection ? [.isButton, .isSelected] : .isButton
                    )
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.vertical, Theme.Spacing.s)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("explorer.parts")
    }

    // MARK: - Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let facts {
                StructureInspectorView(facts: facts)
                    .transition(reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .bottom)))
            } else {
                sceneSummary
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.l)
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: selection)
    }

    private var sceneSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Spacing.s) {
                Text(scene.formula)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if scene.isSimplified {
                    SimplifiedBadge()
                }
            }
            Text(scene.caption)
                .font(AppFont.footnote)
                .foregroundStyle(AppColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(5)
            if let note = scene.nucleonSampleNote {
                Text(note)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("explorer.summary")
    }

    private var backdrop: some View {
        ZStack {
            AppColor.canvas
            RadialGradient(
                colors: [
                    element.category.tileFill.opacity(0.55),
                    AppColor.canvas.opacity(0),
                ],
                center: .center,
                startRadius: 10,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

/// The compact panel that appears when a part of the model is selected.
struct StructureInspectorView: View {
    let facts: StructureFacts

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(facts.title)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(facts.subtitle)
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(facts.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider().overlay(AppColor.hairline)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                        Text(row.label)
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColor.secondaryText)
                        Spacer(minLength: Theme.Spacing.s)
                        Text(row.value)
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(AppColor.primaryText)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(AppColor.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(AppColor.hairline, lineWidth: 0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("explorer.inspector")
    }
}

/// Marks a picture as a teaching simplification. Text as well as color, so it
/// reads without relying on the badge's tint.
struct SimplifiedBadge: View {
    var body: some View {
        Text("SIMPLIFIED")
            .font(.system(size: 9, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(AppColor.secondaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background { Capsule().fill(AppColor.surfaceMuted) }
            .accessibilityLabel("Simplified diagram")
    }
}
