import SwiftUI

/// The single most reused view in the app: one element rendered as a rounded
/// tile. It scales from a 19-point cell in the fitted periodic table up to a
/// 92-point card in the favorites carousel.
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

    private var cornerRadius: CGFloat {
        max(Theme.Radius.tile, size * 0.22)
    }

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
        .accessibilityAddTraits(.isButton)
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
                    .foregroundStyle(element.category.onTileColor.opacity(0.7))
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
                    .foregroundStyle(element.category.onTileColor.opacity(0.7))
                Text(element.symbol)
                    .font(AppFont.tileSymbol(symbolSize))
                    .foregroundStyle(element.category.onTileColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(element.name)
                    .font(AppFont.tileNumber(size * 0.15))
                    .foregroundStyle(element.category.onTileColor.opacity(0.75))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if isFavorite || (showsMastery && mastery == .mastered) {
            HStack(spacing: 1) {
                if showsMastery, mastery == .mastered {
                    Image(systemName: "checkmark")
                        .font(.system(size: max(6, size * 0.16), weight: .bold))
                        .foregroundStyle(AppColor.positive)
                }
                if isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: max(6, size * 0.16)))
                        .foregroundStyle(element.category.accentColor)
                }
            }
            .padding(max(1.5, size * 0.055))
            .opacity(isDimmed ? 0 : 1)
            .allowsHitTesting(false)
        }
    }

    private var accessibilityLabel: String {
        var label = element.accessibilityDescription
        if isFavorite { label += ", favorite" }
        if showsMastery, mastery != .notStarted { label += ", \(mastery.displayName)" }
        return label
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
