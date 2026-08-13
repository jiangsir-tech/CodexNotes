import AppKit
import Combine
import CodexNotesCore
import QuartzCore

enum MainWindowCompactGeometry {
    static func compactFrame(
        from expandedFrame: NSRect,
        compactWidth: CGFloat,
        compactHeight: CGFloat
    ) -> NSRect {
        let width = max(1, min(compactWidth, expandedFrame.width))
        let height = max(1, min(compactHeight, expandedFrame.height))
        return NSRect(
            x: expandedFrame.maxX - width,
            y: expandedFrame.maxY - height,
            width: width,
            height: height
        )
    }

    static func expandedFrame(
        from compactFrame: NSRect,
        cachedExpandedFrame: NSRect
    ) -> NSRect {
        NSRect(
            x: compactFrame.maxX - cachedExpandedFrame.width,
            y: compactFrame.maxY - cachedExpandedFrame.height,
            width: cachedExpandedFrame.width,
            height: cachedExpandedFrame.height
        )
    }

    static func expandedFrame(
        from compactFrame: NSRect,
        cachedExpandedFrame: NSRect,
        constrainedTo visibleFrame: NSRect
    ) -> NSRect {
        let unconstrained = expandedFrame(
            from: compactFrame,
            cachedExpandedFrame: cachedExpandedFrame
        )
        let size = NSSize(
            width: min(unconstrained.width, visibleFrame.width),
            height: min(unconstrained.height, visibleFrame.height)
        )
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        return NSRect(
            x: min(max(unconstrained.minX, visibleFrame.minX), maximumX),
            y: min(max(unconstrained.minY, visibleFrame.minY), maximumY),
            width: size.width,
            height: size.height
        )
    }
}

private enum MainWindowExpandedFramePositioning {
    /// A deliberate user expansion follows the current compact bar, so moving
    /// the bar remains a useful way to choose where the full window reappears.
    case followCompactBar

    /// An automatic expansion is the inverse of an automatic collapse. Restore
    /// the complete cached frame without treating incidental compact-bar layout
    /// changes as a user move. Fall back to the bar only when that cached frame
    /// is no longer visible on any current display.
    case restoreCachedFrameIfVisible
}

@MainActor
final class MainWindowCompactController: ObservableObject {
    static let minimumExpandedContentSize = NSSize(width: 340, height: 520)
    /// The compact window is a top-right anchored pill containing only the
    /// centered app title and the expand chevron. This leaves comfortable
    /// native-titlebar spacing without covering a full column of Codex.
    static let compactWindowWidth: CGFloat = 190
    // Keep a small content sliver below the native titlebar. A 1pt sliver makes
    // the 28pt titlebar accessory extend past the compact window by roughly one
    // point on current macOS builds, which can clip the chevron while AppKit is
    // laying out the final frame.
    static let compactContentHeight: CGFloat = 3
    // AppKit briefly composites a near-zero-height native titlebar as a bare
    // line when an NSWindow frame is animated down to titlebar-only height.
    // The artifact survives ordering and SwiftUI layout fixes, so compact frame
    // changes are deliberately atomic. Other accessibility motion behavior is
    // still respected by the rest of the app.
    static let animatesCompactFrameTransitions = false
    static let transitionDuration: TimeInterval = 0.18
    static let unknownFailOpenDelay: TimeInterval = 1
    // Window-level opacity is required here: changing only backgroundColor does
    // not affect AppKit's native titlebar chrome. Hover or keyboard focus raises
    // contrast while the resting bar stays translucent enough to reveal Codex.
    static let restingWindowOpacity: CGFloat = 0.42
    static let activeWindowOpacity: CGFloat = 0.68

    @Published private(set) var isCollapsed = false
    @Published private(set) var isCompactContentPresentationActive = false
    private(set) var isAutomaticAvoidanceEnabled =
        RightPanelAvoidancePreference.defaultValue

