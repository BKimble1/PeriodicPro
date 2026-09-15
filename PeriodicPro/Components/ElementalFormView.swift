import SwiftUI

/// A small, honest diagram of how the *pure element* actually exists — a
/// diatomic molecule, a puckered ring, a metallic lattice, a covalent network
/// or separate atoms. Drawn with `Canvas` so no image assets are needed.
struct ElementalFormView: View {
    let element: ChemicalElement
    var size: CGSize = CGSize(width: 132, height: 96)

    private var tint: Color { element.category.accentColor }

    /// Reads the atom count out of the elemental-form label ("S₈" → 8) so the
    /// drawing always matches the text beside it. `nil` when the label carries
    /// no subscript at all, which means the form is not a fixed-size molecule
    /// (selenium's "helical chains", for instance).
    private var atomCount: Int? {
        let subscripts: [Character: Int] = [
            "\u{2080}": 0, "\u{2081}": 1, "\u{2082}": 2, "\u{2083}": 3, "\u{2084}": 4,
            "\u{2085}": 5, "\u{2086}": 6, "\u{2087}": 7, "\u{2088}": 8, "\u{2089}": 9,
        ]
        var digits: [Int] = []
        for character in element.elementalForm {
            if let value = subscripts[character] {
                digits.append(value)
            } else if !digits.isEmpty {
                break
            }
        }
        guard !digits.isEmpty else { return element.structure == .diatomic ? 2 : nil }
        return digits.reduce(0) { $0 * 10 + $1 }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            switch element.structure {
            case .diatomic:
                drawChain(context: context, center: center, canvas: canvasSize,
                          count: atomCount ?? 2)
            case .polyatomicMolecule:
                if let atomCount {
                    drawRing(context: context, center: center, canvas: canvasSize,
                             count: max(3, min(atomCount, 8)))
                } else {
                    // No subscript means an open chain rather than a closed ring.
                    drawChain(context: context, center: center, canvas: canvasSize, count: 5)
                }
            case .metallicLattice:
                drawLattice(context: context, canvas: canvasSize)
            case .covalentNetwork:
                drawNetwork(context: context, canvas: canvasSize)
            case .monatomicGas, .atom:
                drawSeparateAtoms(context: context, canvas: canvasSize)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diagram of the elemental form: \(element.structure.displayName).")
    }

    // MARK: - Drawing primitives

    private func sphere(_ context: GraphicsContext, at point: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        context.fill(Circle().path(in: rect), with: .color(tint.opacity(0.9)))
        let highlight = CGRect(x: point.x - radius * 0.45, y: point.y - radius * 0.55,
                               width: radius * 0.6, height: radius * 0.6)
        context.fill(Circle().path(in: highlight), with: .color(.white.opacity(0.35)))
    }

    private func bond(_ context: GraphicsContext, from: CGPoint, to: CGPoint, width: CGFloat = 3) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(tint.opacity(0.4)), lineWidth: width)
    }

    private func drawChain(context: GraphicsContext, center: CGPoint, canvas: CGSize, count: Int) {
        let radius = min(canvas.height * 0.28, canvas.width / CGFloat(count * 3))
        let spacing = radius * 2.35
        let totalWidth = spacing * CGFloat(count - 1)
        var points: [CGPoint] = []
        for index in 0..<count {
            points.append(CGPoint(x: center.x - totalWidth / 2 + spacing * CGFloat(index), y: center.y))
        }
        for index in 0..<(points.count - 1) {
            bond(context, from: points[index], to: points[index + 1], width: radius * 0.5)
        }
        points.forEach { sphere(context, at: $0, radius: radius) }
    }

    private func drawRing(context: GraphicsContext, center: CGPoint, canvas: CGSize, count: Int) {
        let ringRadius = min(canvas.width, canvas.height) * 0.33
        let atomRadius = max(4, ringRadius * 0.9 / CGFloat(count))
        var points: [CGPoint] = []
        for index in 0..<count {
            let angle = (Double(index) / Double(count)) * 2 * .pi - .pi / 2
            points.append(CGPoint(
                x: center.x + ringRadius * CGFloat(cos(angle)),
                y: center.y + ringRadius * CGFloat(sin(angle)) * 0.82
            ))
        }
        for index in 0..<count {
            bond(context, from: points[index], to: points[(index + 1) % count], width: atomRadius * 0.45)
        }
        points.forEach { sphere(context, at: $0, radius: atomRadius) }
    }

    private func drawLattice(context: GraphicsContext, canvas: CGSize) {
        let columns = 4
        let rows = 3
        let spacingX = canvas.width / CGFloat(columns + 1)
        let spacingY = canvas.height / CGFloat(rows + 1)
        let atomRadius = min(spacingX, spacingY) * 0.30

        var points: [[CGPoint]] = []
        for row in 0..<rows {
            var line: [CGPoint] = []
            let inset = row.isMultiple(of: 2) ? 0 : spacingX * 0.5
            for column in 0..<columns {
                line.append(CGPoint(
                    x: spacingX * CGFloat(column + 1) + inset - spacingX * 0.25,
                    y: spacingY * CGFloat(row + 1)
                ))
            }
            points.append(line)
        }
        for row in 0..<rows {
            for column in 0..<columns {
                if column < columns - 1 {
                    bond(context, from: points[row][column], to: points[row][column + 1], width: 1.6)
                }
                if row < rows - 1 {
                    bond(context, from: points[row][column], to: points[row + 1][column], width: 1.6)
                }
            }
        }
        for line in points {
            line.forEach { sphere(context, at: $0, radius: atomRadius) }
        }
    }

    private func drawNetwork(context: GraphicsContext, canvas: CGSize) {
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let ringRadius = min(canvas.width, canvas.height) * 0.30
        let atomRadius = ringRadius * 0.21

        var points: [CGPoint] = []
        for index in 0..<6 {
            let angle = (Double(index) / 6.0) * 2 * .pi - .pi / 2
            points.append(CGPoint(
                x: center.x + ringRadius * CGFloat(cos(angle)),
                y: center.y + ringRadius * CGFloat(sin(angle))
            ))
        }
        for index in 0..<6 {
            bond(context, from: points[index], to: points[(index + 1) % 6], width: 2)
        }
        // Stubs outward, suggesting a structure that continues past the frame.
        for index in 0..<6 where index.isMultiple(of: 2) {
            let point = points[index]
            let outward = CGPoint(
                x: point.x + (point.x - center.x) * 0.55,
                y: point.y + (point.y - center.y) * 0.55
            )
            bond(context, from: point, to: outward, width: 1.6)
        }
        points.forEach { sphere(context, at: $0, radius: atomRadius) }
    }

    private func drawSeparateAtoms(context: GraphicsContext, canvas: CGSize) {
        let radius = min(canvas.width, canvas.height) * 0.14
        let positions: [CGPoint] = [
            CGPoint(x: canvas.width * 0.30, y: canvas.height * 0.34),
            CGPoint(x: canvas.width * 0.70, y: canvas.height * 0.28),
            CGPoint(x: canvas.width * 0.50, y: canvas.height * 0.68),
            CGPoint(x: canvas.width * 0.18, y: canvas.height * 0.74),
        ]
        for (index, point) in positions.enumerated() {
            sphere(context, at: point, radius: index == 0 ? radius : radius * 0.72)
        }
    }
}
