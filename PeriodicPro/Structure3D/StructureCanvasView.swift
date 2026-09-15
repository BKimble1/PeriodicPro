import SwiftUI

/// A glossy ball-and-stick rendering of a structure, drawn with `Canvas`.
///
/// This is the lightweight renderer. It is what the detail page's structure card
/// shows and what the Identify mode uses as its clue, because both live inside
/// a scrolling view where standing up a full 3D scene per card would be wasteful.
/// The immersive explorer uses RealityKit instead; both read the same
/// `StructureScene`, so they can never disagree about what an element looks like.
///
/// Depth ordering is a painter's algorithm over a single list of atoms and
/// bonds, which is correct for ball-and-stick geometry where struts are shorter
/// than the spheres they join.
struct StructureCanvasView: View {
    let scene: StructureScene
    var atomColor: Color
    var bondColor: Color
    /// Identify mode passes `false`: there, the structure is the question, and
    /// a family-colored model would answer it.
    var usesElementColor: Bool = true
    var yaw: Double = 0.6
    var pitch: Double = 0.35
    var zoom: Double = 1
    /// Highlighted node, drawn bright while everything else dims.
    var selection: StructureSelection = .none

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let projection = StructureProjection(yaw: yaw, pitch: pitch, zoom: zoom, size: size)
            for item in StructureDrawList.items(scene: scene, projection: projection) {
                switch item.kind {
                case .bond(let bond):
                    draw(bond: bond, item: item, projection: projection, in: &context)
                case .node(let node):
                    draw(node: node, item: item, projection: projection, in: &context)
                }
            }
        }
        // No drawingGroup: Canvas already rasterizes efficiently, and an extra
        // offscreen render target per preview is a cost with no benefit here.
        .accessibilityHidden(true)
    }

    // MARK: - Drawing

    private func draw(
        node: StructureNode,
        item: StructureDrawList.Drawable,
        projection: StructureProjection,
        in context: inout GraphicsContext
    ) {
        let placed = item.from
        let radius = max(1.0, projection.radius(node.radius, scale: placed.scale))
        let rect = CGRect(
            x: placed.point.x - radius,
            y: placed.point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        let base = color(for: node)
        let isSelected = selection.nodeID == node.id
        let dim = !selection.isEmpty && !isSelected

        // Depth cue: things further away are slightly darker and softer, which
        // is what stops a flat circle from reading as a sticker.
        let depthShade = 0.72 + 0.28 * ((placed.depth + 1) / 2)
        let bodyOpacity = (dim ? 0.28 : 1.0) * depthShade

        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [
                    base.opacity(bodyOpacity),
                    base.opacity(bodyOpacity * 0.55),
                ]),
                center: CGPoint(x: rect.midX + radius * 0.1, y: rect.midY + radius * 0.16),
                startRadius: radius * 0.1,
                endRadius: radius * 1.15
            )
        )

        // Specular highlight, up and to the left, matching a single soft key
        // light. Same light direction for every sphere, which is what makes a
        // cluster read as one lit object.
        let highlightRadius = radius * 0.46
        let highlight = CGRect(
            x: rect.midX - radius * 0.34 - highlightRadius / 2,
            y: rect.midY - radius * 0.36 - highlightRadius / 2,
            width: highlightRadius,
            height: highlightRadius
        )
        context.fill(
            Path(ellipseIn: highlight),
            with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity((dim ? 0.18 : 0.85) * depthShade),
                    Color.white.opacity(0),
                ]),
                center: CGPoint(x: highlight.midX, y: highlight.midY),
                startRadius: 0,
                endRadius: highlightRadius
            )
        )

        if isSelected {
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: -radius * 0.14, dy: -radius * 0.14)),
                with: .color(AppColor.accent),
                lineWidth: max(1.5, radius * 0.14)
            )
        }
    }

    private func draw(
        bond: StructureBond,
        item: StructureDrawList.Drawable,
        projection: StructureProjection,
        in context: inout GraphicsContext
    ) {
        let dim = !selection.isEmpty && selection.bondID != bond.id
        let isSelected = selection.bondID == bond.id
        // Struts are sized as a fraction of the canvas, not in fixed points, so
        // the same scene reads correctly in a 140-point card and in a
        // full-screen explorer.
        let canvasBase = min(projection.size.width, projection.size.height)
        let perspective = (item.from.scale + item.to.scale) / 2
        let width = max(1.0, Double(canvasBase) * strutWidthFraction * perspective)

        // A double or triple bond is drawn as parallel struts, offset
        // perpendicular to the bond in screen space.
        let dx = item.to.point.x - item.from.point.x
        let dy = item.to.point.y - item.from.point.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.001 else { return }
        let nx = -dy / length
        let ny = dx / length

        let strutCount = bond.isDiscreteBond ? bond.order.rawValue : 1
        let spacing = width * 1.5
        let start = -Double(strutCount - 1) / 2

        var path = Path()
        for index in 0..<strutCount {
            let offset = (start + Double(index)) * spacing
            path.move(to: CGPoint(
                x: item.from.point.x + nx * offset,
                y: item.from.point.y + ny * offset
            ))
            path.addLine(to: CGPoint(
                x: item.to.point.x + nx * offset,
                y: item.to.point.y + ny * offset
            ))
        }

        context.stroke(
            path,
            with: .color(isSelected ? AppColor.accent : bondColor.opacity(dim ? 0.18 : 0.75)),
            style: StrokeStyle(lineWidth: width, lineCap: .round)
        )
    }

    private var strutWidthFraction: Double {
        switch scene.kind {
        case .atomModel: return 0
        // A contact line in a lattice is drawn thinner than a covalent bond,
        // so the two never read as the same thing.
        case .metallicLattice: return 0.013
        default: return 0.024
        }
    }

    private func color(for node: StructureNode) -> Color {
        switch node.role {
        case .atom:
            return usesElementColor ? atomColor : AppColor.secondaryText
        case .proton:
            return usesElementColor ? AppColor.warning : AppColor.secondaryText
        case .neutron:
            return AppColor.secondaryText
        case .electron:
            return usesElementColor ? AppColor.accent : AppColor.tertiaryText
        }
    }
}
