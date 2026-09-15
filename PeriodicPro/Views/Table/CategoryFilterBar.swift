import SwiftUI

/// Primary filter chips plus the entry point to the full family list.
struct CategoryFilterBar: View {
    @Binding var filter: ElementFilter
    var onOpenDetailedFilters: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.s) {
                    chip(title: "All", isSelected: !filter.isActive) {
                        filter = .all
                    }
                    ForEach(ElementFamily.allCases) { family in
                        chip(
                            title: family.displayName,
                            isSelected: filter.family == family && filter.categories.isEmpty
                        ) {
                            if filter.family == family && filter.categories.isEmpty {
                                filter = .all
                            } else {
                                filter = ElementFilter(family: family, categories: [])
                            }
                        }
                    }
                    if !filter.categories.isEmpty {
                        chip(title: filter.summary, isSelected: true) {
                            filter = .all
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenMargin)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            Button(action: onOpenDetailedFilters) {
                Image(systemName: filter.categories.isEmpty
                      ? "line.3.horizontal.decrease.circle"
                      : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(filter.categories.isEmpty ? AppColor.secondaryText : AppColor.accent)
                    .frame(width: Theme.minimumTouchTarget, height: Theme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Filter by element family")
            .accessibilityIdentifier("table.filterButton")
            .padding(.trailing, Theme.Spacing.screenMargin - 12)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(Theme.Motion.soft) { action() }
        } label: {
            Text(title)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : AppColor.primaryText)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
                .frame(minHeight: 34)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? AppColor.accent : AppColor.surface)
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? .clear : AppColor.hairline, lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("filter.\(title.replacingOccurrences(of: " ", with: ""))")
    }
}

/// Full family picker presented as a sheet so the chip row stays short.
struct CategoryFilterSheet: View {
    @Binding var filter: ElementFilter
    let catalog: ElementCatalog
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ElementCategory.displayOrder) { category in
                        Button {
                            Haptics.tap()
                            toggle(category)
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: category.glyph)
                                    .font(.system(size: 10))
                                    .foregroundStyle(category.accentColor)
                                    .frame(width: 18)
                                Text(category.pluralName)
                                    .foregroundStyle(AppColor.primaryText)
                                Spacer()
                                Text("\(catalog.elements(in: category).count)")
                                    .font(AppFont.footnote.monospacedDigit())
                                    .foregroundStyle(AppColor.tertiaryText)
                                if filter.categories.contains(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppColor.accent)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                            }
                        }
                        .accessibilityIdentifier("filterSheet.\(category.rawValue)")
                    }
                } header: {
                    Text("Element Families")
                } footer: {
                    Text("Choosing one or more families replaces the Metals / Nonmetals / Metalloids chip.")
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        filter = .all
                    }
                    .disabled(!filter.isActive)
                    .accessibilityIdentifier("filterSheet.clear")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("filterSheet.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func toggle(_ category: ElementCategory) {
        var categories = filter.categories
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
        filter = ElementFilter(family: nil, categories: categories)
    }
}