    private weak var window: NSWindow?
    private weak var editorController: MarkdownEditorController?
    private var interactionState = MainWindowCompactState()
    private var expandedFrame: NSRect?
    private var isTransitioning = false
    private var transitionTargetIsCollapsed: Bool?
    private var pendingTransitionAction: (
        action: MainWindowCompactAction,
        automatic: Bool
    )?
    private var pendingAutomaticCollapse = false
    private var pendingManualCollapse = false
    private var pendingRetryWorkItem: DispatchWorkItem?
    private var unknownFailOpenWorkItem: DispatchWorkItem?
    private var latestRightPanelObservation: CodexRightPanelState = .unknown
    private var windowObservers: [NSObjectProtocol] = []
    private var backgroundColor = NSColor.windowBackgroundColor
    private var expandedWindowAlpha: CGFloat?
    private var expandedTitlebarSeparatorStyle: NSTitlebarSeparatorStyle?
    private var reduceMotion = false
    private var reduceTransparency = false
    private var isPointerInside = false
    private var transitionID = UUID()
    private let framePersistenceDefaults: UserDefaults
    private let accessoryController = MainWindowCompactAccessoryController()
    private let hoverController = MainWindowCompactHoverController()

    init(framePersistenceDefaults: UserDefaults = .standard) {
        self.framePersistenceDefaults = framePersistenceDefaults
    }

    var compactStateDidChange: ((Bool) -> Void)?

    var shouldPersistCurrentFrame: Bool {
        !isCollapsed && !isTransitioning
    }

    var isRightPanelOpen: Bool {
        interactionState.lastDefiniteRightPanelState == .open
    }

    private var effectiveIsCollapsed: Bool {
        transitionTargetIsCollapsed ?? isCollapsed
    }

    /// The compact chrome is intentionally a resting-state appearance. Applying
    /// transparent titlebar chrome while AppKit is still shrinking the window
    /// leaves an empty, near-transparent frame whose border reads as a single
    /// line. Keep ordinary chrome throughout both animation directions and only
    /// switch to the translucent compact bar after the frame has settled.
    private var usesCompactAppearance: Bool {
        isCollapsed && !isTransitioning
    }

