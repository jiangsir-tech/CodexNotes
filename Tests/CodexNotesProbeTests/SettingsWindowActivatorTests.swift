import AppKit
import XCTest
@testable import CodexNotesProbe

@MainActor
final class SettingsWindowActivatorTests: XCTestCase {
    func testReattachingVisibleSettingsWindowPublishesVisibleAgain() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        let coordinator = SettingsWindowActivator.Coordinator()
        var visibilityChanges: [Bool] = []
        let token = NotificationCenter.default.addObserver(
            forName: SettingsWindowVisibilityNotification.name,
            object: nil,
            queue: .main
        ) { notification in
            guard let isVisible = notification.userInfo?[
                SettingsWindowVisibilityNotification.isVisibleKey
            ] as? Bool else { return }
            visibilityChanges.append(isVisible)
        }
        defer {
            NotificationCenter.default.removeObserver(token)
            coordinator.invalidate()
            window.orderOut(nil)
        }

        coordinator.attach(
            to: window,
            appearanceName: nil,
            backgroundColor: .windowBackgroundColor
        )
        XCTAssertEqual(visibilityChanges.last, true)

        window.close()
        XCTAssertEqual(visibilityChanges.last, false)

        window.orderFrontRegardless()
        coordinator.attach(
            to: window,
            appearanceName: nil,
            backgroundColor: .windowBackgroundColor
        )

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(visibilityChanges.last, true)
    }
}
