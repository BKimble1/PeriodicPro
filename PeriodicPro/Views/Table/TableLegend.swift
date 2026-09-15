import SwiftUI

/// Compact color key for the ten element families.
///
/// Deliberately not interactive. Filtering already has two routes — the chip
/// row above the table and the family sheet behind it — and making the key a
/// third would either duplicate them or force every row to a 44-point target,
/// turning a 140-point key into a 220-point one that dominates the screen.
struct TableLegend: View {
    let catalog: ElementCatalog

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Two columns normally; one once "Alkaline Earth" can no longer share
    /// ~130 points with a swatch without being scaled down and truncated.
    private var columns: [GridItem] {
        let item = GridItem(.flexible(), spacing: Theme.Spacing.m, alignment: .leading)
        return dynamicTypeSize >= .xxLarge ? [item] : [item, item]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Families")
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColor.secondaryText)
                .textCase(.uppercase)
                .kerning(0.5)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(ElementCategory.displayOrder) { category in
                    key(category)
                }
            }
        }
    }

    private func key(_ category: ElementCategory) -> some View {
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
                .foregroundStyle(AppColor.secondaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.pluralName), \(catalog.count(of: category)) elements")
    }
}
