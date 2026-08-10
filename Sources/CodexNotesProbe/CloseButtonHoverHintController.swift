import AppKit
import CodexNotesCore

@MainActor
protocol CloseButtonHoverHintPresenting: AnyObject {
    @discardableResult
    func present(message: String, relativeTo button: NSButton) -> Bool

    func dismiss()
}

@MainActor
private final class CloseButtonHoverHintViewController: NSViewController {
    private let message: String

    init(message: String) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)

        let container = NSView()
        container.setAccessibilityElement(false)
        container.addSubview(label)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 126),
            container.heightAnchor.constraint(equalToConstant: 32),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        view = container
    }
}

@MainActor
private final class CloseButtonHoverPopoverPresenter: CloseButtonHoverHintPresenting {
    private var popover: NSPopover?

    @discardableResult
    func present(message: String, relativeTo button: NSButton) -> Bool {
        guard button.window?.isVisible == true else { return false }
        dismiss()

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(width: 126, height: 32)
        popover.contentViewController = CloseButtonHoverHintViewController(
            message: message
        )
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .maxY
        )
        guard popover.isShown else { return false }

        // The hint is purely explanatory. Its window must never intercept a
        // click intended for the close button or activate the application.
        popover.contentViewController?.view.window?.ignoresMouseEvents = true
        self.popover = popover
        return true
    }

    func dismiss() {
        if popover?.isShown == true {
            popover?.performClose(nil)
        }
        popover = nil
    }
}

/// Replaces AppKit's deliberately delayed native tooltip with a small,
/// non-activating hint that appears quickly over the main window close button.
@MainActor
final class CloseButtonHoverHintController: NSResponder {
    typealias ScheduledAction = @MainActor () -> Void
    typealias Cancellation = @MainActor () -> Void
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping ScheduledAction
    ) -> Cancellation

    static let displayDelay: TimeInterval = 0.30
    static var message: String { L10n.text(.windowCloseHoverHint) }

    private weak var closeButton: NSButton?
    private weak var window: NSWindow?
    private var trackingArea: NSTrackingArea?
    private var windowVisibilityObservation: NSKeyValueObservation?
    private var scheduledCancellation: Cancellation?
    private var isPointerInside = false
    private let scheduler: Scheduler
    private let presenter: any CloseButtonHoverHintPresenting

    override convenience init() {
        self.init(
            scheduler: Self.mainQueueScheduler,
            presenter: CloseButtonHoverPopoverPresenter()
        )
    }

    init(
        scheduler: @escaping Scheduler,
        presenter: any CloseButtonHoverHintPresenting
    ) {
        self.scheduler = scheduler
        self.presenter = presenter
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        scheduledCancellation?()
        windowVisibilityObservation?.invalidate()
        if let closeButton, let trackingArea {
            closeButton.removeTrackingArea(trackingArea)
        }
        presenter.dismiss()
    }

    /// Attaches to the current standard close button. Repeated calls for the
    /// same button and window leave exactly one tracking area installed.
    func attach(to button: NSButton, in window: NSWindow) {
        button.toolTip = nil

        if closeButton === button, self.window === window {
            ensureTrackingAreaIsInstalled(on: button)
            return
        }

        detach()
        closeButton = button
        self.window = window
        installTrackingArea(on: button)
        windowVisibilityObservation = window.observe(
            \.isVisible,
            options: [.new]
        ) { [weak self] _, change in
            guard change.newValue == false else { return }
            MainActor.assumeIsolated {
                self?.cancelAndDismiss()
            }
        }
    }

    /// Cancels a pending hint immediately and closes a visible hint.
    func cancelAndDismiss() {
        isPointerInside = false
        cancelScheduledPresentation()
        presenter.dismiss()
    }

    /// Removes all observation and tracking state from the current button.
    func detach() {
        cancelAndDismiss()
        windowVisibilityObservation?.invalidate()
        windowVisibilityObservation = nil
        if let closeButton, let trackingArea {
            closeButton.removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        closeButton = nil
        window = nil
    }

    override func mouseEntered(with event: NSEvent) {
        pointerEntered(from: event.trackingArea)
    }

    override func mouseExited(with event: NSEvent) {
        pointerExited(from: event.trackingArea)
    }

    // Semantic entry points keep timing behavior deterministic under a fake
    // clock without requiring synthetic AppKit mouse events in unit tests.
    func pointerEntered() {
        guard closeButton != nil else { return }
        isPointerInside = true
        cancelScheduledPresentation()
        scheduledCancellation = scheduler(Self.displayDelay) { [weak self] in
            self?.presentIfStillEligible()
        }
    }

    func pointerExited() {
        cancelAndDismiss()
    }

    func pointerEntered(from eventTrackingArea: NSTrackingArea?) {
        guard eventTrackingArea === trackingArea else { return }
        pointerEntered()
    }

    func pointerExited(from eventTrackingArea: NSTrackingArea?) {
        guard eventTrackingArea === trackingArea else { return }
        pointerExited()
    }

    private func presentIfStillEligible() {
        scheduledCancellation = nil
        guard isPointerInside,
              let closeButton,
              let window,
              closeButton.window === window,
              window.isVisible else {
            return
        }
        _ = presenter.present(message: Self.message, relativeTo: closeButton)
    }

    private func ensureTrackingAreaIsInstalled(on button: NSButton) {
        if let trackingArea, button.trackingAreas.contains(trackingArea) {
            return
        }
        installTrackingArea(on: button)
    }

    private func installTrackingArea(on button: NSButton) {
        if let trackingArea {
            closeButton?.removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeAlways,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )
        button.addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    private func cancelScheduledPresentation() {
        scheduledCancellation?()
        scheduledCancellation = nil
    }

    private static let mainQueueScheduler: Scheduler = { delay, action in
        let workItem = DispatchWorkItem {
            MainActor.assumeIsolated {
                action()
            }
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
        return {
            workItem.cancel()
        }
    }
}
