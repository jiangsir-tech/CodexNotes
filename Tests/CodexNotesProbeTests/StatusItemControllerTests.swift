import AppKit
import CodexNotesCore
import XCTest
@testable import CodexNotesProbe

final class StatusItemControllerTests: XCTestCase {
    func testApplicationPresentationUsesAccessoryPolicy() {
        XCTAssertEqual(CodexNotesApplicationPresentation.activationPolicy, .accessory)
        XCTAssertTrue(CodexNotesApplicationPresentation.isSatisfied(by: .accessory))
        XCTAssertFalse(CodexNotesApplicationPresentation.isSatisfied(by: .regular))
        XCTAssertFalse(CodexNotesApplicationPresentation.isSatisfied(by: .prohibited))
    }

    func testHiddenWindowShows() {
        XCTAssertEqual(
            action(isWindowVisible: false),
            .show
        )
    }

    func testHiddenApplicationShowsWindow() {
        XCTAssertEqual(
            action(
                isApplicationHidden: true,
                isWindowVisible: true
            ),
            .show
        )
    }

    func testMiniaturizedWindowShows() {
        XCTAssertEqual(
            action(
                isWindowVisible: true,
                isWindowMiniaturized: true
            ),
            .show
        )
    }

    func testVisibleWindowHides() {
        XCTAssertEqual(
            action(isWindowVisible: true),
            .hide
        )
    }

    func testVisibleInactiveNonKeyWindowStillHidesWithOneClick() {
        XCTAssertEqual(
            action(isWindowVisible: true),
            .hide
        )
    }

    func testVisibleSettingsAlwaysSwitchesBackToMainWindow() {
        XCTAssertEqual(
            action(
                isWindowVisible: true,
                isSettingsVisible: true
            ),
            .show
        )
    }

    func testManualHideOverridesAutomaticVisibilityUntilShowResumesFollowing() {
        var state = MainWindowVisibilityState()
        XCTAssertEqual(state.preference, .automatic)
        XCTAssertTrue(
            state.shouldShow(
                automaticVisibilityAllowed: true,
                isSettingsVisible: false
            )
        )
        XCTAssertFalse(
            state.shouldShow(
                automaticVisibilityAllowed: false,
                isSettingsVisible: false
            )
        )

        state.recordManualHide()
        XCTAssertEqual(state.preference, .hidden)
        XCTAssertFalse(
            state.shouldShow(
                automaticVisibilityAllowed: true,
                isSettingsVisible: false
            )
        )

        state.recordManualShow()
        XCTAssertEqual(state.preference, .automatic)
        XCTAssertFalse(
            state.shouldShow(
                automaticVisibilityAllowed: false,
                isSettingsVisible: false
            )
        )
        XCTAssertTrue(
            state.shouldShow(
                automaticVisibilityAllowed: true,
                isSettingsVisible: false
            )
        )
        XCTAssertFalse(
            state.shouldShow(
                automaticVisibilityAllowed: true,
                isSettingsVisible: true
            )
        )
    }

    func testAwaitingCodexActivationSuppressesWindowUntilCompleted() {
        var state = MainWindowVisibilityState()
        state.recordManualHide()
        let requestID = UUID()
        state.beginCodexActivation(requestID: requestID)

        XCTAssertEqual(state.preference, .automatic)
        XCTAssertTrue(state.isAwaitingCodexActivation)
        XCTAssertTrue(state.isCurrentCodexActivationRequest(requestID))
        XCTAssertFalse(
            state.shouldShow(
                automaticVisibilityAllowed: true,
                isSettingsVisible: false
            )
        )

        XCTAssertTrue(state.completeCodexActivation(requestID: requestID))
        XCTAssertFalse(state.isAwaitingCodexActivation)
        XCTAssertTrue(
            state.shouldShow(
                automaticVisibilityAllowed: true,
                isSettingsVisible: false
            )
        )
    }

    func testStaleActivationCompletionCannotClearNewRequest() {
        var state = MainWindowVisibilityState()
        let oldRequestID = UUID()
        let currentRequestID = UUID()

        state.beginCodexActivation(requestID: oldRequestID)
        state.beginCodexActivation(requestID: currentRequestID)

        XCTAssertFalse(
            state.completeCodexActivation(requestID: oldRequestID)
        )
        XCTAssertTrue(state.isCurrentCodexActivationRequest(currentRequestID))
        XCTAssertTrue(
            state.completeCodexActivation(requestID: currentRequestID)
        )
        XCTAssertFalse(state.isAwaitingCodexActivation)
    }

    func testManualHideCancelsPendingActivationRequest() {
        var state = MainWindowVisibilityState()
        let requestID = state.beginCodexActivation()

        state.recordManualHide()

        XCTAssertEqual(state.preference, .hidden)
        XCTAssertFalse(state.isAwaitingCodexActivation)
        XCTAssertFalse(state.isCurrentCodexActivationRequest(requestID))
    }

    func testLeftClickTogglesWindow() {
        XCTAssertEqual(
            StatusItemInteractionPolicy.interaction(for: .leftMouseUp),
            .toggleWindow
        )
    }

    func testRightClickShowsQuitMenuWithoutTogglingWindow() {
        XCTAssertEqual(
            StatusItemInteractionPolicy.interaction(for: .rightMouseUp),
            .showQuitMenu
        )
    }

    func testControlLeftClickAlsoShowsQuitMenu() {
        XCTAssertEqual(
            StatusItemInteractionPolicy.interaction(
                for: .leftMouseUp,
                modifierFlags: .control
            ),
            .showQuitMenu
        )
    }

