import AppKit
import XCTest
@testable import CodexNotesProbe

final class MainWindowInitialPlacementPolicyTests: XCTestCase {
    func testPreferredSizeAdaptsAcrossLaptopAndExternalDisplays() {
        let cases: [(CGSize, CGSize)] = [
            (CGSize(width: 1_440, height: 875), CGSize(width: 418, height: 640)),
            (CGSize(width: 1_512, height: 949), CGSize(width: 438, height: 683)),
            (CGSize(width: 1_728, height: 1_053), CGSize(width: 501, height: 725)),
            (CGSize(width: 2_560, height: 1_409), CGSize(width: 548, height: 725)),
            (CGSize(width: 6_016, height: 3_290), CGSize(width: 548, height: 725)),
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
            NSSize(width: 440, height: 680)
        )
        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.preferredSize(
                forVisibleFrameSize: .zero
            ),
            NSSize(width: 440, height: 680)
        )
        XCTAssertEqual(
            MainWindowInitialPlacementPolicy.preferredSize(
                forVisibleFrameSize: CGSize(width: CGFloat.nan, height: 900)
            ),
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
        XCTAssertEqual(right.origin, NSPoint(x: 808, y: 152))

        let left = MainWindowInitialPlacementPolicy.initialFrame(
            in: visibleFrame,
            codexFrame: NSRect(x: 600, y: 100, width: 700, height: 700)
        )
        XCTAssertEqual(left.origin, NSPoint(x: 174, y: 152))

        let overlap = MainWindowInitialPlacementPolicy.initialFrame(
            in: visibleFrame,
            codexFrame: NSRect(x: 100, y: 100, width: 1_240, height: 700)
        )
        XCTAssertEqual(overlap.origin, NSPoint(x: 914, y: 152))
        XCTAssertTrue(visibleFrame.contains(overlap))
    }

    func testPlacementCentersWithoutCodexWindow() {
        let frame = MainWindowInitialPlacementPolicy.initialFrame(
            in: NSRect(x: 200, y: 100, width: 1_440, height: 900),
            codexFrame: nil
        )
        XCTAssertEqual(frame, NSRect(x: 711, y: 226, width: 418, height: 648))
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