    func attach(
        to window: NSWindow,
        editorController: MarkdownEditorController,
        backgroundColor: NSColor,
        reduceMotion: Bool,
        reduceTransparency: Bool
    ) {
        if self.editorController !== editorController {
            self.editorController?.textCompositionDidEnd = nil
        }
        if self.window !== window {
            detach()
            self.window = window
            self.editorController = editorController
            expandedWindowAlpha = window.alphaValue
            expandedTitlebarSeparatorStyle = window.titlebarSeparatorStyle
            installWindowObservers(for: window)
            accessoryController.attach(to: window) { [weak self] in
                self?.toggleFromTitlebar()
            }
            hoverController.attach(to: window) { [weak self] isInside in
                guard let self else { return }
                self.isPointerInside = isInside
                self.applyAppearance()
            }
        } else {
            self.editorController = editorController
            accessoryController.ensureAttached(to: window)
            hoverController.ensureAttached(to: window)
        }
        editorController.textCompositionDidEnd = { [weak self] in
            self?.retryPendingCollapseIfPossible()
        }

        updateConfiguration(
            backgroundColor: backgroundColor,
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
        accessoryController.update(
            isCollapsed: isCollapsed,
            isEnabled: !isTransitioning
        )
    }

    func detach() {
        pendingRetryWorkItem?.cancel()
        pendingRetryWorkItem = nil
        cancelUnknownFailOpen()
        pendingAutomaticCollapse = false
        pendingManualCollapse = false
        pendingTransitionAction = nil
        transitionTargetIsCollapsed = nil
        compactStateDidChange = nil
        transitionID = UUID()
        if let window, isCollapsed {
            let cachedFrame = expandedFrame ?? window.frame
            let positioning: MainWindowExpandedFramePositioning =
                interactionState.collapseOrigin == .automatic
                    ? .restoreCachedFrameIfVisible
                    : .followCompactBar
            let restoredFrame = targetExpandedFrame(
                for: window,
                cachedFrame: cachedFrame,
                positioning: positioning
            )
            window.styleMask.insert(.resizable)
            window.contentMinSize = Self.minimumExpandedContentSize
            setFrameImmediatelyCancellingAnimation(
                restoredFrame,
                on: window,
                display: false
            )
            isCollapsed = false
            isCompactContentPresentationActive = false
            applyStandardButtonVisibility(isCompact: false)
            applyAppearance()
        }
        isCompactContentPresentationActive = false
        applyStandardButtonVisibility(isCompact: false)
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers.removeAll()
        accessoryController.detach()
        hoverController.detach()
        editorController?.textCompositionDidEnd = nil
        window = nil
        editorController = nil
        expandedFrame = nil
        expandedWindowAlpha = nil
        expandedTitlebarSeparatorStyle = nil
        isPointerInside = false
        isTransitioning = false
        interactionState = MainWindowCompactState()
    }

    func updateConfiguration(
        backgroundColor: NSColor,
        reduceMotion: Bool,
        reduceTransparency: Bool
    ) {
        self.backgroundColor = backgroundColor
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        accessoryController.update(
            isCollapsed: isCollapsed,
            isEnabled: !isTransitioning
        )
        applyStandardButtonVisibility(isCompact: isCollapsed)
        applyAppearance()
    }

    func seedRightPanel(_ state: CodexRightPanelState) {
        cancelUnknownFailOpen()
        latestRightPanelObservation = state
        pendingAutomaticCollapse = false
        guard isAutomaticAvoidanceEnabled else { return }
        interactionState.seedRightPanel(state)
    }

    /// Enables or disables only Codex-driven compact actions. The title-bar
    /// toggle remains wired independently, so manual collapse/expand is always
    /// available. Disabling also cancels every deferred automatic action and
    /// restores a compact frame only when automatic avoidance owns it.
    func setAutomaticAvoidanceEnabled(_ isEnabled: Bool) {
        guard isAutomaticAvoidanceEnabled != isEnabled else { return }
        isAutomaticAvoidanceEnabled = isEnabled
        cancelUnknownFailOpen()
        pendingAutomaticCollapse = false
        if pendingTransitionAction?.automatic == true {
            pendingTransitionAction = nil
        }

        guard isEnabled else {
            let action = interactionState.disableAutomaticAvoidance(
                isCollapsed: effectiveIsCollapsed
            )
            perform(action, automatic: true)
            return
        }

        // Do not consume the last pre-disable sample. Settings changes and the
        // asynchronous SwiftUI window update have no guaranteed ordering, so a
        // cached `.open` could otherwise collapse the window after the sidebar
        // had already closed. The detector publishes a fresh observation for
        // the new preference generation.
        latestRightPanelObservation = .unknown
        interactionState.seedRightPanel(.unknown)
    }

    func selectionDidChange(seeding state: CodexRightPanelState) {
        // The right panel is physical window state, not task state. Preserve
        // the pre-open snapshot across task changes and only end the cycle on a
        // definite close. This branch is retained for compatibility with older
        // observation identities; the current producer uses one window identity.
        latestRightPanelObservation = state
        guard isAutomaticAvoidanceEnabled else { return }

        if state != .unknown {
            observeRightPanel(state)
            return
        }

        cancelUnknownFailOpen()
        latestRightPanelObservation = .unknown
        pendingAutomaticCollapse = false
        guard isCollapsed,
              interactionState.collapseOrigin == .automatic else { return }
        interactionState.releaseAutomaticCollapseForUncertainty()
        perform(.expand, automatic: true)
    }

    func observeRightPanel(_ state: CodexRightPanelState) {
        latestRightPanelObservation = state
        guard isAutomaticAvoidanceEnabled, let window else { return }
        if state == .unknown {
            let hasAutomaticOwnership =
                interactionState.collapseOrigin == .automatic
            pendingAutomaticCollapse = false
            if pendingTransitionAction?.automatic == true,
               pendingTransitionAction?.action == .collapse {
                pendingTransitionAction = nil
            }
            if hasAutomaticOwnership {
                scheduleUnknownFailOpenIfNeeded()
            }
        } else {
            cancelUnknownFailOpen()
        }
        let action = interactionState.observeRightPanel(
            state,
            isWindowVisible: window.isVisible,
            isCollapsed: effectiveIsCollapsed
        )
        if state == .closed {
            pendingAutomaticCollapse = false
        }
        if isTransitioning,
           action == .none,
           let transitionTargetIsCollapsed,
           pendingTransitionAction?.automatic == true,
           (state == .open && transitionTargetIsCollapsed
               || state == .closed && !transitionTargetIsCollapsed) {
            pendingTransitionAction = nil
        }
        perform(action, automatic: true)
    }

    func userDidShowWindow() {
        cancelUnknownFailOpen()
        pendingAutomaticCollapse = false
        let action = interactionState.recordManualShow(
            isCollapsed: effectiveIsCollapsed
        )
        perform(action, automatic: false)
    }

    func prepareForDefaultSizeRestore() {
        cancelUnknownFailOpen()
        pendingAutomaticCollapse = false
        pendingManualCollapse = false
        guard isCollapsed else { return }
        let action = interactionState.recordManualToggle(isCollapsed: true)
        if action == .expand {
            expand(
                animated: false,
                positioning: .followCompactBar
            )
        }
    }

    func presentPreservingTransientFrame(
        _ present: @MainActor (NSWindow) -> Void = { $0.orderFrontRegardless() }
    ) {
        guard let window else { return }
        let transientFrame = window.frame
        _ = window.setFrameAutosaveName("")
        present(window)
        window.setFrame(transientFrame, display: false)
        _ = window.setFrameAutosaveName("")
    }

    func toggleFromTitlebar() {
        cancelUnknownFailOpen()
        let action = interactionState.recordManualToggle(
            isCollapsed: effectiveIsCollapsed
        )
        pendingAutomaticCollapse = false
        perform(action, automatic: false)
    }

    private func perform(
        _ action: MainWindowCompactAction,
        automatic: Bool
    ) {
        guard action != .none else { return }
        if isTransitioning {
            pendingTransitionAction = (action, automatic)
            return
        }
        switch action {
        case .none:
            break
        case .collapse:
            requestCollapse(automatic: automatic)
        case .expand:
            pendingManualCollapse = false
            expand(
                animated: true,
                positioning: automatic
                    ? .restoreCachedFrameIfVisible
                    : .followCompactBar
            )
        }
    }

    private func requestCollapse(automatic: Bool) {
        guard let window, !isCollapsed else { return }

        if automatic,
           editorController?.blocksAutomaticWindowCollapse(in: window) == true {
            pendingAutomaticCollapse = true
            return
        }

        if !automatic,
           editorController?.hasActiveTextComposition == true {
            pendingManualCollapse = true
            schedulePendingCollapseRetry()
            return
        }

        pendingAutomaticCollapse = false
        pendingManualCollapse = false
        collapse(animated: true)
    }

    private func retryPendingCollapseIfPossible() {
        guard let window, !isCollapsed else {
            pendingAutomaticCollapse = false
            pendingManualCollapse = false
            return
        }

        if pendingAutomaticCollapse {
            guard isAutomaticAvoidanceEnabled,
                  interactionState.lastDefiniteRightPanelState == .open,
                  interactionState.collapseOrigin == .automatic else {
                pendingAutomaticCollapse = false
                return
            }
            guard editorController?.blocksAutomaticWindowCollapse(in: window)
                != true else { return }
            pendingAutomaticCollapse = false
            collapse(animated: true)
            return
        }

        if pendingManualCollapse {
            guard editorController?.hasActiveTextComposition != true else {
                schedulePendingCollapseRetry()
                return
            }
            pendingManualCollapse = false
            collapse(animated: true)
        }
    }

    private func schedulePendingCollapseRetry() {
        pendingRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingRetryWorkItem = nil
                self?.retryPendingCollapseIfPossible()
            }
        }
        pendingRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func scheduleUnknownFailOpenIfNeeded() {
        guard isAutomaticAvoidanceEnabled,
              unknownFailOpenWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.unknownFailOpenWorkItem = nil
                guard self.isAutomaticAvoidanceEnabled,
                      self.latestRightPanelObservation == .unknown,
                      self.interactionState.collapseOrigin == .automatic else {
                    return
                }

                self.pendingAutomaticCollapse = false
                if self.pendingTransitionAction?.automatic == true,
                   self.pendingTransitionAction?.action == .collapse {
                    self.pendingTransitionAction = nil
                }
                self.interactionState
                    .releaseAutomaticCollapseForUncertainty()
                self.perform(.expand, automatic: true)
            }
        }
        unknownFailOpenWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.unknownFailOpenDelay,
            execute: workItem
        )
    }

    private func cancelUnknownFailOpen() {
        unknownFailOpenWorkItem?.cancel()
        unknownFailOpenWorkItem = nil
    }

    private func collapse(animated: Bool) {
        guard let window, !isCollapsed else { return }

        let fullFrame = window.frame
        expandedFrame = fullFrame
        expandedWindowAlpha = window.alphaValue
        expandedTitlebarSeparatorStyle = window.titlebarSeparatorStyle
        MainWindowFramePersistence.persist(
            window: window,
            defaults: framePersistenceDefaults
        )
        let titlebarOnlyHeight = compactWindowHeight(
            for: window,
            expandedFrame: fullFrame
        )
        let targetFrame = MainWindowCompactGeometry.compactFrame(
            from: fullFrame,
            compactWidth: Self.compactWindowWidth,
            compactHeight: titlebarOnlyHeight
        )

        isCollapsed = true
        isCompactContentPresentationActive = false
        window.contentMinSize = NSSize(
            width: Self.compactWindowWidth,
            height: Self.compactContentHeight
        )
        applyStandardButtonVisibility(isCompact: true)
        accessoryController.update(isCollapsed: true, isEnabled: false)
        compactStateDidChange?(true)
        transition(
            to: targetFrame,
            targetIsCollapsed: true,
            animated: animated
        ) { [weak self, weak window] in
            guard let self else { return }
            // Changing the style mask also rebuilds native titlebar chrome. Do
            // it only after the resize animation so it cannot race the titlebar
            // layout and amplify the one-line intermediate frame.
            window?.styleMask.remove(.resizable)
            self.isCompactContentPresentationActive = true
        }
    }

    private func compactWindowHeight(
        for window: NSWindow,
        expandedFrame: NSRect
    ) -> CGFloat {
        // `contentLayoutRect` excludes the titlebar even when the content view
        // itself extends underneath it via `.fullSizeContentView`. Its height
        // difference from the expanded frame is therefore the native chrome
        // that must remain visible in compact mode.
        let titlebarHeight = max(
            0,
            expandedFrame.height - window.contentLayoutRect.height
        )
        return min(
            expandedFrame.height,
            ceil(
                max(
                    Self.compactContentHeight,
                    titlebarHeight + Self.compactContentHeight
                )
            )
        )
    }

    private func expand(
        animated: Bool,
        positioning: MainWindowExpandedFramePositioning
    ) {
        guard let window, isCollapsed else { return }

        let cachedFrame = expandedFrame ?? window.frame
        let targetFrame = targetExpandedFrame(
            for: window,
            cachedFrame: cachedFrame,
            positioning: positioning
        )
        isCompactContentPresentationActive = false
        window.styleMask.insert(.resizable)
        window.contentMinSize = Self.minimumExpandedContentSize
        transition(
            to: targetFrame,
            targetIsCollapsed: false,
            animated: animated
        ) { [weak self, weak window] in
            guard let self, let window else { return }
            self.isCollapsed = false
            self.applyStandardButtonVisibility(isCompact: false)
            self.expandedFrame = window.frame
            self.accessoryController.update(isCollapsed: false)
            self.compactStateDidChange?(false)
            if self.pendingTransitionAction?.action != .collapse {
                MainWindowFramePersistence.persist(
                    window: window,
                    defaults: self.framePersistenceDefaults
                )
            }
        }
    }

    private func transition(
        to frame: NSRect,
        targetIsCollapsed: Bool,
        animated: Bool,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        guard let window else { return }
        transitionID = UUID()
        let currentTransitionID = transitionID
        isTransitioning = true
        transitionTargetIsCollapsed = targetIsCollapsed
        accessoryController.update(
            isCollapsed: isCollapsed,
            isEnabled: false
        )
        applyAppearance()

        let finish = { [weak self] in
            guard let self, self.transitionID == currentTransitionID else {
                return
            }
            self.isTransitioning = false
            self.transitionTargetIsCollapsed = nil
            completion()
            self.accessoryController.update(
                isCollapsed: self.isCollapsed,
                isEnabled: true
            )
            self.applyAppearance()
            if let pendingAction = self.pendingTransitionAction {
                self.pendingTransitionAction = nil
                self.perform(
                    pendingAction.action,
                    automatic: pendingAction.automatic
                )
            }
        }

        if !animated || reduceMotion || !Self.animatesCompactFrameTransitions {
            setFrameImmediatelyCancellingAnimation(
                frame,
                on: window,
                display: window.isVisible
            )
            finish()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.transitionDuration
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated {
                finish()
            }
        }
    }

    /// A plain `setFrame` does not supersede an in-flight `window.animator()`
    /// resize: AppKit can finish the older animation later and put the window
    /// back at its stale target. A zero-duration animator transaction replaces
    /// that animation first; the direct write then makes the lifecycle operation
    /// synchronously observable to its caller.
    private func setFrameImmediatelyCancellingAnimation(
        _ frame: NSRect,
        on window: NSWindow,
        display: Bool
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            window.animator().setFrame(frame, display: display)
        }
        window.setFrame(frame, display: display)
    }

    private func targetExpandedFrame(
        for window: NSWindow,
        cachedFrame: NSRect,
        positioning: MainWindowExpandedFramePositioning
    ) -> NSRect {
        let compactFrame = window.frame
        var visibleFrames = NSScreen.screens.map(\.visibleFrame)
        for fallbackFrame in [
            window.screen?.visibleFrame,
            NSScreen.main?.visibleFrame,
        ].compactMap({ $0 }) where !visibleFrames.contains(fallbackFrame) {
            visibleFrames.append(fallbackFrame)
        }

        if positioning == .restoreCachedFrameIfVisible {
            let cachedFrameIsVisible = MainWindowInitialPlacementPolicy
                .visibleFrame(
                    containingMostOf: cachedFrame,
                    among: visibleFrames
                ) != nil
            if cachedFrameIsVisible || visibleFrames.isEmpty {
                return cachedFrame
            }
        }

        let visibleFrame = MainWindowInitialPlacementPolicy.visibleFrame(
            containingMostOf: compactFrame,
            among: visibleFrames
        ) ?? visibleFrames.first

        guard let visibleFrame else {
            return MainWindowCompactGeometry.expandedFrame(
                from: compactFrame,
                cachedExpandedFrame: cachedFrame
            )
        }
        return MainWindowCompactGeometry.expandedFrame(
            from: compactFrame,
            cachedExpandedFrame: cachedFrame,
            constrainedTo: visibleFrame
        )
    }

    private func installWindowObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyAppearance()
                    DispatchQueue.main.async { [weak self] in
                        self?.retryPendingCollapseIfPossible()
                    }
                }
            },
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.applyAppearance()
                }
            },
        ]
    }

    private func applyAppearance() {
        guard let window else { return }
        if usesCompactAppearance {
            let baselineAlpha = expandedWindowAlpha ?? 1
            let compactOpacity = Self.compactWindowOpacity(
                isActive: isPointerInside || window.isKeyWindow,
                reduceTransparency: reduceTransparency
            )
            // The retained 3pt content sliver exists only to keep the titlebar
            // accessory from clipping. It must not paint the note paper color.
            window.backgroundColor = .clear
            window.isOpaque = false
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.alphaValue = baselineAlpha * compactOpacity
        } else {
            window.alphaValue = expandedWindowAlpha ?? window.alphaValue
            window.isOpaque = true
            window.titlebarAppearsTransparent = false
            if let expandedTitlebarSeparatorStyle {
                window.titlebarSeparatorStyle = expandedTitlebarSeparatorStyle
            }
            window.backgroundColor = backgroundColor
        }
        window.invalidateShadow()
    }

    private func applyStandardButtonVisibility(isCompact: Bool) {
        guard let window else { return }
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.isHidden = isCompact
            closeButton.isEnabled = !isCompact
        }
        // These controls are hidden by MainWindowChromePolicy in the expanded
        // window and must never reappear inside the compact pill.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    static func compactWindowOpacity(
        isActive: Bool,
        reduceTransparency: Bool
    ) -> CGFloat {
        if reduceTransparency { return 1 }
        return isActive ? activeWindowOpacity : restingWindowOpacity
    }
}