    @MainActor
    func testStatusItemUsesCodexPencilByDefault() {
        let suiteName = "StatusItemControllerTests.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = StatusItemController(
            defaults: defaults,
            iconProvider: { _ in NSImage(size: NSSize(width: 20, height: 20)) }
        )

        XCTAssertEqual(controller.currentIconID, .codexPencil)
    }

    @MainActor
    func testStatusItemRefreshesWhenSavedPreferenceChanges() {
        let suiteName = "StatusItemControllerTests.change.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var providedIcons: [StatusBarIconID] = []
        let controller = StatusItemController(
            defaults: defaults,
            iconProvider: { icon in
                providedIcons.append(icon)
                return NSImage(size: NSSize(width: 20, height: 20))
            }
        )

        StatusBarIconPreference.save(.chatGPTPencil, to: defaults)
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: defaults
        )

        XCTAssertEqual(controller.currentIconID, .chatGPTPencil)
        XCTAssertEqual(providedIcons, [.codexPencil, .chatGPTPencil])
    }

    @MainActor
    func testStatusItemRefreshesLocalizedContentAndReloadsSameIcon() {
        let suiteName = "StatusItemControllerTests.language.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppLanguagePreference.save(.simplifiedChinese, to: defaults)
        var providedIcons: [StatusBarIconID] = []
        let controller = StatusItemController(
            defaults: defaults,
            iconProvider: { icon in
                providedIcons.append(icon)
                return NSImage(size: NSSize(width: 20, height: 20))
            }
        )
        let chinese = AppLocalization(preference: .simplifiedChinese)

        XCTAssertEqual(
            controller.currentToolTip,
            chinese.text(.statusItemTooltip)
        )
        XCTAssertEqual(
            controller.currentAccessibilityHelp,
            chinese.text(.statusItemAccessibilityHelp)
        )
        XCTAssertEqual(
            controller.currentQuitMenuTitle,
            chinese.text(.statusItemQuit)
        )
        XCTAssertEqual(controller.quitMenuItemCount, 1)
        XCTAssertEqual(providedIcons, [.codexPencil])

        AppLanguagePreference.save(.english, to: defaults)
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: defaults
        )

        let english = AppLocalization(preference: .english)
        XCTAssertEqual(
            controller.currentToolTip,
            english.text(.statusItemTooltip)
        )
        XCTAssertEqual(
            controller.currentAccessibilityHelp,
            english.text(.statusItemAccessibilityHelp)
        )
        XCTAssertEqual(
            controller.currentQuitMenuTitle,
            english.text(.statusItemQuit)
        )
        XCTAssertEqual(controller.quitMenuItemCount, 1)
        XCTAssertEqual(providedIcons, [.codexPencil, .codexPencil])

        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
        XCTAssertEqual(controller.quitMenuItemCount, 1)
        XCTAssertEqual(providedIcons, [.codexPencil, .codexPencil])
    }

    @MainActor
    func testCloseEducationPresentsOnlyOnceAndPersistsAcrossControllers() async {
        let suiteName = "StatusItemControllerTests.closeEducation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var presentationCount = 0

        var controller: StatusItemController? = StatusItemController(
            defaults: defaults,
            iconProvider: { _ in NSImage(size: NSSize(width: 20, height: 20)) },
            closeEducationPresenter: { _ in
                presentationCount += 1
                return true
            }
        )
        XCTAssertNotNil(controller)
        NotificationCenter.default.post(
            name: MainWindowCommandNotification.hiddenUsingCloseButton,
            object: nil
        )
        NotificationCenter.default.post(
            name: MainWindowCommandNotification.hiddenUsingCloseButton,
            object: nil
        )
        await drainMainQueue()

        XCTAssertEqual(presentationCount, 1)
        XCTAssertTrue(defaults.bool(forKey: StatusItemCloseEducationPreference.key))

        controller = nil
        let recreatedController = StatusItemController(
            defaults: defaults,
            iconProvider: { _ in NSImage(size: NSSize(width: 20, height: 20)) },
            closeEducationPresenter: { _ in
                presentationCount += 1
                return true
            }
        )
        NotificationCenter.default.post(
            name: MainWindowCommandNotification.hiddenUsingCloseButton,
            object: nil
        )
        await drainMainQueue()

        XCTAssertEqual(presentationCount, 1)
        withExtendedLifetime(recreatedController) {}
    }

    @MainActor
    func testFailedCloseEducationPresentationDoesNotConsumePreference() async {
        let suiteName = "StatusItemControllerTests.closeEducationFailure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var presentationCount = 0
        let controller = StatusItemController(
            defaults: defaults,
            iconProvider: { _ in NSImage(size: NSSize(width: 20, height: 20)) },
            closeEducationPresenter: { _ in
                presentationCount += 1
                return false
            }
        )

        NotificationCenter.default.post(
            name: MainWindowCommandNotification.hiddenUsingCloseButton,
            object: nil
        )
        await drainMainQueue()
        NotificationCenter.default.post(
            name: MainWindowCommandNotification.hiddenUsingCloseButton,
            object: nil
        )
        await drainMainQueue()

        XCTAssertEqual(presentationCount, 2)
        XCTAssertFalse(defaults.bool(forKey: StatusItemCloseEducationPreference.key))
        withExtendedLifetime(controller) {}
    }

    @MainActor
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }

    private func action(
        isApplicationHidden: Bool = false,
        isWindowVisible: Bool,
        isWindowMiniaturized: Bool = false,
        isSettingsVisible: Bool = false
    ) -> MainWindowToggleAction {
        MainWindowTogglePolicy.action(
            isApplicationHidden: isApplicationHidden,
            isWindowVisible: isWindowVisible,
            isWindowMiniaturized: isWindowMiniaturized,
            isSettingsVisible: isSettingsVisible
        )
    }
}
