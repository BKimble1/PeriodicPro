import SwiftUI

/// A wrapping row of toggle chips for a multi-select set. Selection shows as
/// a filled chip with a checkmark, never as color alone.
struct ChipGrid<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Set<Item>
    let title: (Item) -> String
    var identifierPrefix = "chip"

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.s)],
                  alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(items, id: \.self) { item in
                let isOn = selection.contains(item)
                Button {
                    Haptics.tap()
                    if isOn { selection.remove(item) } else { selection.insert(item) }
                } label: {
                    HStack(spacing: 4) {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(title(item))
                            .font(.system(.footnote, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(isOn ? Color.white : AppColor.primaryText)
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 36)
                    .background {
                        Capsule(style: .continuous).fill(isOn ? AppColor.accent : AppColor.surfaceMuted)
                    }
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("\(identifierPrefix).\(String(describing: item))")
            }
        }
    }
}

/// Chooses the exact elements for a custom quiz.
struct ElementMultiPicker: View {
    let catalog: ElementCatalog
    @Binding var selection: [Int]

    @State private var query = ""

    private var results: [ChemicalElement] {
        query.isEmpty ? catalog.elements : catalog.search(query, limit: 118)
    }

    var body: some View {
        List(results) { element in
            let isOn = selection.contains(element.atomicNumber)
            Button {
                Haptics.tap()
                if isOn {
                    selection.removeAll { $0 == element.atomicNumber }
                } else if selection.count < QuizConfiguration.maximumCustomItems {
                    selection.append(element.atomicNumber)
                }
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    ElementTile(element: element, size: 40, density: .standard)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(element.name)
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(AppColor.primaryText)
                        Text(element.category.displayName)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    Spacer()
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? AppColor.accent : AppColor.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(element.accessibilityDescription)
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("quizSetup.pickElement.\(element.symbol)")
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Element, symbol, or number")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle("Elements (\(selection.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selection.isEmpty ? "Select all" : "Clear") {
                    Haptics.tap()
                    selection = selection.isEmpty ? catalog.elements.map(\.atomicNumber) : []
                }
                .accessibilityIdentifier("quizSetup.pickElement.toggleAll")
            }
        }
    }
}

/// Chooses the exact compounds for a custom quiz, from everything the device
/// knows: the bundled catalog and anything looked up or saved.
struct CompoundMultiPicker: View {
    let compounds: [ChemicalCompound]
    @Binding var selection: [String]

    @State private var query = ""

    private var results: [ChemicalCompound] {
        let askable = compounds.filter { !$0.isHypothetical }
        guard !query.isEmpty else { return askable.sorted { $0.preferredName < $1.preferredName } }
        return CompoundCatalog(compounds: askable).search(query, limit: 60)
    }

    var body: some View {
        List(results) { compound in
            let isOn = selection.contains(compound.id)
            Button {
                Haptics.tap()
                if isOn {
                    selection.removeAll { $0 == compound.id }
                } else if selection.count < QuizConfiguration.maximumCustomItems {
                    selection.append(compound.id)
                }
            } label: {
                HStack(spacing: Theme.Spacing.m) {
                    CompoundTile(formula: compound.formula, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compound.preferredName)
                            .font(.system(.body, weight: .medium))
                            .foregroundStyle(AppColor.primaryText)
                        Text(compound.displayFormula)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    Spacer()
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isOn ? AppColor.accent : AppColor.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(compound.accessibilityDescription)
            .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("quizSetup.pickCompound.\(compound.pubChemCID ?? 0)")
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Compound name or formula")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle("Compounds (\(selection.count))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selection.isEmpty ? "Select all" : "Clear") {
                    Haptics.tap()
                    selection = selection.isEmpty ? compounds.filter { !$0.isHypothetical }.map(\.id) : []
                }
                .accessibilityIdentifier("quizSetup.pickCompound.toggleAll")
            }
        }
    }
}
