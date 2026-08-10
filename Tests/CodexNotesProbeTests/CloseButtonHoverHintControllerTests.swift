import AppKit
import XCTest
@testable import CodexNotesCore
@testable import CodexNotesProbe

@MainActor
final class CloseButtonHoverHintControllerTests: XCTestCase {
    func testHintAppearsAtExactlyPointThreeSeconds() throws {
        let restoreLanguage = selectSimplifiedChinese()
        defer { restoreLanguage() }
        let context = try makeVisibleWindow()
        let scheduler = TestScheduler()
        let presenter = TestPresenter()
        let controller = makeController(scheduler: scheduler, presenter: presenter)
        controller.attach(to: context.button, in: context.window)

        controller.pointerEntered()
        XCTAssertEqual(scheduler.scheduledDelays, [0.30])
        scheduler.advance(by: 0.299)
        XCTAssertEqual(presenter.presentedMessages, [])

        scheduler.advance(by: 0.001)
        XCTAssertEqual(presenter.presentedMessages, ["隐藏 CodexNotes"])
    }

    private func selectSimplifiedChinese() -> () -> Void {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: AppLanguagePreference.key)
        AppLanguagePreference.save(.simplifiedChinese, to: defaults)
        return {
            if let previousValue {
                defaults.set(previousValue, forKey: AppLanguagePreference.key)
            } else {
                defaults.removeObject(forKey: AppLanguagePreference.key)
            }
        }
    }

    func testExitBeforeDelayCancelsPresentation() throws {
        let context = try makeVisibleWindow()
        let scheduler = TestScheduler()
        let presenter = TestPresenter()
        let controller = makeController(scheduler: scheduler, presenter: presenter)
        controller.attach(to: context.button, in: context.window)

        controller.pointerEntered()
        scheduler.advance(by: 0.299)
        controller.pointerExited()
        scheduler.advance(by: 1)

        XCTAssertEqual(presenter.presentedMessages, [])
        XCTAssertEqual(presenter.dismissCount, 2)
    }

    func testExitAfterPresentationDismissesImmediately() throws {
        let context = try makeVisibleWindow()
        let scheduler = TestScheduler()
        let presenter = TestPresenter()
        let controller = makeController(scheduler: scheduler, presenter: presenter)
        controller.attach(to: context.button, in: context.window)

        controller.pointerEntered()
        scheduler.advance(by: 0.30)
        XCTAssertEqual(presenter.presentedMessages.count, 1)

        controller.pointerExited()
        XCTAssertEqual(presenter.dismissCount, 2)
    }

    func testAttachInstallsRequiredTrackingOptionsExactlyOnce() throws {
        let context = try makeVisibleWindow()
        let scheduler = TestScheduler()
        let presenter = TestPresenter()
        let controller = makeController(scheduler: scheduler, presenter: presenter)

        controller.attach(to: context.button, in: context.window)
        controller.attach(to: context.button, in: context.window)

        let ownedAreas = context.button.trackingAreas.filter {
            $0.owner === controller
        }
        let area = try XCTUnwrap(ownedAreas.first)
        XCTAssertEqual(ownedAreas.count, 1)
        XCTAssertTrue(area.options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(area.options.contains(.activeAlways))
        XCTAssertTrue(area.options.contains(.inVisibleRect))
        XCTAssertNil(context.button.toolTip)

        controller.pointerEntered()
        XCTAssertEqual(scheduler.pendingActionCount, 1)
    }

    func testDetachRemovesTrackingAreaAndCancelsPendingHint() throws {
        let context = try makeVisibleWindow()
        let scheduler = TestScheduler()
        let presenter = TestPresenter()
        let controller = makeController(scheduler: scheduler, presenter: presenter)
        controller.attach(to: context.button, in: context.window)
        controller.pointerEntered()

        controller.detach()
        scheduler.advance(by: 1)

        XCTAssertFalse(context.button.trackingAreas.contains { $0.owner === controller })
        XCTAssertEqual(presenter.presentedMessages, [])
    }

    func testMouseEventsFromAReplacedTrackingAreaAreIgnored() throws {
        let originalContext = try makeVisibleWindow()
        let currentContext = try makeVisibleWindow()
        let scheduler = TestScheduler()
        let presenter = TestPresenter()
        let controller = makeController(scheduler: scheduler, presenter: presenter)
        controller.attach(to: originalContext.button, in: originalContext.window)
        let replacedArea = try XCTUnwrap(
            originalContext.button.trackingAreas.first { $0.owner === controller }
        )
        controller.attach(to: currentContext.button, in: currentContext.window)

        controller.pointerEntered(from: replacedArea)
        XCTAssertEqual(scheduler.pendingActionCount, 0)

        controller.pointerEntered()
        scheduler.advance(by: 0.30)
        let dismissCountBeforeStaleExit = presenter.dismissCount
        controller.pointerExited(from: replacedArea)

        XCTAssertEqual(presenter.dismissCount, dismissCountBeforeStaleExit)
        XCTAssertEqual(presenter.presentedMessages.count, 1)
    }

    func testHiddenWindowCancelsPendingHint() throws {
        let context = try makeVisibleWindow()
        let scheduler = TestScheduler()
        let presenter = TestPresenter()
        let controller = makeController(scheduler: scheduler, presenter: presenter)
        controller.attach(to: context.button, in: context.window)
        controller.pointerEntered()

        context.window.orderOut(nil)
        scheduler.advance(by: 1)

        XCTAssertEqual(presenter.presentedMessages, [])
    }

    func testCancelAndDismissClosesVisibleHintAndAllowsReentry() throws {
        let context = try makeVisibleWindow()
        let scheduler = TestScheduler()
        let presenter = TestPresenter()
        let controller = makeController(scheduler: scheduler, presenter: presenter)
        controller.attach(to: context.button, in: context.window)
        controller.pointerEntered()
        scheduler.advance(by: 0.30)

        controller.cancelAndDismiss()
        XCTAssertEqual(presenter.dismissCount, 2)

        controller.pointerEntered()
        scheduler.advance(by: 0.30)
        XCTAssertEqual(presenter.presentedMessages.count, 2)
    }

    private func makeController(
        scheduler: TestScheduler,
        presenter: TestPresenter
    ) -> CloseButtonHoverHintController {
        CloseButtonHoverHintController(
            scheduler: { delay, action in
                scheduler.schedule(after: delay, action: action)
            },
            presenter: presenter
        )
    }

    private func makeVisibleWindow() throws -> (window: NSWindow, button: NSButton) {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 500, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.orderFront(nil)
        XCTAssertTrue(window.isVisible)
        return (
            window,
            try XCTUnwrap(window.standardWindowButton(.closeButton))
        )
    }
}

