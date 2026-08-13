import CodexNotesCore

enum MainWindowCompactAction: Equatable, Sendable {
    case none
    case collapse
    case expand
}

enum MainWindowCollapseOrigin: Equatable, Sendable {
    case automatic
    case manual
}

/// Pure interaction state for coordinating Codex's right panel with the notes
/// window. The caller remains responsible for applying the returned window
/// action and for reporting every user-initiated toggle or show operation.
struct MainWindowCompactState: Equatable, Sendable {
    private(set) var lastDefiniteRightPanelState: CodexRightPanelState = .unknown
    private(set) var collapseOrigin: MainWindowCollapseOrigin?
    private(set) var hasHandledCurrentOpenCycle = false
    private(set) var userOverrodeCurrentOpenCycle = false
    /// Snapshot of the compact/expanded state immediately before the current
    /// right-panel cycle began. Window visibility is deliberately separate:
    /// restoring an expanded frame must never show a window the user hid.
    private(set) var wasExpandedBeforeCurrentOpenCycle: Bool?

    /// Establishes a low-level baseline without producing a window action.
    /// User-visible initial observations should go through `observeRightPanel`
    /// so an already-open panel can claim its one automatic action.
    mutating func seedRightPanel(_ state: CodexRightPanelState) {
        lastDefiniteRightPanelState = state
        collapseOrigin = nil
        userOverrodeCurrentOpenCycle = false
        hasHandledCurrentOpenCycle = state == .open
        wasExpandedBeforeCurrentOpenCycle = nil
    }

    /// Observes either a bootstrap snapshot or an incremental panel event.
    /// The first definite `open` in each open cycle is eligible for one
    /// automatic collapse, including an initial observation or a recovery from
    /// `unknown`. `unknown` never resets an already-handled open cycle.
    @discardableResult
    mutating func observeRightPanel(
        _ state: CodexRightPanelState,
        isWindowVisible: Bool,
        isCollapsed: Bool,
        isInitialObservation: Bool = false
    ) -> MainWindowCompactAction {
        switch state {
        case .unknown:
            return .none

        case .closed:
            // Treat the right panel as a temporary workspace. If CodexNotes was
            // expanded before that workspace opened, restore it even when the
            // user briefly expanded and re-collapsed the notes while inspecting
            // the panel. A window that was already compact before the cycle only
            // remains expanded when it is still expanded at close time.
            let shouldRestorePreOpenExpandedState =
                lastDefiniteRightPanelState == .open
                && wasExpandedBeforeCurrentOpenCycle == true

            lastDefiniteRightPanelState = .closed
            hasHandledCurrentOpenCycle = false
            userOverrodeCurrentOpenCycle = false
            wasExpandedBeforeCurrentOpenCycle = nil

            if shouldRestorePreOpenExpandedState
                || collapseOrigin == .automatic {
                collapseOrigin = nil
            } else if !isCollapsed {
                collapseOrigin = nil
            }

            // Return an idempotent expand even when the window still appears
            // expanded. The controller also uses this action to cancel a manual
            // collapse that may be waiting for an IME composition to finish.
            return shouldRestorePreOpenExpandedState ? .expand : .none

        case .open:
            lastDefiniteRightPanelState = .open
            guard !hasHandledCurrentOpenCycle else {
                return .none
            }

            hasHandledCurrentOpenCycle = true
            userOverrodeCurrentOpenCycle = false
            wasExpandedBeforeCurrentOpenCycle = !isCollapsed

            guard isWindowVisible, !isCollapsed else {
                return .none
            }

            collapseOrigin = .automatic
            return .collapse
        }
    }

    /// Records a click on the compact/expand title-bar control. The argument is
    /// the state before the click; the return value is the requested new state.
    @discardableResult
    mutating func recordManualToggle(
        isCollapsed: Bool
    ) -> MainWindowCompactAction {
        if isCollapsed {
            collapseOrigin = nil
            recordUserOverrideIfPanelIsOpen()
            return .expand
        }

        collapseOrigin = .manual
        recordUserOverrideIfPanelIsOpen()
        return .collapse
    }

    /// A deliberate show while the right panel is open means the user wants
    /// access to the notes. It cancels automatic ownership and expands an
    /// already-collapsed window, while leaving an expanded window unchanged.
    @discardableResult
    mutating func recordManualShow(
        isCollapsed: Bool
    ) -> MainWindowCompactAction {
        guard lastDefiniteRightPanelState == .open else {
            return .none
        }

        collapseOrigin = nil
        hasHandledCurrentOpenCycle = true
        userOverrodeCurrentOpenCycle = true
        return isCollapsed ? .expand : .none
    }

    /// Releases a collapse that CodexNotes owned when panel detection remains
    /// unavailable. Keep the current open cycle handled so a transient AX
    /// outage cannot make the same still-open sidebar collapse the window a
    /// second time after detection recovers.
    mutating func releaseAutomaticCollapseForUncertainty() {
        guard collapseOrigin == .automatic else { return }
        collapseOrigin = nil
        hasHandledCurrentOpenCycle = true
    }

    /// Stops participating in the current automatic avoidance cycle. A frame
    /// owned by automatic avoidance is restored only when the notes were
    /// expanded before the panel opened. Manual compact state is deliberately
    /// retained, because disabling the feature must not undo a title-bar click.
    @discardableResult
    mutating func disableAutomaticAvoidance(
        isCollapsed: Bool
    ) -> MainWindowCompactAction {
        let shouldRestoreAutomaticallyCollapsedWindow =
            collapseOrigin == .automatic
            && wasExpandedBeforeCurrentOpenCycle == true
            && isCollapsed

        if collapseOrigin == .automatic {
            collapseOrigin = nil
        }
        lastDefiniteRightPanelState = .unknown
        hasHandledCurrentOpenCycle = false
        userOverrodeCurrentOpenCycle = false
        wasExpandedBeforeCurrentOpenCycle = nil

        return shouldRestoreAutomaticallyCollapsedWindow ? .expand : .none
    }

    private mutating func recordUserOverrideIfPanelIsOpen() {
        guard lastDefiniteRightPanelState == .open else {
            return
        }
        hasHandledCurrentOpenCycle = true
        userOverrodeCurrentOpenCycle = true
    }
}