@MainActor
private final class MainWindowCompactAccessoryController: NSObject {
    private weak var window: NSWindow?
    private let accessoryViewController = NSTitlebarAccessoryViewController()
    private let button = NSButton()
    private var action: (() -> Void)?

    override init() {
        super.init()
        let container = NSView()
        container.frame = NSRect(x: 0, y: 0, width: 36, height: 28)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = #selector(buttonPressed)
        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        accessoryViewController.layoutAttribute = .right
        accessoryViewController.view = container
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(to window: NSWindow, action: @escaping () -> Void) {
        if self.window !== window {
            detach()
            self.window = window
        }
        self.action = action
        ensureAttached(to: window)
    }

    func ensureAttached(to window: NSWindow) {
        guard !window.titlebarAccessoryViewControllers.contains(where: {
            $0 === accessoryViewController
        }) else { return }
        window.addTitlebarAccessoryViewController(accessoryViewController)
    }

    func update(isCollapsed: Bool, isEnabled: Bool = true) {
        let labelKey: L10n.Key = isCollapsed
            ? .mainWindowExpandAccessibilityLabel
            : .mainWindowCollapseAccessibilityLabel
        let helpKey: L10n.Key = isCollapsed
            ? .mainWindowExpandAccessibilityHelp
            : .mainWindowCollapseAccessibilityHelp
        let label = L10n.text(labelKey)
        button.image = NSImage(
            systemSymbolName: isCollapsed ? "chevron.down" : "chevron.up",
            accessibilityDescription: label
        )
        button.toolTip = label
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(L10n.text(helpKey))
    }

    func detach() {
        if let window,
           let index = window.titlebarAccessoryViewControllers.firstIndex(
               where: { $0 === accessoryViewController }
           ) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
        window = nil
        action = nil
    }

    @objc private func buttonPressed() {
        action?()
    }
}

@MainActor
private final class MainWindowCompactHoverController: NSResponder {
    private weak var window: NSWindow?
    private weak var frameView: NSView?
    private var trackingArea: NSTrackingArea?
    private var changeHandler: ((Bool) -> Void)?

    func attach(
        to window: NSWindow,
        changeHandler: @escaping (Bool) -> Void
    ) {
        guard let frameView = window.contentView?.superview else {
            detach()
            return
        }
        if self.window !== window || self.frameView !== frameView {
            detach()
            self.window = window
            self.frameView = frameView
        }
        self.changeHandler = changeHandler
        ensureAttached(to: window)
    }

    func ensureAttached(to window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        if let trackingArea, frameView.trackingAreas.contains(trackingArea) {
            return
        }
        if let trackingArea {
            self.frameView?.removeTrackingArea(trackingArea)
        }
        self.frameView = frameView
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        frameView.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    func detach() {
        if let frameView, let trackingArea {
            frameView.removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        frameView = nil
        window = nil
        changeHandler = nil
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea === trackingArea else { return }
        changeHandler?(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea === trackingArea else { return }
        changeHandler?(false)
    }
}
