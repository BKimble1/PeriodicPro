import SwiftUI

/// The decorative layer that sits around the expanded element hero.
///
/// Attached with `.background`, never a `ZStack`. A background does not take
/// part in its host's layout, so however large this draws, the hero card keeps
/// its exact 196-point square and the zoom transition still lands where the
/// table tile was. Three rules keep it decorative rather than distracting:
///
/// * it is masked to a clear core, so nothing is drawn under the symbol, the
///   atomic number or the name;
/// * it fades in *after* the zoom settles, so the shape the tile grows into is
///   the plain card the learner tapped and not a shower of decoration;
/// * it never exceeds `ElementArtworkProminence.hero` opacity.
struct ElementHeroArtwork: View {
    let element: ChemicalElement
    /// Matches `ElementHero`'s default card size. The artwork is drawn to a
    /// larger canvas so its forms break past the card's edges the way the
    /// reference concept does.
    var heroSize: CGFloat = 196

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    private var canvasSize: CGFloat { heroSize * 1.85 }

    var body: some View {
        ElementArtworkView(
            descriptor: ElementArtwork.descriptor(for: element),
            accent: element.category.accentColor,
            prominence: .hero
        )
        .frame(width: canvasSize, height: canvasSize)
        .mask {
            // Clear through the card's footprint, opaque outside it. This is
            // what guarantees the hero's text never has artwork behind it, and
            // it holds for every family color and both appearances without
            // needing a contrast measurement per element.
            RadialGradient(
                colors: [.clear, .clear, .black, .black],
                center: .center,
                startRadius: heroSize * 0.34,
                endRadius: heroSize * 0.92
            )
        }
        .opacity(isRevealed ? 1 : 0)
        .scaleEffect(isRevealed ? 1 : 0.9)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: reveal)
        .onChange(of: element.atomicNumber) { _, _ in
            // The same screen can be reused for a different element when the
            // learner navigates on; start the reveal again rather than showing
            // the new element's artwork already settled.
            isRevealed = false
            reveal()
        }
    }

    private func reveal() {
        guard !reduceMotion else {
            isRevealed = true
            return
        }
        withAnimation(.easeOut(duration: 0.55).delay(0.28)) {
            isRevealed = true
        }
    }
}

/// The same treatment at card scale, for the large favorite and study cards.
///
/// Quieter and blurred further than the hero version: on a card the artwork is
/// competing with a headline rather than with a 78-point symbol.
struct ElementCardArtwork: View {
    let element: ChemicalElement

    var body: some View {
        ElementArtworkView(
            descriptor: ElementArtwork.descriptor(for: element),
            accent: element.category.accentColor,
            prominence: .card
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
