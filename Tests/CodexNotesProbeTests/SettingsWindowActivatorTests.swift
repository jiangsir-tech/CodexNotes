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

    func testAttachElevatesSettingsAndCloseRestoresOriginalLevel() {
        let window = makeWindow()
        let originalLevel = window.level
        let coordinator = SettingsWindowActivator.Coordinator()
        defer {
            coordinator.invalidate()
            window.orderOut(nil)
        }

        coordinator.attach(
            to: window,
            appearanceName: nil,
            backgroundColor: .windowBackgroundColor
        )

        XCTAssertGreaterThan(
            SettingsWindowLevelPolicy.active.rawValue,
            NSWindow.Level.floating.rawValue
        )
        XCTAssertEqual(window.level, SettingsWindowLevelPolicy.active)

        window.close()

        XCTAssertEqual(window.level, originalLevel)
    }

    func testResignAndDetachRestoreLevelAndRemoveKeyObservers() {
        let window = makeWindow()
        let originalLevel = window.level
        let coordinator = SettingsWindowActivator.Coordinator()
        defer { window.orderOut(nil) }

        coordinator.attach(
            to: window,
            appearanceName: nil,
            backgroundColor: .windowBackgroundColor
        )
        XCTAssertEqual(window.level, SettingsWindowLevelPolicy.active)

        NotificationCenter.default.post(
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        XCTAssertEqual(window.level, originalLevel)

        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        XCTAssertEqual(window.level, SettingsWindowLevelPolicy.active)

        coordinator.detach()
        XCTAssertEqual(window.level, originalLevel)

        NotificationCenter.default.post(
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        XCTAssertEqual(window.level, originalLevel)
    }

    func testActiveSettingsStaysAboveFloatingMainWindowOrderedFront() throws {
        let settingsWindow = makeWindow()
        let mainWindow = makeWindow()
        mainWindow.identifier = CodexNotesWindowIdentifier.main
        mainWindow.level = .floating
        let coordinator = SettingsWindowActivator.Coordinator()
        defer {
            coordinator.invalidate()
            settingsWindow.orderOut(nil)
            mainWindow.orderOut(nil)
        }

        coordinator.attach(
            to: settingsWindow,
            appearanceName: nil,
            backgroundColor: .windowBackgroundColor
        )
        mainWindow.orderFrontRegardless()

        XCTAssertEqual(
            settingsWindow.level,
            SettingsWindowLevelPolicy.active
        )
        XCTAssertGreaterThan(
            settingsWindow.level.rawValue,
            mainWindow.level.rawValue
        )

        let orderedWindows = NSApp.orderedWindows
        let settingsIndex = try XCTUnwrap(
            orderedWindows.firstIndex { $0 === settingsWindow }
        )
        let mainIndex = try XCTUnwrap(
            orderedWindows.firstIndex { $0 === mainWindow }
        )
        XCTAssertLessThan(settingsIndex, mainIndex)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        return window
    }
}
