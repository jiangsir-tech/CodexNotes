import XCTest
@testable import CodexNotesProbe

final class MainWindowCompactStateTests: XCTestCase {
    func testUnknownObservationDoesNotTriggerOrBecomeAClosedBaseline() {
        var state = MainWindowCompactState()

        XCTAssertEqual(
            state.observeRightPanel(
                .unknown,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .unknown)
        XCTAssertFalse(state.hasHandledCurrentOpenCycle)
    }

    func testFirstOpenObservationCollapsesVisibleExpandedWindow() {
        var state = MainWindowCompactState()

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .collapse
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .open)
        XCTAssertTrue(state.hasHandledCurrentOpenCycle)
        XCTAssertEqual(state.collapseOrigin, .automatic)
    }

    func testExplicitInitialOpenObservationCollapsesVisibleExpandedWindow() {
        var state = MainWindowCompactState()

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false,
                isInitialObservation: true
            ),
            .collapse
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .open)
        XCTAssertTrue(state.hasHandledCurrentOpenCycle)
        XCTAssertEqual(state.collapseOrigin, .automatic)
    }

    func testIncrementalClosedToOpenCollapsesVisibleExpandedWindow() {
        var state = MainWindowCompactState()
        state.seedRightPanel(.closed)

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .collapse
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .open)
        XCTAssertEqual(state.collapseOrigin, .automatic)
        XCTAssertTrue(state.hasHandledCurrentOpenCycle)
        XCTAssertFalse(state.userOverrodeCurrentOpenCycle)
    }

    func testRepeatedOpenWithinSameCycleDoesNotCollapseAgain() {
        var state = automaticallyCollapsedState()

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )
        XCTAssertEqual(state.collapseOrigin, .automatic)
    }

    func testUnknownDuringOpenCycleDoesNotResetCycleOrCauseRetrigger() {
        var state = automaticallyCollapsedState()

        XCTAssertEqual(
            state.observeRightPanel(
                .unknown,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .none
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .open)
        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )
    }

    func testUnknownThenFirstOpenCollapsesOnceInCurrentCycle() {
        var state = MainWindowCompactState()
        state.seedRightPanel(.closed)

        XCTAssertEqual(
            state.observeRightPanel(
                .unknown,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )
        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .collapse
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .open)
        XCTAssertEqual(state.collapseOrigin, .automatic)

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )
    }

    func testFailOpenReleaseDoesNotRehandleTheSameOpenCycle() {
        var state = automaticallyCollapsedState()

        state.releaseAutomaticCollapseForUncertainty()

        XCTAssertNil(state.collapseOrigin)
        XCTAssertTrue(state.hasHandledCurrentOpenCycle)
        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )

        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .expand
        )
        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .collapse
        )
    }

    func testOpenObservationForAnotherSelectionDoesNotResetHandledCycle() {
        var state = automaticallyCollapsedState()

        // A task-selection change is not a right-panel close. Consumers must
        // preserve this state and report the still-open panel normally.
        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )
        XCTAssertTrue(state.hasHandledCurrentOpenCycle)
        XCTAssertEqual(state.collapseOrigin, .automatic)
    }

    func testExpandedBeforeOpenAndCollapsedAtCloseRestoresExpandedState() {
        var state = automaticallyCollapsedState()

        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .expand
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .closed)
        XCTAssertNil(state.collapseOrigin)
        XCTAssertFalse(state.hasHandledCurrentOpenCycle)
        XCTAssertFalse(state.userOverrodeCurrentOpenCycle)
    }

    func testExpandedBeforeOpenAndExpandedAtCloseStaysExpanded() {
        var state = automaticallyCollapsedState()

        XCTAssertEqual(state.recordManualToggle(isCollapsed: true), .expand)
        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .expand
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .closed)
        XCTAssertNil(state.collapseOrigin)
        XCTAssertFalse(state.hasHandledCurrentOpenCycle)
        XCTAssertFalse(state.userOverrodeCurrentOpenCycle)
    }

    func testCollapsedBeforeOpenAndCollapsedAtCloseStaysCollapsed() {
        var state = MainWindowCompactState()
        state.seedRightPanel(.closed)

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .none
        )
        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .none
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .closed)
        XCTAssertNil(state.collapseOrigin)
        XCTAssertFalse(state.hasHandledCurrentOpenCycle)
        XCTAssertFalse(state.userOverrodeCurrentOpenCycle)
    }

    func testCollapsedBeforeOpenAndExpandedAtCloseStaysExpanded() {
        var state = MainWindowCompactState()
        state.seedRightPanel(.closed)

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .none
        )
        XCTAssertEqual(state.recordManualToggle(isCollapsed: true), .expand)
        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .closed)
        XCTAssertNil(state.collapseOrigin)
        XCTAssertFalse(state.hasHandledCurrentOpenCycle)
        XCTAssertFalse(state.userOverrodeCurrentOpenCycle)
    }

    func testExpandedBeforeOpenIsRestoredAfterManualExpandThenCollapse() {
        var state = automaticallyCollapsedState()

        XCTAssertEqual(state.recordManualToggle(isCollapsed: true), .expand)
        XCTAssertEqual(state.recordManualToggle(isCollapsed: false), .collapse)
        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .expand
        )
        XCTAssertEqual(state.lastDefiniteRightPanelState, .closed)
        XCTAssertNil(state.collapseOrigin)
        XCTAssertFalse(state.hasHandledCurrentOpenCycle)
        XCTAssertFalse(state.userOverrodeCurrentOpenCycle)
    }

    func testPanelCanAutomaticallyCollapseAgainInANewOpenCycle() {
        var state = automaticallyCollapsedState()
        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .expand
        )

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .collapse
        )
        XCTAssertEqual(state.collapseOrigin, .automatic)
    }

    func testManualExpandDuringOpenCycleKeepsWindowExpandedAtClose() {
        var state = automaticallyCollapsedState()

        XCTAssertEqual(state.recordManualToggle(isCollapsed: true), .expand)
        XCTAssertTrue(state.userOverrodeCurrentOpenCycle)
        XCTAssertNil(state.collapseOrigin)
        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )
        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .expand
        )
    }

    func testManualCollapseWithNoExpandedPreOpenBaselineStaysCollapsed() {
        var state = MainWindowCompactState()
        state.seedRightPanel(.closed)

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .none
        )
        XCTAssertEqual(state.recordManualToggle(isCollapsed: true), .expand)

        XCTAssertEqual(state.recordManualToggle(isCollapsed: false), .collapse)
        XCTAssertEqual(state.collapseOrigin, .manual)
        XCTAssertTrue(state.userOverrodeCurrentOpenCycle)
        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .none
        )
        XCTAssertEqual(state.collapseOrigin, .manual)
    }

    func testManualShowExpandsAutomaticCollapseAndOverridesOpenCycle() {
        var state = automaticallyCollapsedState()

        XCTAssertEqual(state.recordManualShow(isCollapsed: true), .expand)
        XCTAssertNil(state.collapseOrigin)
        XCTAssertTrue(state.hasHandledCurrentOpenCycle)
        XCTAssertTrue(state.userOverrodeCurrentOpenCycle)
        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .expand
        )
    }

    func testManualShowLeavesExpandedWindowExpandedAndOverridesOpenCycle() {
        var state = MainWindowCompactState()
        state.seedRightPanel(.open)

        XCTAssertEqual(state.recordManualShow(isCollapsed: false), .none)
        XCTAssertTrue(state.userOverrodeCurrentOpenCycle)
        XCTAssertTrue(state.hasHandledCurrentOpenCycle)
    }

    func testManualShowOutsideOpenCycleDoesNotChangeCompactState() {
        var state = MainWindowCompactState()
        state.seedRightPanel(.closed)

        XCTAssertEqual(state.recordManualShow(isCollapsed: true), .none)
        XCTAssertEqual(state.lastDefiniteRightPanelState, .closed)
        XCTAssertFalse(state.userOverrodeCurrentOpenCycle)
    }

    func testOpenWhileWindowHiddenConsumesCycleWithoutCollapsingLater() {
        var state = MainWindowCompactState()
        state.seedRightPanel(.closed)

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: false,
                isCollapsed: false
            ),
            .none
        )
        XCTAssertTrue(state.hasHandledCurrentOpenCycle)
        XCTAssertNil(state.collapseOrigin)
        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .none
        )
        XCTAssertEqual(state.recordManualShow(isCollapsed: false), .none)
        XCTAssertTrue(state.userOverrodeCurrentOpenCycle)
    }

    func testOpenWhileAlreadyCollapsedDoesNotClaimAutomaticOwnership() {
        var state = MainWindowCompactState()
        XCTAssertEqual(state.recordManualToggle(isCollapsed: false), .collapse)
        state.seedRightPanel(.closed)
        XCTAssertEqual(state.recordManualToggle(isCollapsed: false), .collapse)

        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .none
        )
        XCTAssertEqual(state.collapseOrigin, .manual)
        XCTAssertEqual(
            state.observeRightPanel(
                .closed,
                isWindowVisible: true,
                isCollapsed: true
            ),
            .none
        )
    }

    func testDisablingAvoidanceRestoresAutomaticallyOwnedExpandedBaseline() {
        var state = automaticallyCollapsedState()

        XCTAssertEqual(
            state.disableAutomaticAvoidance(isCollapsed: true),
            .expand
        )
        XCTAssertNil(state.collapseOrigin)
        XCTAssertEqual(state.lastDefiniteRightPanelState, .unknown)
        XCTAssertNil(state.wasExpandedBeforeCurrentOpenCycle)
        XCTAssertFalse(state.hasHandledCurrentOpenCycle)
    }

    func testDisablingAvoidanceCancelsPendingAutomaticCollapseWithoutExpanding() {
        var state = automaticallyCollapsedState()

        XCTAssertEqual(
            state.disableAutomaticAvoidance(isCollapsed: false),
            .none
        )
        XCTAssertNil(state.collapseOrigin)
        XCTAssertEqual(state.lastDefiniteRightPanelState, .unknown)
    }

    func testDisablingAvoidanceDoesNotUndoManualCollapseDuringOpenCycle() {
        var state = automaticallyCollapsedState()
        XCTAssertEqual(state.recordManualToggle(isCollapsed: true), .expand)
        XCTAssertEqual(state.recordManualToggle(isCollapsed: false), .collapse)
        XCTAssertEqual(state.collapseOrigin, .manual)

        XCTAssertEqual(
            state.disableAutomaticAvoidance(isCollapsed: true),
            .none
        )
        XCTAssertEqual(state.collapseOrigin, .manual)
        XCTAssertEqual(state.lastDefiniteRightPanelState, .unknown)
        XCTAssertNil(state.wasExpandedBeforeCurrentOpenCycle)
    }

    private func automaticallyCollapsedState() -> MainWindowCompactState {
        var state = MainWindowCompactState()
        state.seedRightPanel(.closed)
        XCTAssertEqual(
            state.observeRightPanel(
                .open,
                isWindowVisible: true,
                isCollapsed: false
            ),
            .collapse
        )
        return state
    }
}
