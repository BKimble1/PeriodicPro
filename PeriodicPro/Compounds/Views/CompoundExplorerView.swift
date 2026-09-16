import SwiftUI

/// The immersive 3D viewer for a compound: the same RealityKit scene the
/// element explorer uses, with a ball-and-stick / space-fill switch.
///
/// Free for everyone — the compound features are part of the beta, not of
/// Elemora Pro.
struct CompoundExplorerView: View {
    let compound: ChemicalCompound
    let tint: ElementCategory
    var initialStyle: CompoundRenderStyle = .ballAndStick

    @Environment(\.dismiss) private var dismiss
    @Environment(\.elementCatalog) private var catalog
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var style: CompoundRenderStyle = .ballAndStick
    @State private var selection: StructureSelection = .none
    @State private var hasAppliedInitialStyle = false

    private var scene: StructureScene? {
        CompoundStructureScene.scene(for: compound, style: style)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Style", selection: $style) {
                    ForEach(CompoundRenderStyle.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.bottom, Theme.Spacing.m)
                .accessibilityIdentifier("compoundExplorer.style")

                if let scene {
                    viewer(scene)
                    partsRow(scene)
                    inspector(scene)
                } else {
                    EmptyStateView(
                        symbolName: "cube.fill",
                        title: "No structure to show",
                        message: "This compound has no drawn structure."
                    )
                }
            }
            .background(backdrop)
            .navigationTitle(compound.preferredName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("compoundExplorer.done")
                }
            }
        }
        .tint(AppColor.accent)
        .onAppear {
            guard !hasAppliedInitialStyle else { return }
            hasAppliedInitialStyle = true
            style = initialStyle
        }
        .onChange(of: style) { _, _ in selection = .none }
    }

    private func viewer(_ scene: StructureScene) -> some View {
        StructureRealityView(scene: scene, accent: tint.accentColor, selection: $selection)
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if selection.isEmpty && !dynamicTypeSize.isAccessibilitySize {
                    Text("Drag to turn · Pinch to zoom · Tap an atom")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, 6)
                        .background { Capsule().fill(.ultraThinMaterial) }
                        .padding(Theme.Spacing.m)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CompoundFactsBuilder.summary(of: scene, compound: compound, catalog: catalog))
            .accessibilityIdentifier("compoundExplorer.viewer")
    }

    private func partsRow(_ scene: StructureScene) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(parts(of: scene)) { part in
                    Button {
                        Haptics.tap()
                        withAnimation(reduceMotion ? nil : Theme.Motion.reveal) {
                            selection = selection == part.selection ? .none : part.selection
                        }
                    } label: {
                        Text(part.label)
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(selection == part.selection ? Color.white : AppColor.primaryText)
                            .padding(.horizontal, Theme.Spacing.l)
                            .frame(minHeight: Theme.minimumTouchTarget)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(selection == part.selection ? AppColor.accent : AppColor.surface)
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(selection == part.selection ? .clear : AppColor.hairline,
                                                  lineWidth: 0.8)
                            }
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == part.selection ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, Theme.Spacing.screenMargin)
            .padding(.vertical, Theme.Spacing.s)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("compoundExplorer.parts")
    }

    /// The generic part list, with atoms named by their element.
    private func parts(of scene: StructureScene) -> [StructurePartList.Part] {
        StructurePartList.parts(of: scene).map { part in
            guard case .node(let id) = part.selection,
                  let number = scene.node(id: id)?.atomicNumber,
                  let element = catalog.element(atomicNumber: number) else { return part }
            let sameElement = scene.atoms.filter { $0.atomicNumber == number }
            let ordinal = (sameElement.firstIndex { $0.id == id } ?? 0) + 1
            let label = sameElement.count > 1 ? "\(element.symbol) \(ordinal)" : element.symbol
            return StructurePartList.Part(label: label, selection: part.selection)
        }
    }

    private func inspector(_ scene: StructureScene) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let facts = CompoundFactsBuilder.facts(for: selection, in: scene, compound: compound,
                                                      catalog: catalog) {
                StructureInspectorView(facts: facts)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(compound.displayFormula)
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(AppColor.primaryText)
                        if scene.isSimplified { SimplifiedBadge() }
                    }
                    Text(scene.representationLabel)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(AppColor.secondaryText)
                        .textCase(.uppercase)
                        .kerning(0.5)
                    Text(scene.caption)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(6)
                    Text(compound.attribution)
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("compoundExplorer.summary")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.screenMargin)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.l)
        .animation(reduceMotion ? nil : Theme.Motion.reveal, value: selection)
    }

    private var backdrop: some View {
        ZStack {
            AppColor.canvas
            RadialGradient(
                colors: [tint.tileFill.opacity(0.55), AppColor.canvas.opacity(0)],
                center: .center, startRadius: 10, endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}