@MainActor
private final class TestPresenter: CloseButtonHoverHintPresenting {
    private(set) var presentedMessages: [String] = []
    private(set) var dismissCount = 0

    func present(message: String, relativeTo button: NSButton) -> Bool {
        presentedMessages.append(message)
        return true
    }

    func dismiss() {
        dismissCount += 1
    }
}

@MainActor
private final class TestScheduler {
    private final class Token {
        var isCancelled = false
    }

    private struct Entry {
        let deadline: TimeInterval
        let token: Token
        let action: CloseButtonHoverHintController.ScheduledAction
    }

    private var now: TimeInterval = 0
    private var entries: [Entry] = []
    private(set) var scheduledDelays: [TimeInterval] = []

    var pendingActionCount: Int {
        entries.filter { !$0.token.isCancelled }.count
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping CloseButtonHoverHintController.ScheduledAction
    ) -> CloseButtonHoverHintController.Cancellation {
        let token = Token()
        entries.append(Entry(deadline: now + delay, token: token, action: action))
        scheduledDelays.append(delay)
        return {
            token.isCancelled = true
        }
    }

    func advance(by interval: TimeInterval) {
        now += interval
        let dueEntries = entries.filter { $0.deadline <= now }
        entries.removeAll { $0.deadline <= now }
        for entry in dueEntries where !entry.token.isCancelled {
            entry.action()
        }
    }
}
