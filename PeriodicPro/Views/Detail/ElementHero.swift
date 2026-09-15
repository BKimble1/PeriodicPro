import SwiftUI

/// The large element card the tile expands into. Its shape, corner style and
/// fill deliberately mirror `ElementTile` so the zoom transition reads as one
/// continuous object growing rather than two views cross-fading.
struct ElementHero: View {
    let element: ChemicalElement
    var size: CGFloat = 196

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            card
            VStack(spacing: Theme.Spacing.s) {
                CategoryBadge(category: element.category)
                Text(element.tagline)
                    .font(.system(.title3, weight: .medium))
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.s)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var cornerRadius: CGFloat { ElementTileShape.cornerRadius(for: size) }

    private var card: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(element.category.heroGradient)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(element.category.accentColor.opacity(0.16), lineWidth: 1)

            VStack(spacing: 0) {
                Text("\(element.atomicNumber)")
                    .font(.system(size: size * 0.115, weight: .medium).monospacedDigit())
                    .foregroundStyle(element.category.onTileColor.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                Text(element.symbol)
                    .font(AppFont.heroSymbol(size * 0.40))
                    .foregroundStyle(element.category.onTileColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text(element.name)
                    .font(.system(size: size * 0.105, weight: .medium))
                    .foregroundStyle(element.category.onTileColor.opacity(0.85))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(element.formattedAtomicMass)
                    .font(.system(size: size * 0.072, weight: .regular).monospacedDigit())
                    .foregroundStyle(element.category.onTileColor.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(size * 0.11)
        }
        .frame(width: size, height: size)
        .themeShadow(Theme.Shadow.raised)
        // Attached to the card, and after the shadow.
        //
        // A `.background` takes no part in its host's layout, so however large
        // the artwork draws, the card keeps its exact square and the zoom
        // transition still lands on it. After the shadow, because a shadow is
        // cast from the composited alpha of everything above it in the chain —
        // artwork inside that subtree would turn a crisp card shadow into a
        // halo.
        .background { ElementHeroArtwork(element: element, heroSize: size) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(element.accessibilityDescription)
        .accessibilityIdentifier("detail.hero")
    }
}
