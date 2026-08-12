import AppKit
import ObjectiveC.runtime

private enum MainWindowFrameResizeCursorRuntime {
    typealias Factory = @convention(c) (
        AnyClass,
        Selector,
        UInt,
        UInt
    ) -> Unmanaged<NSCursor>

    private static let selector = NSSelectorFromString(
        "frameResizeCursorFromPosition:inDirections:"
    )
    private static let factory: Factory? = {
        guard let method = class_getClassMethod(NSCursor.self, selector) else {
            return nil
        }
        return unsafeBitCast(
            method_getImplementation(method),
            to: Factory.self
        )
    }()

    static func cursor(position: UInt) -> NSCursor? {
        factory?(
            NSCursor.self,
            selector,
            position,
            3 // inward | outward
        ).takeUnretainedValue()
    }
}

/// The part of a resizable window frame currently under the pointer.
enum MainWindowResizeCursorRegion: CaseIterable, Equatable {
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case topLeft

    static let edgeThickness: CGFloat = 6
    static let cornerReach: CGFloat = 14

    /// Returns an edge only inside the thin native resize band. Corners use
    /// an L-shaped extension along their two adjacent edges, matching the
    /// larger target users expect without claiming interior content pixels.
    static func region(
        at point: NSPoint,
        in bounds: NSRect,
        edgeThickness: CGFloat = edgeThickness,
        cornerReach: CGFloat = cornerReach
    ) -> Self? {
        guard bounds.width > 0,
              bounds.height > 0,
              point.x >= bounds.minX,
              point.x <= bounds.maxX,
              point.y >= bounds.minY,
              point.y <= bounds.maxY else {
            return nil
        }

        let edgeThickness = max(0, edgeThickness)
        let horizontalCornerReach = min(
            max(edgeThickness, cornerReach),
            bounds.width / 2
        )
        let verticalCornerReach = min(
            max(edgeThickness, cornerReach),
            bounds.height / 2
        )
        let distanceFromLeft = point.x - bounds.minX
        let distanceFromRight = bounds.maxX - point.x
        let distanceFromBottom = point.y - bounds.minY
        let distanceFromTop = bounds.maxY - point.y
        let nearLeft = distanceFromLeft <= edgeThickness
        let nearRight = distanceFromRight <= edgeThickness
        let nearBottom = distanceFromBottom <= edgeThickness
        let nearTop = distanceFromTop <= edgeThickness

        if (nearTop && distanceFromLeft <= horizontalCornerReach)
            || (nearLeft && distanceFromTop <= verticalCornerReach) {
            return .topLeft
        }
        if (nearTop && distanceFromRight <= horizontalCornerReach)
            || (nearRight && distanceFromTop <= verticalCornerReach) {
            return .topRight
        }
        if (nearBottom && distanceFromRight <= horizontalCornerReach)
            || (nearRight && distanceFromBottom <= verticalCornerReach) {
            return .bottomRight
        }
        if (nearBottom && distanceFromLeft <= horizontalCornerReach)
            || (nearLeft && distanceFromBottom <= verticalCornerReach) {
            return .bottomLeft
        }
        if nearTop { return .top }
        if nearRight { return .right }
        if nearBottom { return .bottom }
        if nearLeft { return .left }
        return nil
    }

    var frameResizePosition: UInt {
        switch self {
        case .top: 1
        case .left: 2
        case .bottom: 4
        case .right: 8
        case .topLeft: 3
        case .topRight: 9
        case .bottomLeft: 6
        case .bottomRight: 12
        }
    }

    var cursor: NSCursor {
        cursor(resolvingFrameResizeCursorWith: MainWindowFrameResizeCursorRuntime.cursor)
    }

    func cursor(
        resolvingFrameResizeCursorWith resolve: (UInt) -> NSCursor?
    ) -> NSCursor {
        if let nativeCursor = resolve(frameResizePosition) {
            return nativeCursor
        }

        // macOS 14 has no public frame-resize cursor factory. Keep the frame
        // resizable and provide an axis cue rather than a custom image.
        switch self {
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right, .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .resizeLeftRight
        }
    }
}

@MainActor
protocol MainWindowResizeCursorPresenting: AnyObject {
    func beginPresenting(_ region: MainWindowResizeCursorRegion)
    func updatePresentedRegion(_ region: MainWindowResizeCursorRegion)
    func endPresenting()
}

@MainActor
private final class AppKitMainWindowResizeCursorPresenter:
    MainWindowResizeCursorPresenting
{
    private var previousCursor: NSCursor?
    private var lastPresentedCursor: NSCursor?
    private var isPresenting = false

    func beginPresenting(_ region: MainWindowResizeCursorRegion) {
        if !isPresenting {
            let currentCursor = NSCursor.current
            previousCursor = Self.isFrameResizeCursor(currentCursor)
                ? .arrow
                : currentCursor
            isPresenting = true
        }
        present(region.cursor)
    }

    func updatePresentedRegion(_ region: MainWindowResizeCursorRegion) {
        guard isPresenting else {
            beginPresenting(region)
            return
        }
        // Reassert on every mouse-moved event. Cursor rects belonging to a
        // descendant view may also be active while the pointer hugs the edge.
        present(region.cursor)
    }

    func endPresenting() {
        guard isPresenting else { return }
        // AppKit may already have selected an I-beam, checkbox hand, or title
        // bar cursor for the same event. Restore our snapshot only while the
        // cursor is still the exact frame cursor this presenter last set.
        if NSCursor.current === lastPresentedCursor {
            (previousCursor ?? .arrow).set()
        }
        previousCursor = nil
        lastPresentedCursor = nil
        isPresenting = false
    }

    private func present(_ cursor: NSCursor) {
        lastPresentedCursor = cursor
        cursor.set()
    }

    private static func isFrameResizeCursor(_ cursor: NSCursor) -> Bool {
        MainWindowResizeCursorRegion.allCases.contains {
            let candidate = $0.cursor
            return candidate === cursor
                || (
                    candidate.hotSpot == cursor.hotSpot
                        && candidate.image.tiffRepresentation
                            == cursor.image.tiffRepresentation
                )
        }
    }
}

