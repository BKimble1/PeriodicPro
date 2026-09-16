import SwiftUI

/// The elements in the builder and how many of each, with plus, minus and
/// remove on every row.
struct CompositionTray: View {
    let entries: [CompoundBuilderModel.Entry]
    let canAddElement: Bool
    let onIncrement: (Int) -> Void
    let onDecrement: (Int) -> Void
    let onRemove: (Int) -> Void
    let onAdd: () -> Void
    let onClear: () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Composition")
                        .font(AppFont.cardTitle)
                        .foregroundStyle(AppColor.primaryText)
                    Spacer()
                    if !entries.isEmpty {
                        Button("Clear", action: onClear)
                            .font(.system(.footnote, weight: .medium))
                            .frame(minHeight: Theme.minimumTouchTarget)
                            .accessibilityIdentifier("build.clear")
                    }
                }

                if entries.isEmpty {
                    Text("Add elements to build a composition. Elemora then looks it up in its own catalog "
                         + "and in PubChem.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("build.empty")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider().overlay(AppColor.hairline)
                            }
                            row(entry)
                        }
                    }
                }

                Button(action: onAdd) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "plus.circle.fill")
                        Text(entries.isEmpty ? "Add an element" : "Add another element")
                    }
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(canAddElement ? AppColor.accent : AppColor.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .fill(AppColor.accent.opacity(canAddElement ? 0.10 : 0.04))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canAddElement)
                .accessibilityIdentifier("build.addElement")

                if !canAddElement {
                    Text("Up to \(CompoundBuilderModel.maximumDistinctElements) different elements "
                         + "in one composition.")
                        .font(AppFont.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("build.tray")
    }

    private func row(_ entry: CompoundBuilderModel.Entry) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ElementTile(element: entry.element, size: 44, density: .standard)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.element.name)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(AppColor.primaryText)
                Text(entry.element.category.displayName)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Theme.Spacing.s)

            stepButton("minus", label: "Remove one \(entry.element.name.lowercased())",
                       identifier: "build.decrement.\(entry.element.symbol)") {
                onDecrement(entry.element.atomicNumber)
            }
            Text("\(entry.count)")
                .font(.system(.title3, weight: .semibold).monospacedDigit())
                .foregroundStyle(AppColor.primaryText)
                .frame(minWidth: 28)
                .accessibilityLabel("\(entry.count) \(entry.element.name)")
                .accessibilityIdentifier("build.count.\(entry.element.symbol)")
            stepButton("plus", label: "Add one more \(entry.element.name.lowercased())",
                       identifier: "build.increment.\(entry.element.symbol)") {
                onIncrement(entry.element.atomicNumber)
            }
            Button {
                Haptics.tap()
                onRemove(entry.element.atomicNumber)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(AppColor.tertiaryText)
                    .frame(width: Theme.minimumTouchTarget, height: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(entry.element.name.lowercased())")
            .accessibilityIdentifier("build.remove.\(entry.element.symbol)")
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private func stepButton(_ symbol: String, label: String, identifier: String,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColor.accent)
                .frame(width: 36, height: 36)
                .background { Circle().fill(AppColor.accent.opacity(0.12)) }
                .frame(width: Theme.minimumTouchTarget, height: Theme.minimumTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// Picks one element for the tray: the full catalog, searchable by name,
/// symbol or number.
struct ElementPickerSheet: View {
    let catalog: ElementCatalog
    let onPick: (ChemicalElement) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [ChemicalElement] {
        query.isEmpty ? catalog.elements : catalog.search(query, limit: 118)
    }

    var body: some View {
        NavigationStack {
            List(results) { element in
                Button {
                    Haptics.tap()
                    onPick(element)
                    dismiss()
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        ElementTile(element: element, size: 40, density: .standard)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(element.name)
                                .font(.system(.body, weight: .medium))
                                .foregroundStyle(AppColor.primaryText)
                            Text("\(element.category.displayName) · Number \(element.atomicNumber)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(element.accessibilityDescription)
                .accessibilityIdentifier("build.pick.\(element.symbol)")
            }
            .listStyle(.plain)
            .scrollIndicators(.hidden)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Element, symbol, or number")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("Add an element")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("build.pickerCancel")
                }
            }
        }
        .tint(AppColor.accent)
        .presentationDetents([.large])
    }
}
