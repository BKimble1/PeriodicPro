import SwiftUI

/// The scroll geometry the pinch needs, rounded to whole points.
///
/// `onScrollGeometryChange` compares the value the closure returns and fires
/// whenever it differs. Returning the whole `ScrollGeometry` meant any
/// sub-pixel change — and several arrive while a layout settles — counted as a
/// new value, which is what produced "OnScrollGeometryChange Modifier tried to
/// update multiple times per frame" in the logs. Rounding collapses that churn
/// to the changes a finger can actually cause.
struct TableScrollSnapshot: Equatable, Sendable {
    let offset: CGPoint
    let contentSize: CGSize
    let viewportSize: CGSize

    init(offset: CGPoint, contentSize: CGSize, viewportSize: CGSize) {
        self.offset = CGPoint(x: offset.x.rounded(), y: offset.y.rounded())
        self.contentSize = CGSize(width: contentSize.width.rounded(), height: contentSize.height.rounded())
        self.viewportSize = CGSize(width: viewportSize.width.rounded(), height: viewportSize.height.rounded())
    }
}

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

    func apply(_ snapshot: TableScrollSnapshot) {
        offset = snapshot.offset
        contentSize = snapshot.contentSize
        viewportSize = snapshot.viewportSize
    }
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
/// There is no visible zoom control of any kind — no Fit button, no toolbar
/// menu. Pinch, drag and double tap are the whole interface, and the accessible
/// twin of the pinch is an invisible adjustable element plus named VoiceOver
/// actions, so a learner using VoiceOver reaches every zoom level without
/// anything appearing on screen for everybody else.
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
    let isFavorite: (Int) -> Bool
    let mastery: (Int) -> MasteryLevel
    let onSelect: (ChemicalElement) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tracker = TableScrollTracker()
    @State private var pinchStartZoom: CGFloat?
    @State private var pinchStartOffset: CGPoint = .zero
    @State private var pinchStartContent: CGSize = .zero
    @State private var pinchFocus: CGPoint = .zero
    /// When the last pinch let go. To a tile, a finger that lands on it and
    /// lifts from it is a tap; to the person it was half of a pinch. A
    /// selection that arrives while two fingers are down, or within a beat of
    /// them lifting, belongs to the pinch, and no page opens for it.
    @State private var pinchEndedAt: Date = .distantPast
    /// How long after a pinch ends the tiles still treat a lift as its tail.
    private static let pinchSettleInterval: TimeInterval = 0.4
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
            expandedHeight: TableZoomLayout.expandedViewportHeight(screenHeight: screenHeight),
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
                onSelect: select,
                onDoubleTap: toggleZoom
            )
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            // At fitted zoom the content is exactly the viewport wide, so
            // nothing scrolls sideways and the grid sits centered.
            .frame(minWidth: viewportWidth)
            .coordinateSpace(.named(Self.contentSpace))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height.rounded()
            } action: { height in
                if abs(zoom - 1) < 0.001, fittedContentHeight != height {
                    fittedContentHeight = height
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollPosition($position)
        .scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        .onScrollGeometryChange(for: TableScrollSnapshot.self) { geometry in
            TableScrollSnapshot(
                offset: geometry.contentOffset,
                contentSize: geometry.contentSize,
                viewportSize: geometry.containerSize
            )
        } action: { _, snapshot in
            tracker.apply(snapshot)
        }
        .frame(height: viewportHeight(at: zoom))
        .simultaneousGesture(magnifyGesture)
        .task { restore() }
        .onDisappear { savedOffset = tracker.offset }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table.zoomView")
        .overlay(alignment: .topLeading) { zoomAccessibilityControl }
    }

    // MARK: - Accessibility

    /// The pinch's accessible twin, and nothing on screen.
    ///
    /// A clear, non-hit-testing element that VoiceOver and Switch Control can
    /// focus and adjust: swipe up and down to zoom, or pick one of the named
    /// actions from the rotor. Sighted learners see nothing at all, which is
    /// the point — the old toolbar menu and Fit chip were visual clutter that
    /// existed only for this.
    private var zoomAccessibilityControl: some View {
        Color.clear
            .frame(width: Theme.minimumTouchTarget, height: Theme.minimumTouchTarget)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel("Table zoom")
            .accessibilityValue(zoomValueDescription)
            .accessibilityHint("Swipe up or down to zoom the periodic table")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(zoomingIn: true)
                case .decrement: step(zoomingIn: false)
                @unknown default: break
                }
            }
            .accessibilityAction(named: Text("Zoom in")) { step(zoomingIn: true) }
            .accessibilityAction(named: Text("Zoom out")) { step(zoomingIn: false) }
            .accessibilityAction(named: Text("Fit table")) { fit(animated: true) }
            .accessibilitySortPriority(1)
            .accessibilityIdentifier("table.zoomAdjustable")
    }

    private var zoomValueDescription: String {
        "\((zoom * 10).rounded() / 10)×"
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
                pinchEndedAt = Date()
                // A pinch that stops a hair above fitted snaps home, so the
                // table is never left three points too wide with slack to
                // scroll.
                if zoom > 1, zoom < TableZoomLayout.zoomedThreshold {
                    fit(animated: true)
                }
            }
    }

    /// Opens a tile's page, unless the tap was really the end of a pinch.
    ///
    /// The tiles are buttons and the pinch is a simultaneous gesture, so each
    /// finger of a pinch is also a press on whatever tile it landed on. A
    /// finger that lifts from the tile it started on completes that press.
    /// The pinch recognizer ends when the first finger lifts, which can come
    /// either side of the button firing, so both the live flag and the
    /// moment it cleared are checked.
    private func select(_ element: ChemicalElement) {
        guard !isPinching,
              Date().timeIntervalSince(pinchEndedAt) > Self.pinchSettleInterval else { return }
        onSelect(element)
    }

    /// Applies a zoom while keeping `focus` (a viewport point) over the same
    /// content. The new content size is estimated from the size at the start
    /// of the gesture so the offset can be clamped before the layout catches
    /// up.
    ///
    /// A change smaller than a tenth of a percent is dropped: the magnify
    /// gesture reports a value every frame whether or not the fingers moved,
    /// and writing `zoom` and the scroll position for a change nothing can see
    /// is what made the scroll geometry update several times in one frame.
    private func move(
        to target: CGFloat,
        from startZoom: CGFloat,
        startOffset: CGPoint,
        startContent: CGSize,
        focus: CGPoint,
        animated: Bool
    ) {
        guard abs(target - zoom) > 0.001 else { return }
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

    /// One VoiceOver step, about the middle of the window.
    private func step(zoomingIn: Bool) {
        let factor = zoomingIn ? TableZoomLayout.stepFactor : 1 / TableZoomLayout.stepFactor
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
}
