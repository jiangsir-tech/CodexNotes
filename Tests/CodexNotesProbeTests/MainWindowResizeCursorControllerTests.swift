import AppKit
import XCTest
@testable import CodexNotesProbe

@MainActor
final class MainWindowResizeCursorControllerTests: XCTestCase {
    func testClassifiesAllFourEdgesFourCornersAndInterior() {
        let bounds = NSRect(x: 10, y: 20, width: 100, height: 80)
        let cases: [(NSPoint, MainWindowResizeCursorRegion?)] = [
            (NSPoint(x: 60, y: 100), .top),
            (NSPoint(x: 110, y: 100), .topRight),
            (NSPoint(x: 110, y: 60), .right),
            (NSPoint(x: 110, y: 20), .bottomRight),
            (NSPoint(x: 60, y: 20), .bottom),
            (NSPoint(x: 10, y: 20), .bottomLeft),
            (NSPoint(x: 10, y: 60), .left),
            (NSPoint(x: 10, y: 100), .topLeft),
            (NSPoint(x: 60, y: 60), nil),
        ]

        for (point, expectedRegion) in cases {
            XCTAssertEqual(
                MainWindowResizeCursorRegion.region(at: point, in: bounds),
                expectedRegion,
                "point=\(point)"
            )
        }
    }

    func testCornersUseLShapedReachAndDoNotClaimInteriorSquare() {
        let bounds = NSRect(x: 0, y: 0, width: 100, height: 80)

        XCTAssertEqual(
            MainWindowResizeCursorRegion.region(at: NSPoint(x: 10, y: 79), in: bounds),
            .topLeft
        )
        XCTAssertEqual(
            MainWindowResizeCursorRegion.region(at: NSPoint(x: 1, y: 70), in: bounds),
            .topLeft
        )
        XCTAssertNil(
            MainWindowResizeCursorRegion.region(at: NSPoint(x: 10, y: 70), in: bounds)
        )
        XCTAssertEqual(
            MainWindowResizeCursorRegion.region(at: NSPoint(x: 15, y: 79), in: bounds),
            .top
        )
    }

    func testPointsOutsideFrameNeverProduceResizeRegion() {
        let bounds = NSRect(x: 0, y: 0, width: 100, height: 80)
        let outsidePoints = [
            NSPoint(x: -0.01, y: 40),
            NSPoint(x: 100.01, y: 40),
            NSPoint(x: 50, y: -0.01),
            NSPoint(x: 50, y: 80.01),
        ]

        for point in outsidePoints {
            XCTAssertNil(
                MainWindowResizeCursorRegion.region(at: point, in: bounds),
                "point=\(point)"
            )
        }
    }

    func testAllRegionsMapToTheirNativeFrameResizeCursor() throws {
        guard #available(macOS 15.0, *) else {
            XCTAssertCursorEqual(
                MainWindowResizeCursorRegion.top.cursor,
                .resizeUpDown
            )
            XCTAssertCursorEqual(
                MainWindowResizeCursorRegion.left.cursor,
                .resizeLeftRight
            )
            return
        }
        let expected: [(MainWindowResizeCursorRegion, NSCursor.FrameResizePosition)] = [
            (.top, .top),
            (.topRight, .topRight),
            (.right, .right),
            (.bottomRight, .bottomRight),
            (.bottom, .bottom),
            (.bottomLeft, .bottomLeft),
            (.left, .left),
            (.topLeft, .topLeft),
        ]

