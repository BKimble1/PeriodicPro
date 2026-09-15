import SwiftUI

/// The single most reused view in the app: one element rendered as a rounded
/// tile. It scales from a 17-point cell in the fitted periodic table up to a
/// 68-point card in the favorites carousel.
struct ElementTile: View {
    enum Density {
        /// Symbol only. Used when the whole table has to fit the screen width.
        case minimal
        /// Atomic number + symbol.
        case standard
        /// Atomic number + symbol + name.
        case detailed
    }

    let element: ChemicalElement
    var size: CGFloat
    var density: Density = .standard
    var isDimmed: Bool = false
    var isFavorite: Bool = false
    var mastery: MasteryLevel = .notStarted
    var showsMastery: Bool = false

    private var cornerRadius: CGFloat { ElementTileShape.cornerRadius(for: size) }

    private var symbolSize: CGFloat {
        switch density {
        case .minimal: return size * 0.46
        case .standard: return size * 0.40
        case .detailed: return size * 0.36
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(element.category.tileFill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(element.category.accentColor.opacity(0.18), lineWidth: 0.5)
                }

            content
                .padding(.horizontal, size * 0.06)
        }
        .frame(width: size, height: size)
        .opacity(isDimmed ? 0.22 : 1)
        .saturation(isDimmed ? 0.15 : 1)
        .overlay(alignment: .topTrailing) { badges }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        switch density {
        case .minimal:
            Text(element.symbol)
                .font(AppFont.tileSymbol(symbolSize))
                .foregroundStyle(element.category.onTileColor)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
        case .standard:
            VStack(spacing: size * 0.02) {
                Text("\(element.atomicNumber)")
                    .font(AppFont.tileNumber(size * 0.22))
                    .foregroundStyle(element.category.onTileColor)
                Text(element.symbol)
                    .font(AppFont.tileSymbol(symbolSize))
                    .foregroundStyle(element.category.onTileColor)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
            }
        case .detailed:
            VStack(spacing: size * 0.02) {
                Text("\(element.atomicNumber)")
                    .font(AppFont.tileNumber(size * 0.17))
                    .foregroundStyle(element.category.onTileColor)
                Text(element.symbol)
                    .font(AppFont.tileSymbol(symbolSize))
                    .foregroundStyle(element.category.onTileColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(element.name)
                    .font(AppFont.tileNumber(size * 0.15))
                    .foregroundStyle(element.category.onTileColor.opacity(0.88))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
    }

    /// At most one badge. Two side by side are wide enough to reach back into
    /// the atomic number's box on a 68-point tile, and a favorite the learner
    /// chose matters more than a mastery state they can see on Progress.
    @ViewBuilder
    private var badges: some View {
        if isFavorite {
            badge("heart.fill", tint: element.category.accentColor, bold: false)
        } else if showsMastery, mastery == .mastered {
            badge("checkmark", tint: AppColor.positive, bold: true)
        }
    }

    private func badge(_ symbolName: String, tint: Color, bold: Bool) -> some View {
        Image(systemName: symbolName)
            .font(.system(size: max(6, size * 0.16), weight: bold ? .bold : .regular))
            .foregroundStyle(tint)
            .padding(max(1.5, size * 0.055))
            .opacity(isDimmed ? 0 : 1)
            .allowsHitTesting(false)
    }

    private var accessibilityLabel: String {
        var label = element.accessibilityDescription
        if isFavorite { label += ", favorite" }
        if showsMastery, mastery != .notStarted { label += ", \(mastery.displayName)" }
        return label
    }
}

/// The one place the element-tile silhouette is defined.
///
/// `ElementHero` uses the same ratio, so the native zoom transition grows one
/// continuous shape instead of morphing between two different roundings.
enum ElementTileShape {
    static func cornerRadius(for size: CGFloat) -> CGFloat {
        max(Theme.Radius.tile, size * 0.22)
    }
}

/// Press feedback for every element tile: a small, quick, spring-damped push.
struct ElementTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.88 : 1))
            .animation(Theme.Motion.tap, value: configuration.isPressed)
    }
}
