import AppKit
import XCTest
@testable import CodexNotesProbe

final class MainWindowInitialPlacementPolicyTests: XCTestCase {
    func testPreferredSizeAdaptsAcrossLaptopAndExternalDisplays() {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 1_440, height: 875), CGSize(width: 400, height: 600)),
            (CGSize(width: 1_512, height: 949), CGSize(width: 408, height: 626)),
            (CGSize(width: 1_728, height: 1_053), CGSize(width: 467, height: 680)),
            (CGSize(width: 2_560, height: 1_409), CGSize(width: 480, height: 680)),
            (CGSize(width: 6_016, height: 3_290), CGSize(width: 480, height: 680)),
        ]

        for (visibleSize, expected) in cases {
            XCTAssertEqual(
                MainWindowInitialPlacementPolicy.preferredSize(
                    forVisibleFrameSize: visibleSize
                ),
                expected,
                "Unexpected size for \(visibleSize)"
            )
        }
    }

    func testPreferredSizeFallsBackForInvalidScreenInformation() {
        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.preferredSize(
                forVisibleFrameSize: nil
            ),
            NSSize(width: 420, height: 640)
        )
        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.preferredSize(
                forVisibleFrameSize: .zero
            ),
            NSSize(width: 420, height: 640)
        )
        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.preferredSize(
                forVisibleFrameSize: CGSize(width: CGFloat.nan, height: 900)
            ),
            NSSize(width: 420, height: 640)
        )
        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.swiftUIBootstrapSize,
            NSSize(width: 440, height: 680)
        )
    }

    func testPreferredSizeNeverExceedsAnUnusuallySmallVisibleFrame() {
        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.preferredSize(
                forVisibleFrameSize: CGSize(width: 360, height: 500)
            ),
            NSSize(width: 360, height: 500)
        )
    }

    func testPlacementUsesRightThenLeftThenClampedOverlap() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)

        let right = MainWindowInitialPlacementPolicy.initialFrame(
            in: visibleFrame,
            codexFrame: NSRect(x: 100, y: 100, width: 700, height: 700)
        )
        XCTAssertEqual(right.origin, NSPoint(x: 808, y: 200))

        let left = MainWindowInitialPlacementPolicy.initialFrame(
            in: visibleFrame,
            codexFrame: NSRect(x: 600, y: 100, width: 700, height: 700)
        )
        XCTAssertEqual(left.origin, NSPoint(x: 192, y: 200))

        let overlap = MainWindowInitialPlacementPolicy.initialFrame(
            in: visibleFrame,
            codexFrame: NSRect(x: 100, y: 100, width: 1_240, height: 700)
        )
        XCTAssertEqual(overlap.origin, NSPoint(x: 932, y: 200))
        XCTAssertTrue(visibleFrame.contains(overlap))
    }

    func testPlacementCentersWithoutCodexWindow() {
        let frame = MainWindowInitialPlacementPolicy.initialFrame(
            in: NSRect(x: 200, y: 100, width: 1_440, height: 900),
            codexFrame: nil
        )
        XCTAssertEqual(frame, NSRect(x: 720, y: 250, width: 400, height: 600))
    }

    func testRestoringDefaultSizePreservesTopLeftAndClampsToVisibleFrame() {
        let studioDisplay = NSRect(
            x: 0,
            y: 0,
            width: 2_560,
            height: 1_409
        )
        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.frameByRestoringDefaultSize(
                from: NSRect(x: 1_975, y: 379, width: 452, height: 638),
                in: studioDisplay
            ),
            NSRect(x: 1_975, y: 337, width: 480, height: 680)
        )

        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.frameByRestoringDefaultSize(
                from: NSRect(x: 1_300, y: 40, width: 200, height: 200),
                in: NSRect(x: 0, y: 0, width: 1_440, height: 900)
            ),
            NSRect(x: 1_040, y: 0, width: 400, height: 600)
        )
    }

    func testDefaultSizeSelectsTheVisibleFrameWithTheLargestIntersection() {
        let left = NSRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let main = NSRect(x: 0, y: 0, width: 1_440, height: 900)

        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.visibleFrame(
                containingMostOf: NSRect(
                    x: -1_000,
                    y: 100,
                    width: 1_200,
                    height: 700
                ),
                among: [main, left]
            ),
            left
        )
    }

    func testDisplaySelectionUsesLargestQuartzIntersection() {
        let left = MainWindowDisplayGeometry(
            appKitFrame: NSRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1_440, height: 875),
            quartzFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        let right = MainWindowDisplayGeometry(
            appKitFrame: NSRect(x: 1_440, y: 0, width: 2_560, height: 1_440),
            visibleFrame: NSRect(x: 1_440, y: 0, width: 2_560, height: 1_409),
            quartzFrame: CGRect(x: 1_440, y: 0, width: 2_560, height: 1_440)
        )

        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.display(
                containingQuartzBounds: CGRect(
                    x: 1_200,
                    y: 100,
                    width: 1_000,
                    height: 700
                ),
                among: [left, right]
            ),
            right
        )
    }

    func testQuartzBoundsConvertToVerticallyStackedAppKitDisplay() {
        let upperDisplay = MainWindowDisplayGeometry(
            appKitFrame: NSRect(x: 0, y: 900, width: 1_920, height: 1_200),
            visibleFrame: NSRect(x: 0, y: 900, width: 1_920, height: 1_175),
            quartzFrame: CGRect(x: 0, y: -1_200, width: 1_920, height: 1_200)
        )
        let converted = MainWindowInitialPlacementPolicy.appKitFrame(
            forQuartzBounds: CGRect(x: 100, y: -1_100, width: 800, height: 700),
            on: upperDisplay
        )

        XCTAssertEqual(converted, NSRect(x: 100, y: 1_300, width: 800, height: 700))
    }
}
