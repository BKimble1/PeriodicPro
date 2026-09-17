import SwiftUI

/// The ten element families: the color key, and the app's only detailed
/// filter.
///
/// Each row is a control. Tapping one narrows the table to that family;
/// tapping a second adds it, because `ElementFilter` already carries a set.
/// Tapping a selected row removes it, and removing the last one returns the
/// table to whatever the primary row above it says — All, or the broad family
/// the learner chose there.
///
/// This replaces the old filter sheet entirely. There is one detailed filtering
/// surface, it is visible, and the state it sets is shown on the rows that set
/// it rather than summarized in a chip somewhere else.
struct TableLegend: View {
    let catalog: ElementCatalog
    @Binding var filter: ElementFilter

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Two columns normally; one once "Alkaline Earth" can no longer share
    /// ~130 points with a swatch without being scaled down and truncated.
    private var columns: [GridItem] {
        let item = GridItem(.flexible(), spacing: Theme.Spacing.s, alignment: .leading)
        return dynamicTypeSize >= .xxLarge ? [item] : [item, item]
    }

    private var hasDetailedSelection: Bool { !filter.categories.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                Text("Families")
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.secondaryText)
                    .textCase(.uppercase)
                    .kerning(0.5)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if hasDetailedSelection {
                    Button("Clear") {
                        Haptics.tap()
                        withAnimation(Theme.Motion.soft) {
                            filter = ElementFilter(family: filter.family, categories: [])
                        }
                    }
                    .font(.system(.footnote, weight: .medium))
                    .accessibilityIdentifier("legend.clear")
                }
            }

            Text(hasDetailedSelection
                 ? "Showing \(filter.summary.lowercased())."
                 : "Tap a family to filter the table. Tap more than one to combine them.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("legend.hint")

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(ElementCategory.displayOrder) { category in
                    row(category)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.families")
    }

    private func row(_ category: ElementCategory) -> some View {
        let isSelected = filter.categories.contains(category)
        return Button {
            Haptics.tap()
            withAnimation(Theme.Motion.soft) { toggle(category) }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(category.tileFill)
                        .frame(width: 18, height: 18)
                    // Large enough that the shape, not just the color, is the
                    // thing the learner reads.
                    Image(systemName: category.glyph)
                        .font(.system(size: 9))
                        .foregroundStyle(category.accentColor)
                }
                Text(category.shortName)
                    .font(AppFont.caption)
                    .foregroundStyle(isSelected ? AppColor.primaryText : AppColor.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColor.accent)
                }
            }
            .padding(.horizontal, Theme.Spacing.s)
            // A generous row rather than a 26-point line of text: this is the
            // only detailed filter in the app and it has to be tappable.
            .frame(minHeight: Theme.minimumTouchTarget, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? AppColor.accent.opacity(0.10) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? AppColor.accent.opacity(0.45) : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.pluralName), \(catalog.count(of: category)) elements")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("legend.\(category.rawValue)")
    }

    /// Adds or removes one family. The broad family chosen above is preserved
    /// so that clearing the last detailed family returns to it rather than to
    /// everything — `ElementFilter.matches` already prefers the set when it is
    /// not empty.
    private func toggle(_ category: ElementCategory) {
        var categories = filter.categories
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
        filter = ElementFilter(family: filter.family, categories: categories)
    }
}
