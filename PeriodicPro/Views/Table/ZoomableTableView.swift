import SwiftUI

/// Scroll geometry kept outside SwiftUI's state.
///
/// The scroll callback fires on every frame of a pan. Writing that into
/// `@State` would re-evaluate the screen — and with it the 118-tile grid —
/// sixty times a second while the learner merely scrolls. A plain reference
/// type is written on every frame and read only when a pinch begins, a double
/// tap lands, or the view goes away; none of those reads is a view update.
@MainActor
final class TableScrollTracker {
    var offset: CGPoint = .zero
    var contentSize: CGSize = .zero
    var viewportSize: CGSize = .zero
}

/// The periodic table as something to pinch, like a photo.
///
/// A two-axis `ScrollView` whose content is the real table laid out at the
/// current zoom — the tiles physically grow, the text is set at the new size,
/// and the scrollable area is the table's true extent. Nothing here is a
/// `scaleEffect` over a static picture.
///
/// The pinch keeps the content under the fingers where it is: the offset for
/// each new zoom is computed by `TableZoomLayout.offsetPreservingFocus` and
/// applied through `ScrollPosition`, so zooming in on oxygen leaves oxygen
/// under the thumb rather than sliding the table to its top-left corner.
///
/// Zoom and scroll position are owned by the screen, not by this view, so
/// they survive a search (which replaces this view with the results list) and
/// a push to an element's detail page.
struct ZoomableTableView: View {
    let catalog: ElementCatalog
    let filter: ElementFilter
    let namespace: Namespace.ID
    /// The width the table lays out in — the safe width of the screen.
    let viewportWidth: CGFloat
    /// The height of the screen, which bounds how tall the zoomed window gets.
    let screenHeight: CGFloat
    @Binding var zoom: CGFloat
    @Binding var position: ScrollPosition
    /// Where the table was scrolled to when it last went off screen.
    @Binding var savedOffset: CGPoint
    /// True while two fingers are down. The screen disables its own vertical
    /// scrolling for the duration, so a pinch never also scrolls the page.
    @Binding var isPinching: Bool
    /// Set by the screen's zoom menu; performed here, where the scroll
    /// geometry is known, and cleared once done.
    @Binding var command: ZoomCommand?
    let isFavorite: (Int) -> Bool
    let mastery: (Int) -> MasteryLevel
    let onSelect: (ChemicalElement) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tracker = TableScrollTracker()
    @State private var pinchStartZoom: CGFloat?
    @State private var pinchStartOffset: CGPoint = .zero
    @State private var pinchStartContent: CGSize = .zero
    @State private var pinchFocus: CGPoint = .zero
    /// The table's height at fitted zoom, measured once the layout settles.
    @State private var fittedContentHeight: CGFloat?

    /// The named space the grid reports double-tap locations in: the content
    /// of the scroll view, which is the space scroll offsets are measured in.
    static let contentSpace = "periodicTable.zoomContent"

    private var fittedTile: CGFloat { TableZoomLayout.fittedTileSize(viewportWidth: viewportWidth) }
    private var tileSize: CGFloat { TableZoomLayout.tileSize(fitted: fittedTile, zoom: zoom) }
    private var spacing: CGFloat { TableZoomLayout.spacing(forTileSize: tileSize) }
    private var isZoomed: Bool { zoom >= TableZoomLayout.zoomedThreshold }

    /// Until the first layout reports the real height: seven main rows, the
    /// gap beneath them, two captions and two detached rows.
    private var estimatedFittedHeight: CGFloat {
        let step = fittedTile + TableZoomLayout.fittedSpacing
        return step * 9 + max(Theme.Spacing.s, fittedTile * 0.45) + 2 * 16 + Theme.Spacing.m * 2 + 8
    }

    private func viewportHeight(at zoom: CGFloat) -> CGFloat {
        TableZoomLayout.viewportHeight(
            fittedHeight: fittedContentHeight ?? estimatedFittedHeight,
            expandedHeight: screenHeight * 0.62,
            zoom: zoom
        )
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            PeriodicTableGrid(
                catalog: catalog,
                filter: filter,
                tileSize: tileSize,
                spacing: spacing,
                density: TableZoomLayout.density(forTileSize: tileSize),
                namespace: namespace,
                isFavorite: isFavorite,
                mastery: mastery,
                showsMastery: TableZoomLayout.showsBadges(forTileSize: tileSize),
                onSelect: onSelect,
                onDoubleTap: toggleZoom
            )
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            // At fitted zoom the content is exactly the viewport wide, so
            // nothing scrolls sideways and the grid sits centered.
            .frame(minWidth: viewportWidth)
            .coordinateSpace(.named(Self.contentSpace))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                if abs(zoom - 1) < 0.001 { fittedContentHeight = height }
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        .onScrollGeometryChange(for: ScrollGeometry.self) { geometry in
            geometry
        } action: { _, geometry in
            tracker.offset = geometry.contentOffset
            tracker.contentSize = geometry.contentSize
            tracker.viewportSize = geometry.containerSize
        }
        .frame(height: viewportHeight(at: zoom))
        .simultaneousGesture(magnifyGesture)
        .overlay(alignment: .topTrailing) { fitChip }
        .task { restore() }
        .onChange(of: command) { _, command in
            guard let command else { return }
            perform(command)
            self.command = nil
        }
        .onDisappear { savedOffset = tracker.offset }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.zoomView")
    }

    // MARK: - Pinch

