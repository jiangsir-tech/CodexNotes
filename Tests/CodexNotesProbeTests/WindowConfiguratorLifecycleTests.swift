import AppKit
import XCTest
@testable import CodexNotesProbe

@MainActor
final class WindowConfiguratorLifecycleTests: XCTestCase {
    func testSettingsVisibilityNotificationDoesNotHideVisibleMainWindow() async {
        await preservingStableFrameDefaults {
            let availability = FakeCodexApplicationAvailabilityMonitor(
                isCodexAvailable: true
            )
            let mainCoordinator = WindowConfigurator.Coordinator(
                codexAvailabilityMonitor: availability
            )
            let settingsCoordinator = SettingsWindowActivator.Coordinator()
            let mainWindow = makeMainWindow()
            let settingsWindow = makeSettingsWindow()
            defer {
                settingsCoordinator.invalidate()
                mainCoordinator.detach()
                settingsWindow.orderOut(nil)
                mainWindow.orderOut(nil)
            }

            mainCoordinator.attach(
                to: mainWindow,
                languageRevision: "test"
            )
            settingsCoordinator.attach(
                to: settingsWindow,
                appearanceName: nil,
                backgroundColor: .windowBackgroundColor
            )
            mainWindow.orderFrontRegardless()
            XCTAssertTrue(mainWindow.isVisible)
            XCTAssertTrue(settingsWindow.isVisible)

            NotificationCenter.default.post(
                name: SettingsWindowVisibilityNotification.name,
                object: nil,
                userInfo: [
                    SettingsWindowVisibilityNotification.isVisibleKey: true,
                ]
            )
            await drainMainQueue()

            XCTAssertTrue(mainWindow.isVisible)
            XCTAssertTrue(settingsWindow.isVisible)
        }
    }

    func testAvailabilityLossHidesMainWindowAndDetachStopsMonitoring() {
        preservingStableFrameDefaults {
            let availability = FakeCodexApplicationAvailabilityMonitor(
                isCodexAvailable: true
            )
            let coordinator = WindowConfigurator.Coordinator(
                codexAvailabilityMonitor: availability
            )
            let window = makeMainWindow()
            defer { window.orderOut(nil) }

            coordinator.attach(to: window, languageRevision: "test")
            coordinator.attach(to: window, languageRevision: "test")

            XCTAssertEqual(availability.startCount, 1)
            XCTAssertTrue(availability.hasChangeHandler)

            window.orderFrontRegardless()
            XCTAssertTrue(window.isVisible)

            availability.update(false)

            XCTAssertFalse(window.isVisible)

            window.orderFrontRegardless()
            XCTAssertTrue(window.isVisible)

            coordinator.detach()

            XCTAssertEqual(availability.stopCount, 1)
            XCTAssertFalse(availability.hasChangeHandler)

            availability.update(false)

            XCTAssertTrue(window.isVisible)
        }
    }

    func testInvalidateStopsMonitoringAndRejectsASecondAttach() {
        preservingStableFrameDefaults {
            let availability = FakeCodexApplicationAvailabilityMonitor(
                isCodexAvailable: false
            )
            let coordinator = WindowConfigurator.Coordinator(
                codexAvailabilityMonitor: availability
            )
            let window = makeMainWindow()
            defer { window.orderOut(nil) }

            coordinator.attach(to: window, languageRevision: "test")
            XCTAssertEqual(availability.startCount, 1)

            coordinator.invalidate()

            XCTAssertEqual(availability.stopCount, 1)
            XCTAssertFalse(availability.hasChangeHandler)

            coordinator.attach(to: window, languageRevision: "test-again")

            XCTAssertEqual(availability.startCount, 1)
            XCTAssertEqual(availability.stopCount, 1)
        }
    }

    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 420, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = CodexNotesWindowIdentifier.main
        window.alphaValue = 0
        return window
    }

    private func makeSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 560, y: 100, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        return window
    }

    private func preservingStableFrameDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let key = MainWindowFramePersistence.autosaveDefaultsKey
        let originalValue = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        body()
    }

    private func preservingStableFrameDefaults(
        _ body: () async -> Void
    ) async {
        let defaults = UserDefaults.standard
        let key = MainWindowFramePersistence.autosaveDefaultsKey
        let originalValue = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        await body()
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}

@MainActor
private final class FakeCodexApplicationAvailabilityMonitor:
    CodexApplicationAvailabilityObserving
{
    private(set) var isCodexAvailable: Bool
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var changeHandler: ((Bool) -> Void)?

    var hasChangeHandler: Bool {
        changeHandler != nil
    }

    init(isCodexAvailable: Bool) {
        self.isCodexAvailable = isCodexAvailable
    }

    func start(onChange: @escaping (Bool) -> Void) {
        startCount += 1
        changeHandler = onChange
    }

    func stop() {
        stopCount += 1
        changeHandler = nil
    }

    func update(_ isCodexAvailable: Bool) {
        self.isCodexAvailable = isCodexAvailable
        changeHandler?(isCodexAvailable)
    }
}
