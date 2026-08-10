import AppKit
import CodexNotesCore
import XCTest
@testable import CodexNotesProbe

@MainActor
final class MainWindowChromePolicyTests: XCTestCase {
    func testMainWindowRejectsZoomRequests() {
        XCTAssertFalse(MainWindowChromePolicy.allowsZoom)
    }

    func testApplyingPolicyHidesZoomButtonAndKeepsManualResize() throws {
        let window = makeWindow()
        let zoomButton = try XCTUnwrap(
            window.standardWindowButton(.zoomButton)
        )
        let closeButton = try XCTUnwrap(
            window.standardWindowButton(.closeButton)
        )
        let miniaturizeButton = try XCTUnwrap(
            window.standardWindowButton(.miniaturizeButton)
        )

        MainWindowChromePolicy.apply(
            to: window,
            localization: AppLocalization(preference: .simplifiedChinese)
        )

        XCTAssertTrue(zoomButton.isHidden)
        XCTAssertFalse(zoomButton.isEnabled)
        XCTAssertFalse(closeButton.isHidden)
        XCTAssertTrue(closeButton.isEnabled)
        XCTAssertNil(closeButton.toolTip)
        XCTAssertEqual(closeButton.accessibilityLabel(), "隐藏 CodexNotes")
        XCTAssertEqual(
            closeButton.accessibilityHelp(),
            "隐藏笔记窗口，应用继续在状态栏运行"
        )
        XCTAssertTrue(miniaturizeButton.isHidden)
        XCTAssertFalse(miniaturizeButton.isEnabled)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.isMovable)
    }

    func testApplyingPolicyUsesTheSelectedEnglishAccessibilityCopy() throws {
        let window = makeWindow()
        let closeButton = try XCTUnwrap(
            window.standardWindowButton(.closeButton)
        )

        MainWindowChromePolicy.apply(
            to: window,
            localization: AppLocalization(preference: .english)
        )

        XCTAssertEqual(closeButton.accessibilityLabel(), "Hide CodexNotes")
        XCTAssertEqual(
            closeButton.accessibilityHelp(),
            "Hides the notes window. CodexNotes will keep running in the menu bar."
        )
    }

    func testApplyingPolicyIsIdempotent() throws {
        let window = makeWindow()

        MainWindowChromePolicy.apply(to: window)
        MainWindowChromePolicy.apply(to: window)

        let zoomButton = try XCTUnwrap(
            window.standardWindowButton(.zoomButton)
        )
        let miniaturizeButton = try XCTUnwrap(
            window.standardWindowButton(.miniaturizeButton)
        )
        XCTAssertTrue(zoomButton.isHidden)
        XCTAssertFalse(zoomButton.isEnabled)
        XCTAssertTrue(miniaturizeButton.isHidden)
        XCTAssertFalse(miniaturizeButton.isEnabled)
    }

    func testWindowCoordinatorRejectsZoom() {
        let window = makeWindow()
        let coordinator = WindowConfigurator.Coordinator()

        XCTAssertFalse(
            coordinator.windowShouldZoom(
                window,
                toFrame: NSRect(x: 0, y: 0, width: 1_200, height: 900)
            )
        )
    }

    func testRejectedPerformZoomKeepsWindowFrame() {
        let window = makeWindow()
        let coordinator = WindowConfigurator.Coordinator()
        let originalFrame = window.frame
        window.delegate = coordinator

        window.performZoom(nil)

        XCTAssertEqual(window.frame, originalFrame)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
    }
}
