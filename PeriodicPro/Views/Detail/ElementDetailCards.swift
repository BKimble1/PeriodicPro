import SwiftUI

// MARK: - Structure

/// Shell diagram plus the three facts people look up most. The caption keeps
/// the model honest: shells are an energy-level bookkeeping device, not orbits.
struct StructureCard: View {
    let element: ChemicalElement
    /// Whether the full interactive explorer is available for this element.
    /// Six elements are free; the rest are part of Elemora Pro.
    var isStructureUnlocked: Bool = true
    var onExplore: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Side by side normally; stacked once the text is large enough that a
    /// 140-point diagram would squeeze the facts into a column of fragments.
    private var stacksVertically: Bool {
        dynamicTypeSize >= .accessibility1
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Atomic Structure")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)

                if stacksVertically {
                    VStack(spacing: Theme.Spacing.m) {
                        AtomicStructureView(element: element, diameter: 176)
                        facts
                    }
                } else {
                    HStack(alignment: .center, spacing: Theme.Spacing.m) {
                        AtomicStructureView(element: element, diameter: 140)
                        facts
                    }
                }

                Text("""
                    A simplified shell model. Each ring stands for an energy level and how \
                    many electrons it holds \u{2014} electrons do not travel on fixed \
                    circular paths.
                    """)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(AppColor.hairline)

                elementalForm
            }
        }
    }

    private var facts: some View {
        VStack(spacing: Theme.Spacing.s) {
            FactRow(label: "Atomic number", value: "\(element.atomicNumber)")
            FactRow(
                label: "Atomic mass",
                value: element.formattedAtomicMass,
                footnote: element.atomicMassFootnote
            )
            FactRow(
                label: "Electron configuration",
                value: element.formattedElectronConfiguration,
                monospacedValue: true
            )
        }
    }

    private var scene: StructureScene {
        StructureSceneBuilder.scene(
            for: element,
            representation: StructureSceneBuilder.representations(for: element).first ?? .atom
        )
    }

    /// The elemental-form section: a glossy preview of the real structure, the
    /// honest label for it, and the way into the interactive explorer.
    ///
    /// The preview is the same `StructureScene` the explorer renders, drawn with
    /// `Canvas` rather than RealityKit. A scrolling card must not stand up a 3D
    /// scene, and this way the picture here and the model there can never
    /// disagree about what the element looks like.
    private var elementalForm: some View {
        // Bound once. `scene` is a computed property and this view's body runs
        // on every step of the detail page's scroll handoff.
        let scene = scene
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            StructurePreview(scene: scene, accent: element.category.accentColor)
                .frame(height: stacksVertically ? 132 : 156)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(element.category.tileFill.opacity(0.5))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    StructureFactsBuilder.summary(of: scene, element: element)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Elemental form")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    if scene.isSimplified { SimplifiedBadge() }
                }
                Text(element.elementalForm)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(element.structure.displayName)
                    .font(AppFont.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            exploreButton
        }
    }

    private var exploreButton: some View {
        Button {
            Haptics.tap()
            onExplore()
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Explore in 3D")
                    .font(.system(.subheadline, weight: .semibold))
                if !isStructureUnlocked { ProBadge() }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(AppColor.accent)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTouchTarget)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(AppColor.accent.opacity(0.10))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isStructureUnlocked
                            ? "Explore \(element.name) in 3D"
                            : "Explore \(element.name) in 3D, Elemora Pro feature")
        .accessibilityIdentifier("detail.explore3D")
    }
}

/// A slowly turning, glossy preview of a structure.
///
/// Separated from `StructureCard` so the timeline that drives the rotation only
/// re-renders this small canvas, not the whole card, and so the rotation can be
/// switched off in one place under Reduce Motion.
struct StructurePreview: View {
    let scene: StructureScene
    let accent: Color
    var usesElementColor: Bool = true
    /// Identify passes `false`. A question does not need to move, the extra
    /// motion is a distraction while the learner is thinking, and an atom model
    /// can hold well over a hundred particles — redrawing those twenty times a
    /// second to decorate a quiz card is not a trade worth making.
    var animates: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPaused: Bool { reduceMotion || !animates }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: isPaused)) { context in
            StructureCanvasView(
                scene: scene,
                atomColor: accent,
                bondColor: AppColor.secondaryText,
                usesElementColor: usesElementColor,
                yaw: isPaused ? 0.6 : Self.yaw(at: context.date),
                pitch: 0.32
            )
            .padding(Theme.Spacing.s)
        }
    }

    /// One turn every forty seconds, derived from the timeline's own clock so
    /// there is no accumulating state to drift or leak.
    static func yaw(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40) / 40 * 2 * .pi
    }
}

// MARK: - Quick facts

/// One row inside the "More properties" disclosure.
struct PropertyRow: Identifiable, Hashable {
    let label: String
    let value: String
    var id: String { label }
}