        for (region, position) in expected {
            XCTAssertCursorEqual(
                region.cursor,
                NSCursor.frameResize(position: position, directions: .all),
                "region=\(region)"
            )
        }
    }

    func testAttachUsesOneAlwaysActiveFullFrameTrackingAreaWithoutChangingHitTesting() throws {
        let context = try makeVisibleWindow()
        let presenter = ResizeCursorPresenterSpy()
        let controller = MainWindowResizeCursorController(presenter: presenter)
        defer {
            controller.detach()
            context.window.orderOut(nil)
        }
        let originalStyleMask = context.window.styleMask
        let originalContentView = context.window.contentView
        let originalSubviewIDs = context.frameView.subviews.map(ObjectIdentifier.init)
        let probePoint = context.frameView.convert(
            NSPoint(x: 20, y: 20),
            from: context.window.contentView
        )
        let originalHitView = context.frameView.hitTest(probePoint)
        XCTAssertFalse(context.window.acceptsMouseMovedEvents)

        controller.attach(to: context.window)
        controller.attach(to: context.window)

        let ownedAreas = context.frameView.trackingAreas.filter {
            $0.owner === controller
        }
        let area = try XCTUnwrap(ownedAreas.first)
        XCTAssertEqual(ownedAreas.count, 1)
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(area.options.contains(.mouseMoved))
        XCTAssertTrue(area.options.contains(.activeAlways))
        XCTAssertTrue(area.options.contains(.inVisibleRect))
        XCTAssertTrue(area.options.contains(.enabledDuringMouseDrag))
        XCTAssertFalse(area.options.contains(.activeInKeyWindow))
        XCTAssertFalse(area.options.contains(.cursorUpdate))
        XCTAssertTrue(context.window.acceptsMouseMovedEvents)
        XCTAssertEqual(context.window.styleMask, originalStyleMask)
        XCTAssertTrue(context.window.contentView === originalContentView)
        XCTAssertEqual(
            context.frameView.subviews.map(ObjectIdentifier.init),
            originalSubviewIDs
        )
        XCTAssertTrue(context.frameView.hitTest(probePoint) === originalHitView)

        controller.detach()

        XCTAssertFalse(context.frameView.trackingAreas.contains { $0.owner === controller })
        XCTAssertFalse(context.window.acceptsMouseMovedEvents)
    }

    func testVisibleNonKeyWindowPresentsEightRegionsAndRestoresOnceInInterior() throws {
        let context = try makeVisibleWindow()
        let presenter = ResizeCursorPresenterSpy()
        let controller = MainWindowResizeCursorController(presenter: presenter)
        defer {
            controller.detach()
            context.window.orderOut(nil)
        }
        controller.attach(to: context.window)
        XCTAssertFalse(context.window.isKeyWindow)
        let bounds = context.frameView.bounds

        let regionPoints: [(MainWindowResizeCursorRegion, NSPoint)] = [
            (.top, NSPoint(x: bounds.midX, y: bounds.maxY)),
            (.topRight, NSPoint(x: bounds.maxX, y: bounds.maxY)),
            (.right, NSPoint(x: bounds.maxX, y: bounds.midY)),
            (.bottomRight, NSPoint(x: bounds.maxX, y: bounds.minY)),
            (.bottom, NSPoint(x: bounds.midX, y: bounds.minY)),
            (.bottomLeft, NSPoint(x: bounds.minX, y: bounds.minY)),
            (.left, NSPoint(x: bounds.minX, y: bounds.midY)),
            (.topLeft, NSPoint(x: bounds.minX, y: bounds.maxY)),
        ]

        controller.pointerMoved(to: regionPoints[0].1)
        for (_, point) in regionPoints {
            controller.pointerMoved(to: point)
        }
        controller.pointerMoved(to: NSPoint(x: bounds.midX, y: bounds.midY))

        XCTAssertEqual(presenter.begunRegions, [.top])
        XCTAssertEqual(
            presenter.updatedRegions,
            regionPoints.map(\.0)
        )
        XCTAssertEqual(presenter.endCount, 1)
        XCTAssertNil(controller.currentRegion)
        XCTAssertFalse(context.window.isKeyWindow)
    }

    func testSameEdgeReassertsCursorWithoutStartingAnotherPresentation() throws {
        let context = try makeVisibleWindow()
        let presenter = ResizeCursorPresenterSpy()
        let controller = MainWindowResizeCursorController(presenter: presenter)
        defer {
            controller.detach()
            context.window.orderOut(nil)
        }
        controller.attach(to: context.window)
        let point = NSPoint(
            x: context.frameView.bounds.maxX,
            y: context.frameView.bounds.midY
        )

        controller.pointerMoved(to: point)
        controller.pointerMoved(to: point)
        controller.pointerMoved(to: point)

        XCTAssertEqual(presenter.begunRegions, [.right])
        XCTAssertEqual(presenter.updatedRegions, [.right, .right])
        XCTAssertEqual(presenter.endCount, 0)
    }

    func testMouseMovedEventUsesAttachedFrameWithoutReadingTrackingArea() throws {
        let context = try makeVisibleWindow()
        let presenter = ResizeCursorPresenterSpy()
        let controller = MainWindowResizeCursorController(presenter: presenter)
        defer {
            controller.detach()
            context.window.orderOut(nil)
        }
        controller.attach(to: context.window)
        let framePoint = NSPoint(
            x: context.frameView.bounds.maxX,
            y: context.frameView.bounds.midY
        )
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved,
                location: context.frameView.convert(framePoint, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: context.window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 0,
                pressure: 0
            )
        )

        controller.mouseMoved(with: event)

        XCTAssertEqual(presenter.begunRegions, [.right])
        XCTAssertEqual(controller.currentRegion, .right)
    }

    func testHiddenOrNonResizableWindowDoesNotLeaveResizeCursorPresented() throws {
        let context = try makeVisibleWindow()
        let presenter = ResizeCursorPresenterSpy()
        let controller = MainWindowResizeCursorController(presenter: presenter)
        defer {
            controller.detach()
            context.window.orderOut(nil)
        }
        controller.attach(to: context.window)
        let edgePoint = NSPoint(
            x: context.frameView.bounds.maxX,
            y: context.frameView.bounds.midY
        )

        controller.pointerMoved(to: edgePoint)
        context.window.styleMask.remove(.resizable)
        controller.pointerMoved(to: edgePoint)
        context.window.styleMask.insert(.resizable)
        context.window.orderOut(nil)
        controller.pointerMoved(to: edgePoint)

        XCTAssertEqual(presenter.begunRegions, [.right])
        XCTAssertEqual(presenter.endCount, 1)
        XCTAssertNil(controller.currentRegion)
    }

    func testReattachingToAnotherWindowRemovesOldAreaAndIgnoresStaleExit() throws {
        let oldContext = try makeVisibleWindow(x: 100)
        let newContext = try makeVisibleWindow(x: 620)
        let presenter = ResizeCursorPresenterSpy()
        let controller = MainWindowResizeCursorController(presenter: presenter)
        defer {
            controller.detach()
            oldContext.window.orderOut(nil)
            newContext.window.orderOut(nil)
        }
        controller.attach(to: oldContext.window)
        let staleArea = try XCTUnwrap(
            oldContext.frameView.trackingAreas.first { $0.owner === controller }
        )

        controller.attach(to: newContext.window)
        controller.pointerMoved(
            to: NSPoint(
                x: newContext.frameView.bounds.maxX,
                y: newContext.frameView.bounds.midY
            )
        )
        controller.pointerExited(from: staleArea)

        XCTAssertFalse(oldContext.frameView.trackingAreas.contains { $0.owner === controller })
        XCTAssertEqual(
            newContext.frameView.trackingAreas.filter { $0.owner === controller }.count,
            1
        )
        XCTAssertEqual(presenter.begunRegions, [.right])
        XCTAssertEqual(presenter.endCount, 0)
        XCTAssertEqual(controller.currentRegion, .right)
    }

    private func makeVisibleWindow(
        x: CGFloat = 100
    ) throws -> (window: NSWindow, frameView: NSView) {
        let window = NonKeyResizeTestWindow(
            contentRect: NSRect(x: x, y: 100, width: 500, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.orderFrontRegardless()
        XCTAssertTrue(window.isVisible)
        return (window, try XCTUnwrap(window.contentView?.superview))
    }

    private func XCTAssertCursorEqual(
        _ actual: NSCursor,
        _ expected: NSCursor,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.hotSpot, expected.hotSpot, message, file: file, line: line)
        XCTAssertEqual(
            actual.image.tiffRepresentation,
            expected.image.tiffRepresentation,
            message,
            file: file,
            line: line
        )
    }
}

private final class NonKeyResizeTestWindow: NSWindow {
    override var isKeyWindow: Bool { false }
}

@MainActor
private final class ResizeCursorPresenterSpy: MainWindowResizeCursorPresenting {
    private(set) var begunRegions: [MainWindowResizeCursorRegion] = []
    private(set) var updatedRegions: [MainWindowResizeCursorRegion] = []
    private(set) var endCount = 0

    func beginPresenting(_ region: MainWindowResizeCursorRegion) {
        begunRegions.append(region)
    }

    func updatePresentedRegion(_ region: MainWindowResizeCursorRegion) {
        updatedRegions.append(region)
    }

    func endPresenting() {
        endCount += 1
    }
}
