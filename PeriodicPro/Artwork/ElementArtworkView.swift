import SwiftUI

/// Draws an element's decorative artwork.
///
/// Everything is procedural `Canvas` work — gradients, arcs and polygons —
/// seeded from the element's atomic number so a given element always looks the
/// same. There are no image assets and nothing is fetched, which is what keeps
/// the app fully offline.
///
/// This is decoration. It is drawn behind or beside the content it accompanies,
/// never underneath text that has no opaque backing, and it is hidden from
/// VoiceOver by its host — the description lives on the hero's own label.
struct ElementArtworkView: View {
    let descriptor: ElementArtworkDescriptor
    /// The element's family accent, used whenever the descriptor has no color
    /// of its own. Passed in rather than derived so this view stays a pure
    /// function of its inputs.
    let accent: Color
    var prominence: ElementArtworkProminence = .hero

    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        guard let hex = descriptor.tintHex else { return accent }
        var red = Double((hex >> 16) & 0xFF) / 255
        var green = Double((hex >> 8) & 0xFF) / 255
        var blue = Double(hex & 0xFF) / 255

        // The named tints are the colors these elements actually are, which
        // makes several of them dark: graphite carbon is 0x3A4048. On a
        // near-black canvas at a quarter opacity that is invisible, so a dark
        // tint is lifted toward white in dark mode. Light tints are left alone.
        if colorScheme == .dark {
            let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
            if luminance < 0.45 {
                let lift = 0.55
                red += (1 - red) * lift
                green += (1 - green) * lift
                blue += (1 - blue) * lift
            }
        }
        return Color(red: red, green: green, blue: blue)
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            var layout = ArtworkLayout(seed: descriptor.seed, size: size)
            let forms = layout.forms(count: descriptor.formCount, kind: descriptor.kind)
            for form in forms {
                draw(form, kind: descriptor.kind, in: &context)
            }
        }
        .blur(radius: prominence.blurRadius)
        .opacity(prominence.opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    private func draw(_ form: ArtworkForm, kind: ElementArtworkKind, in context: inout GraphicsContext) {
        switch kind {
        case .nuggets:
            fill(roundedBlob(form), form: form, in: &context, glossiness: 0.85)
        case .facetedGems:
            fill(polygon(form, sides: 6, twist: 0.18), form: form, in: &context, glossiness: 0.95)
        case .lattice:
            drawLatticeNode(form, in: &context)
        case .pairedSpheres:
            drawPair(form, in: &context)
        case .droplets:
            fill(Path(ellipseIn: form.rect), form: form, in: &context, glossiness: 1.0)
        case .crystalShards:
            fill(shard(form), form: form, in: &context, glossiness: 0.7)
        case .luminousGas:
            drawGlow(form, in: &context)
        case .metallicSheen:
            fill(sheet(form), form: form, in: &context, glossiness: 0.6)
        case .hexPlates:
            fill(polygon(form, sides: 6, twist: 0), form: form, in: &context, glossiness: 0.45)
        case .orbitalArcs:
            drawArc(form, in: &context)
        }
    }

    /// The shared "glossy solid" fill: a diagonal body gradient plus a small
    /// off-center specular bloom. It is what makes a flat shape read as a lit
    /// object rather than a colored blob.
    private func fill(
        _ path: Path,
        form: ArtworkForm,
        in context: inout GraphicsContext,
        glossiness: Double
    ) {
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    tint.opacity(0.95),
                    tint.opacity(0.45),
                ]),
                startPoint: CGPoint(x: form.rect.minX, y: form.rect.minY),
                endPoint: CGPoint(x: form.rect.maxX, y: form.rect.maxY)
            )
        )

        let highlight = form.rect.insetBy(
            dx: form.rect.width * 0.28,
            dy: form.rect.height * 0.28
        )
        .offsetBy(dx: -form.rect.width * 0.12, dy: -form.rect.height * 0.14)

        context.fill(
            Path(ellipseIn: highlight),
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.9 * glossiness),
                    Color.white.opacity(0),
                ]),
                center: CGPoint(x: highlight.midX, y: highlight.midY),
                startRadius: 0,
                endRadius: max(highlight.width, highlight.height) * 0.7
            )
        )
    }

    private func drawPair(_ form: ArtworkForm, in context: inout GraphicsContext) {
        // Two overlapping spheres: the shape of a diatomic molecule, without
        // pretending to be a measured bond length.
        let r = form.rect.width * 0.46
        let offset = r * 0.78
        for sign in [-1.0, 1.0] {
            let center = CGPoint(x: form.rect.midX + offset * sign, y: form.rect.midY)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            fill(
                Path(ellipseIn: rect),
                form: ArtworkForm(rect: rect, rotation: form.rotation, scale: form.scale),
                in: &context,
                glossiness: 1.0
            )
        }
    }

    private func drawLatticeNode(_ form: ArtworkForm, in context: inout GraphicsContext) {
        // A node plus the two struts leaving it. Drawn per form rather than as
        // one connected graph so the density stays even at any canvas size.
        let r = form.rect.width * 0.22
        let center = CGPoint(x: form.rect.midX, y: form.rect.midY)

        var struts = Path()
        for step in 0..<2 {
            let angle = form.rotation + Double(step) * .pi / 2.4
            struts.move(to: center)
            struts.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * form.rect.width * 0.55,
                y: center.y + CGFloat(sin(angle)) * form.rect.width * 0.55
            ))
        }
        context.stroke(struts, with: .color(tint.opacity(0.5)), lineWidth: max(1, r * 0.22))

        let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        fill(
            Path(ellipseIn: rect),
            form: ArtworkForm(rect: rect, rotation: form.rotation, scale: form.scale),
            in: &context,
            glossiness: 0.9
        )
    }

    private func drawGlow(_ form: ArtworkForm, in context: inout GraphicsContext) {
        context.fill(
            Path(ellipseIn: form.rect),
            with: .radialGradient(
                Gradient(colors: [
                    tint.opacity(0.85),
                    tint.opacity(0.25),
                    tint.opacity(0),
                ]),
                center: CGPoint(x: form.rect.midX, y: form.rect.midY),
                startRadius: 0,
                endRadius: form.rect.width * 0.5
            )
        )
    }

    private func drawArc(_ form: ArtworkForm, in context: inout GraphicsContext) {
        var path = Path()
        path.addArc(
            center: CGPoint(x: form.rect.midX, y: form.rect.midY),
            radius: form.rect.width * 0.5,
            startAngle: .radians(form.rotation),
            endAngle: .radians(form.rotation + 2.2),
            clockwise: false
        )
        context.stroke(
            path,
            with: .linearGradient(
                Gradient(colors: [tint.opacity(0.9), tint.opacity(0.1)]),
                startPoint: CGPoint(x: form.rect.minX, y: form.rect.minY),
                endPoint: CGPoint(x: form.rect.maxX, y: form.rect.maxY)
            ),
            style: StrokeStyle(lineWidth: max(1.5, form.rect.width * 0.045), lineCap: .round)
        )
    }

    // MARK: - Shapes

    private func roundedBlob(_ form: ArtworkForm) -> Path {
        // A hexagon with generous corner rounding reads as a worn nugget, and
        // costs one path instead of a spline.
        RoundedRectangle(cornerRadius: form.rect.width * 0.38, style: .continuous)
            .path(in: form.rect)
            .rotated(by: form.rotation, around: CGPoint(x: form.rect.midX, y: form.rect.midY))
    }

    private func polygon(_ form: ArtworkForm, sides: Int, twist: Double) -> Path {
        var path = Path()
        let center = CGPoint(x: form.rect.midX, y: form.rect.midY)
        let radius = form.rect.width * 0.5
        for index in 0..<sides {
            let angle = form.rotation + twist + Double(index) / Double(sides) * 2 * .pi
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func shard(_ form: ArtworkForm) -> Path {
        var path = Path()
        let center = CGPoint(x: form.rect.midX, y: form.rect.midY)
        let radius = form.rect.width * 0.5
        // Alternating long and short radii give the jagged profile of a
        // crystal cluster rather than a regular polygon.
        for index in 0..<6 {
            let angle = form.rotation + Double(index) / 6 * 2 * .pi
            let reach = index.isMultiple(of: 2) ? radius : radius * 0.52
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * reach,
                y: center.y + CGFloat(sin(angle)) * reach
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func sheet(_ form: ArtworkForm) -> Path {
        RoundedRectangle(cornerRadius: form.rect.height * 0.5, style: .continuous)
            .path(in: CGRect(
                x: form.rect.minX,
                y: form.rect.midY - form.rect.height * 0.16,
                width: form.rect.width,
                height: form.rect.height * 0.32
            ))
            .rotated(by: form.rotation, around: CGPoint(x: form.rect.midX, y: form.rect.midY))
    }
}

// MARK: - Layout

/// One placed form: where it sits, how big it is and how it is turned.
struct ArtworkForm {
    let rect: CGRect
    let rotation: Double
    let scale: Double
}

/// Scatters forms across the canvas from a fixed seed.
///
/// Forms are placed to the left and right of the middle rather than evenly
/// around it. The middle is where the hero card sits, and above and below it
/// are the family badge and the tagline, neither of which has an opaque
/// backing — so the only place decoration can go without competing with text
/// is beside the card, which is also where the reference concept puts it.
struct ArtworkLayout {
    private var generator: SeededGenerator
    private let size: CGSize

    init(seed: UInt64, size: CGSize) {
        self.generator = SeededGenerator(seed: seed)
        self.size = size
    }

    mutating func forms(count: Int, kind: ElementArtworkKind) -> [ArtworkForm] {
        guard size.width > 0, size.height > 0, count > 0 else { return [] }

        let base = min(size.width, size.height)
        return (0..<count).map { index in
            // Small: these are nuggets and shards scattered beside the card, not
            // a wash behind it. At 0.3 of the canvas they merged into one blob.
            let scale = unit(0.14, 0.26)
            let side = base * CGFloat(scale)

            // Alternating sides, fanned within three quarters of a radian of
            // horizontal, far enough out that the mask's clear core does not
            // swallow them, and near enough in that the largest form still
            // clears the canvas edge rather than being sliced by it.
            let axis: Double = index.isMultiple(of: 2) ? 0 : .pi
            let fan = (Double(index / 2) / Double(max(1, count / 2)) - 0.4) * 1.5
            let angle = axis + fan + unit(-0.18, 0.18)
            let reach = unit(0.52, 0.78)
            let center = CGPoint(
                x: size.width * 0.5 + CGFloat(cos(angle) * reach) * size.width * 0.5,
                y: size.height * 0.5 + CGFloat(sin(angle) * reach) * size.height * 0.5
            )

            return ArtworkForm(
                rect: CGRect(
                    x: center.x - side / 2,
                    y: center.y - side / 2,
                    width: side,
                    height: side
                ),
                rotation: unit(0, 2 * .pi),
                scale: scale
            )
        }
    }

    private mutating func unit(_ lower: Double, _ upper: Double) -> Double {
        Double.random(in: lower...upper, using: &generator)
    }
}

extension Path {
    /// Rotates a path about a point. `Path.applying` takes a `CGAffineTransform`,
    /// which rotates about the origin, so the translation is applied either side.
    func rotated(by radians: Double, around point: CGPoint) -> Path {
        applying(
            CGAffineTransform(translationX: point.x, y: point.y)
                .rotated(by: CGFloat(radians))
                .translatedBy(x: -point.x, y: -point.y)
        )
    }
}