/// The four facts people look up most, with the rest behind a disclosure so
/// the page never opens as a wall of numbers.
struct QuickFactsCard: View {
    let element: ChemicalElement
    @Binding var showsMoreProperties: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.s),
        GridItem(.flexible(), spacing: Theme.Spacing.s),
    ]

    private var extendedProperties: [PropertyRow] {
        var rows: [PropertyRow] = []
        if let melting = element.temperatureDisplay(element.meltingPointK) {
            rows.append(PropertyRow(label: "Melting point", value: melting))
        }
        if let boiling = element.temperatureDisplay(element.boilingPointK) {
            rows.append(PropertyRow(label: "Boiling point", value: boiling))
        }
        if let density = element.densityDisplay {
            rows.append(PropertyRow(label: "Density", value: density))
        }
        if let electronegativity = element.electronegativityDisplay {
            rows.append(PropertyRow(label: "Electronegativity", value: electronegativity))
        }
        if let discovery = element.discoveryDisplay {
            rows.append(PropertyRow(label: "Discovery", value: discovery))
        }
        return rows
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Quick Facts")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)

                LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
                    FactRow(label: "Category", value: element.category.displayName)
                    FactRow(label: "State at 25 \u{00B0}C", value: element.phase.displayName)
                    FactRow(label: "Group", value: element.groupDisplay)
                    FactRow(label: "Period", value: "\(element.period)")
                }

                if element.group == nil {
                    Text("Group numbers are not assigned to the f-block rows.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                }

                if !extendedProperties.isEmpty {
                    Button {
                        Haptics.tap()
                        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
                            showsMoreProperties.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(showsMoreProperties ? "Fewer properties" : "More properties")
                                .font(.system(.subheadline, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .rotationEffect(.degrees(showsMoreProperties ? 180 : 0))
                        }
                        .foregroundStyle(AppColor.accent)
                        .frame(maxWidth: .infinity, minHeight: Theme.minimumTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("detail.moreProperties")

                    if showsMoreProperties {
                        VStack(spacing: Theme.Spacing.s) {
                            ForEach(extendedProperties) { row in
                                FactRow(label: row.label, value: row.value)
                            }
                            Text("\(element.blockDisplay) \u{00B7} \(element.shellElectrons.count) electron shells")
                                .font(AppFont.caption2)
                                .foregroundStyle(AppColor.tertiaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .transition(reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }
}

// MARK: - About

/// One short paragraph, written for a high-school or college learner.
struct AboutCard: View {
    let element: ChemicalElement

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("About \(element.name)")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                Text(element.about)
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Uses

/// Recognisable, real-world applications as a grid of icon cards.
struct UsesCard: View {
    let element: ChemicalElement

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Two across, one at accessibility sizes. Four columns leave about 54
    /// points of text width on a 375-point phone, which is not enough for the
    /// real copy — "Superconductors" and "Thermoelectrics" break mid-word even
    /// at the default text size. Never an adaptive grid, which leaves a
    /// trailing gap on wide phones and splits four cards three-plus-one on
    /// small ones.
    private var columns: [GridItem] {
        let count = dynamicTypeSize >= .accessibility1 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: count)
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Common Uses")
                    .font(AppFont.cardTitle)
                    .foregroundStyle(AppColor.primaryText)
                LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
                    ForEach(element.uses) { use in
                        UseCard(use: use, tint: element.category.accentColor)
                    }
                }
            }
        }
    }
}

// MARK: - Memory hook

/// The memorization hook: real etymology or a genuine association, never an
/// invented one.
struct MemoryHookCard: View {
    let element: ChemicalElement

    var body: some View {
        CardContainer {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(element.category.onTileColor)
                    .frame(width: 34, height: 34)
                    .background { Circle().fill(element.category.tileFill) }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Remember it")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    Text(element.memoryHook)
                        .font(AppFont.callout)
                        .foregroundStyle(AppColor.secondaryText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Familiarity

/// Where this element stands in the learner's own progress.
struct FamiliarityCard: View {
    let elementName: String
    let snapshot: ElementProgressSnapshot

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text("Your familiarity")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: snapshot.mastery.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(snapshot.mastery.displayName)
                            .font(.system(.caption, weight: .semibold))
                    }
                    .foregroundStyle(snapshot.mastery.tint)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppColor.surfaceMuted)
                        Capsule()
                            .fill(snapshot.mastery.tint)
                            .frame(width: max(proxy.size.width * snapshot.mastery.fraction,
                                              snapshot.mastery == .notStarted ? 0 : 8))
                    }
                }
                .frame(height: 6)

                Text(detailLine)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        // An explicit label replaces the merged one, so it has to carry
        // everything the card shows — including which element it is about.
        .accessibilityLabel(
            "Your familiarity with \(elementName): \(snapshot.mastery.displayName). \(detailLine)"
        )
    }

    private var detailLine: String {
        snapshot.attempts == 0
            ? "Practice this element in Study to build familiarity."
            : "\(snapshot.correctCount) correct \u{00B7} \(snapshot.incorrectCount) to review"
    }
}