    private var magnifyGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                let startZoom: CGFloat
                if let pinchStartZoom {
                    startZoom = pinchStartZoom
                } else {
                    // The baseline is taken once, at the first change, from
                    // where the table actually is — offset included.
                    startZoom = zoom
                    pinchStartZoom = zoom
                    pinchStartOffset = tracker.offset
                    pinchStartContent = tracker.contentSize
                    pinchFocus = value.startLocation
                    isPinching = true
                }
                let target = TableZoomLayout.clampZoom(
                    startZoom * value.magnification, fittedTileSize: fittedTile
                )
                move(to: target, from: startZoom, startOffset: pinchStartOffset,
                     startContent: pinchStartContent, focus: pinchFocus, animated: false)
            }
            .onEnded { _ in
                pinchStartZoom = nil
                isPinching = false
                // A pinch that stops a hair above fitted snaps home, so the
                // table is never left three points too wide with slack to
                // scroll.
                if zoom > 1, zoom < TableZoomLayout.zoomedThreshold {
                    fit(animated: true)
                }
            }
    }

    /// Applies a zoom while keeping `focus` (a viewport point) over the same
    /// content. The new content size is estimated from the size at the start
    /// of the gesture so the offset can be clamped before the layout catches
    /// up.
    private func move(
        to target: CGFloat,
        from startZoom: CGFloat,
        startOffset: CGPoint,
        startContent: CGSize,
        focus: CGPoint,
        animated: Bool
    ) {
        let content = TableZoomLayout.scaledContentSize(startContent, from: startZoom, to: target)
        let viewport = CGSize(width: tracker.viewportSize.width, height: viewportHeight(at: target))
        let raw = TableZoomLayout.offsetPreservingFocus(
            startOffset: startOffset, startZoom: startZoom, newZoom: target, focus: focus
        )
        let offset = TableZoomLayout.clampOffset(raw, contentSize: content, viewportSize: viewport)
        let change = {
            zoom = target
            position.scrollTo(point: offset)
        }
        if animated, !reduceMotion {
            withAnimation(Theme.Motion.reveal, change)
        } else {
            change()
        }
    }

    // MARK: - Double tap, Fit, and the accessibility steps

    /// A double tap on empty table: fit if zoomed, otherwise 2× with the
    /// tapped point brought to the middle of the window.
    private func toggleZoom(at contentPoint: CGPoint) {
        Haptics.tap()
        if isZoomed {
            fit(animated: true)
            return
        }
        let target = TableZoomLayout.clampZoom(TableZoomLayout.doubleTapZoom, fittedTileSize: fittedTile)
        let scaled = CGPoint(x: contentPoint.x * target / zoom, y: contentPoint.y * target / zoom)
        let viewport = CGSize(width: tracker.viewportSize.width, height: viewportHeight(at: target))
        let content = TableZoomLayout.scaledContentSize(tracker.contentSize, from: zoom, to: target)
        let centered = TableZoomLayout.offsetCentering(contentPoint: scaled, viewportSize: viewport)
        let offset = TableZoomLayout.clampOffset(centered, contentSize: content, viewportSize: viewport)
        animate {
            zoom = target
            position.scrollTo(point: offset)
        }
    }

    private func perform(_ command: ZoomCommand) {
        switch command {
        case .fit: fit(animated: true)
        case .zoomIn: step(in: .zoomIn)
        case .zoomOut: step(in: .zoomOut)
        }
    }

    /// Back to every column on screen.
    private func fit(animated: Bool) {
        let change = {
            zoom = 1
            position.scrollTo(edge: .top)
        }
        if animated, !reduceMotion {
            withAnimation(Theme.Motion.reveal, change)
        } else {
            change()
        }
    }

    /// Zoom In / Zoom Out from the menu: one step about the window's middle.
    private func step(in direction: ZoomStep) {
        let factor = direction == .zoomIn ? TableZoomLayout.stepFactor : 1 / TableZoomLayout.stepFactor
        let target = TableZoomLayout.clampZoom(zoom * factor, fittedTileSize: fittedTile)
        if target <= 1 {
            fit(animated: true)
            return
        }
        let focus = CGPoint(x: tracker.viewportSize.width / 2, y: tracker.viewportSize.height / 2)
        move(to: target, from: zoom, startOffset: tracker.offset,
             startContent: tracker.contentSize, focus: focus, animated: true)
    }

    private func animate(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(Theme.Motion.reveal, change)
        }
    }

    /// Puts the table back where it was when it was last on screen — after a
    /// search, which replaces this view with the results list.
    private func restore() {
        guard isZoomed, savedOffset != .zero else { return }
        let target = savedOffset
        Task { @MainActor in
            // One frame, so the content has a size to scroll within.
            try? await Task.sleep(for: .milliseconds(32))
            position.scrollTo(point: target)
        }
    }

    @ViewBuilder
    private var fitChip: some View {
        if isZoomed {
            Button {
                Haptics.tap()
                fit(animated: true)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Fit")
                        .font(.system(.footnote, weight: .semibold))
                }
                .foregroundStyle(AppColor.primaryText)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(minHeight: 34)
                .background { Capsule().fill(.regularMaterial) }
                .overlay { Capsule().strokeBorder(AppColor.hairline, lineWidth: 0.7) }
                .contentShape(Capsule())
                // Padded inside the label so the whole 44-point target taps.
                .padding(Theme.Spacing.s)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fit the whole table on screen")
            .accessibilityIdentifier("table.fit")
            .transition(.opacity)
        }
    }
}

/// The two directions of the accessibility zoom menu.
enum ZoomStep: Hashable, Sendable {
    case zoomIn
    case zoomOut
}

/// What the screen's zoom menu asks the table to do. The menu exists for
/// anyone who cannot pinch — VoiceOver, Switch Control, a single finger — and
/// it reaches every zoom level the pinch can.
enum ZoomCommand: Hashable, Sendable {
    case fit
    case zoomIn
    case zoomOut
}