/// Restores native resize feedback for the accessory app's visible, non-key
/// floating window. The tracking area observes only; AppKit still owns all
/// hit testing and the actual resize drag.
@MainActor
final class MainWindowResizeCursorController: NSResponder {
    private weak var window: NSWindow?
    private weak var frameView: NSView?
    private var trackingArea: NSTrackingArea?
    private var windowVisibilityObservation: NSKeyValueObservation?
    private var originalAcceptsMouseMovedEvents: Bool?
    private let presenter: any MainWindowResizeCursorPresenting
    private(set) var currentRegion: MainWindowResizeCursorRegion?

    override convenience init() {
        self.init(presenter: AppKitMainWindowResizeCursorPresenter())
    }

    init(presenter: any MainWindowResizeCursorPresenting) {
        self.presenter = presenter
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        MainActor.assumeIsolated {
            cancelAndRestore()
            windowVisibilityObservation?.invalidate()
            if let frameView, let trackingArea {
                frameView.removeTrackingArea(trackingArea)
            }
            if let window, let originalAcceptsMouseMovedEvents {
                window.acceptsMouseMovedEvents = originalAcceptsMouseMovedEvents
            }
        }
    }

    /// Repeated attachment to the same standard frame keeps exactly one
    /// tracking area. NSThemeFrame is intentionally used because contentView
    /// does not include the title bar or the top resize edge.
    func attach(to window: NSWindow) {
        guard let frameView = window.contentView?.superview else {
            detach()
            return
        }

        if self.window === window, self.frameView === frameView {
            ensureTrackingAreaIsInstalled(on: frameView)
            window.acceptsMouseMovedEvents = true
            return
        }

        detach()
        self.window = window
        self.frameView = frameView
        originalAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
        window.acceptsMouseMovedEvents = true
        installTrackingArea(on: frameView)
        windowVisibilityObservation = window.observe(
            \.isVisible,
            options: [.new]
        ) { [weak self] _, change in
            guard change.newValue == false else { return }
            MainActor.assumeIsolated {
                self?.cancelAndRestore()
            }
        }
    }

    /// Removes the cursor immediately when the window is hidden while the
    /// pointer is still in its former frame.
    func cancelAndRestore() {
        guard currentRegion != nil else { return }
        currentRegion = nil
        presenter.endPresenting()
    }

    func detach() {
        cancelAndRestore()
        windowVisibilityObservation?.invalidate()
        windowVisibilityObservation = nil
        if let frameView, let trackingArea {
            frameView.removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        if let window, let originalAcceptsMouseMovedEvents {
            window.acceptsMouseMovedEvents = originalAcceptsMouseMovedEvents
        }
        originalAcceptsMouseMovedEvents = nil
        frameView = nil
        window = nil
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === trackingArea else { return }
        pointerMoved(using: event)
    }

    override func mouseMoved(with event: NSEvent) {
        // NSEvent.trackingArea is only valid for enter, exit, and cursor-update
        // events. AppKit dispatches this callback to the tracking area's owner,
        // so attachment identity is validated through our retained area/view.
        guard trackingArea != nil else { return }
        pointerMoved(using: event)
    }

    override func mouseExited(with event: NSEvent) {
        pointerExited(from: event.trackingArea)
    }

    /// A semantic entry point makes the geometry and cursor lifecycle
    /// deterministic in unit tests without moving the user's real pointer.
    func pointerMoved(to point: NSPoint) {
        guard let window,
              let frameView,
              frameView.window === window,
              window.isVisible,
              !window.isMiniaturized,
              window.styleMask.contains(.resizable),
              !window.styleMask.contains(.fullScreen) else {
            cancelAndRestore()
            return
        }
        updatePresentedRegion(
            MainWindowResizeCursorRegion.region(at: point, in: frameView.bounds)
        )
    }

    func pointerExited(from eventTrackingArea: NSTrackingArea?) {
        guard eventTrackingArea === trackingArea else { return }
        cancelAndRestore()
    }

    private func pointerMoved(using event: NSEvent) {
        guard let window,
              event.window === window,
              let frameView,
              frameView.window === window else { return }
        pointerMoved(to: frameView.convert(event.locationInWindow, from: nil))
    }

    private func updatePresentedRegion(
        _ newRegion: MainWindowResizeCursorRegion?
    ) {
        switch (currentRegion, newRegion) {
        case (nil, let newRegion?):
            currentRegion = newRegion
            presenter.beginPresenting(newRegion)
        case (.some, let newRegion?):
            self.currentRegion = newRegion
            // Reassert even if the region did not change; descendant cursor
            // rects must not win a race at the inside edge of the frame.
            presenter.updatePresentedRegion(newRegion)
        case (.some, nil):
            currentRegion = nil
            presenter.endPresenting()
        case (nil, nil):
            break
        }
    }

    private func ensureTrackingAreaIsInstalled(on frameView: NSView) {
        if let trackingArea, frameView.trackingAreas.contains(trackingArea) {
            return
        }
        installTrackingArea(on: frameView)
    }

    private func installTrackingArea(on frameView: NSView) {
        if let trackingArea {
            self.frameView?.removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeAlways,
                .inVisibleRect,
                .enabledDuringMouseDrag,
            ],
            owner: self,
            userInfo: nil
        )
        frameView.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }
}
