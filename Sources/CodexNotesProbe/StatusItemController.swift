import AppKit
import CodexNotesCore

enum CodexNotesApplicationPresentation {
    static let activationPolicy: NSApplication.ActivationPolicy = .accessory

    static func isSatisfied(
        by actualPolicy: NSApplication.ActivationPolicy
    ) -> Bool {
        actualPolicy == activationPolicy
    }
}

enum MainWindowToggleAction: Equatable {
    case show
    case hide
}

enum MainWindowTogglePolicy {
    static func action(
        isApplicationHidden: Bool,
        isWindowVisible: Bool,
        isWindowMiniaturized: Bool
    ) -> MainWindowToggleAction {
        if isApplicationHidden || !isWindowVisible || isWindowMiniaturized {
            return .show
        }
        return .hide
    }
}

enum MainWindowVisibilityPreference: Equatable {
    case automatic
    case hidden
}

struct MainWindowVisibilityState {
    private(set) var preference: MainWindowVisibilityPreference = .automatic
    private(set) var codexActivationRequestID: UUID?

    var isAwaitingCodexActivation: Bool {
        codexActivationRequestID != nil
    }

    mutating func recordManualHide() {
        preference = .hidden
        codexActivationRequestID = nil
    }

    mutating func recordManualShow() {
        preference = .automatic
        codexActivationRequestID = nil
    }

    @discardableResult
    mutating func beginCodexActivation(
        requestID: UUID = UUID()
    ) -> UUID {
        preference = .automatic
        codexActivationRequestID = requestID
        return requestID
    }

    func isCurrentCodexActivationRequest(_ requestID: UUID) -> Bool {
        codexActivationRequestID == requestID
    }

    @discardableResult
    mutating func completeCodexActivation(
        requestID: UUID? = nil
    ) -> Bool {
        guard let currentRequestID = codexActivationRequestID else {
            return false
        }
        if let requestID, requestID != currentRequestID {
            return false
        }
        codexActivationRequestID = nil
        return true
    }

    func shouldShow(
        automaticVisibilityAllowed: Bool,
        isSettingsVisible: Bool
    ) -> Bool {
        guard !isSettingsVisible, !isAwaitingCodexActivation else {
            return false
        }
        switch preference {
        case .automatic:
            return automaticVisibilityAllowed
        case .hidden:
            return false
        }
    }
}

enum StatusItemInteraction: Equatable {
    case toggleWindow
    case showQuitMenu
}

enum StatusItemInteractionPolicy {
    static func interaction(
        for eventType: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> StatusItemInteraction {
        if eventType == .rightMouseUp
            || (eventType == .leftMouseUp && modifierFlags.contains(.control)) {
            return .showQuitMenu
        }
        return .toggleWindow
    }
}

enum MainWindowCommandNotification {
    static let toggle = Notification.Name("CodexNotesToggleMainWindow")
    static let show = Notification.Name("CodexNotesShowMainWindow")
    static let hiddenUsingCloseButton = Notification.Name(
        "CodexNotesMainWindowHiddenUsingCloseButton"
    )
}

enum StatusItemCloseEducationPreference {
    static let key = "statusItemCloseEducationShown"

    static func shouldPresent(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        !defaults.bool(forKey: key)
    }

    static func markPresented(
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(true, forKey: key)
    }
}

enum CodexNotesWindowIdentifier {
    static let main = NSUserInterfaceItemIdentifier(
        "tech.jiangsir.codex-task-notes.main-window"
    )
    static let settings = NSUserInterfaceItemIdentifier(
        "tech.jiangsir.codex-task-notes.settings-window"
    )
}

@MainActor
private final class StatusItemCloseEducationViewController: NSViewController {
    private let localization: AppLocalization

    init(localization: AppLocalization) {
        self.localization = localization
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let titleLabel = NSTextField(
            labelWithString: localization.text(.statusItemEducationTitle)
        )
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let detailLabel = NSTextField(
            wrappingLabelWithString: localization.text(.statusItemEducationMessage)
        )
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleLabel, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 250),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])
        view = container
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let quitMenu = NSMenu()
    private let defaults: UserDefaults
    private let iconProvider: (StatusBarIconID) -> NSImage?
    private let closeEducationPresenter: ((NSStatusBarButton) -> Bool)?
    private var preferenceObserver: NSObjectProtocol?
    private var closeEducationObserver: NSObjectProtocol?
    private var closeEducationPopover: NSPopover?
    private var closeEducationDismissWorkItem: DispatchWorkItem?
    private var closeEducationPresentationPending = false
    private var appliedLanguageRevision = ""
    private(set) var currentIconID: StatusBarIconID?

    var currentToolTip: String? {
        statusItem.button?.toolTip
    }

    var currentAccessibilityHelp: String? {
        statusItem.button?.accessibilityHelp()
    }

    var currentQuitMenuTitle: String? {
        quitMenu.items.first?.title
    }

    var quitMenuItemCount: Int {
        quitMenu.items.count
    }

    override convenience init() {
        self.init(
            defaults: .standard,
            iconProvider: { StatusBarIconArtwork.image(for: $0) },
            closeEducationPresenter: nil
        )
    }

    init(
        defaults: UserDefaults,
        iconProvider: @escaping (StatusBarIconID) -> NSImage?,
        closeEducationPresenter: ((NSStatusBarButton) -> Bool)? = nil
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.defaults = defaults
        self.iconProvider = iconProvider
        self.closeEducationPresenter = closeEducationPresenter
        super.init()
        configureStatusItem()
        configureQuitMenu()
        observeIconPreference()
        observeCloseEducationCommand()
    }

    isolated deinit {
        closeEducationDismissWorkItem?.cancel()
        if closeEducationPopover?.isShown == true {
            closeEducationPopover?.performClose(nil)
        }
        closeEducationPopover = nil
        if let preferenceObserver {
            NotificationCenter.default.removeObserver(preferenceObserver)
        }
        if let closeEducationObserver {
            NotificationCenter.default.removeObserver(closeEducationObserver)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        applyStatusBarIcon()
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("CodexNotes")
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshLocalizedContent(using: currentLocalization())
    }

    private func observeIconPreference() {
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.preferencesDidChange()
            }
        }
    }

    private func observeCloseEducationCommand() {
        closeEducationObserver = NotificationCenter.default.addObserver(
            forName: MainWindowCommandNotification.hiddenUsingCloseButton,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.presentCloseEducationIfNeeded()
            }
        }
    }

    private func applyStatusBarIcon(force: Bool = false) {
        let iconID = StatusBarIconPreference.load(from: defaults)
        guard force || currentIconID != iconID || statusItem.button?.image == nil else {
            return
        }

        let image = iconProvider(iconID) ?? StatusBarIconArtwork.fallbackImage()
        image?.isTemplate = true
        image?.size = StatusBarIconArtwork.pointSize
        statusItem.button?.image = image
        currentIconID = iconID
    }

    private func configureQuitMenu() {
        quitMenu.autoenablesItems = false
        let quitItem = NSMenuItem(
            title: currentLocalization().text(.statusItemQuit),
            action: #selector(quitApplication(_:)),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitMenu.addItem(quitItem)
    }

    private func preferencesDidChange() {
        let localization = currentLocalization()
        let revision = Self.languageRevision(for: localization)
        guard revision != appliedLanguageRevision else {
            applyStatusBarIcon()
            return
        }

        appliedLanguageRevision = revision
        refreshLocalizedContent(using: localization)
        applyStatusBarIcon(force: true)
        dismissCloseEducationPopover()
    }

    private func refreshLocalizedContent(using localization: AppLocalization) {
        statusItem.button?.toolTip = localization.text(.statusItemTooltip)
        statusItem.button?.setAccessibilityHelp(
            localization.text(.statusItemAccessibilityHelp)
        )
        quitMenu.items.first?.title = localization.text(.statusItemQuit)
        appliedLanguageRevision = Self.languageRevision(for: localization)
    }

    private func currentLocalization() -> AppLocalization {
        AppLocalization(
            preference: AppLanguagePreference.load(from: defaults)
        )
    }

    private static func languageRevision(
        for localization: AppLocalization
    ) -> String {
        "\(localization.preference.rawValue):\(localization.resolvedLanguage.rawValue)"
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            dismissCloseEducationPopover()
            postToggleCommand()
            return
        }

        let interaction = StatusItemInteractionPolicy.interaction(
            for: event.type,
            modifierFlags: event.modifierFlags
        )
        dismissCloseEducationPopover()
        switch interaction {
        case .toggleWindow:
            postToggleCommand()
        case .showQuitMenu:
            _ = quitMenu.popUp(
                positioning: nil,
                at: NSPoint(x: sender.bounds.midX, y: sender.bounds.minY),
                in: sender
            )
        }
    }

    private func postToggleCommand() {
        NotificationCenter.default.post(name: MainWindowCommandNotification.toggle, object: nil)
    }

    private func presentCloseEducationIfNeeded() {
        guard !closeEducationPresentationPending,
              StatusItemCloseEducationPreference.shouldPresent(in: defaults) else {
            return
        }
        closeEducationPresentationPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.closeEducationPresentationPending = false }
            guard StatusItemCloseEducationPreference.shouldPresent(
                in: self.defaults
            ), let button = self.statusItem.button,
               button.window != nil else {
                return
            }
            let didPresent: Bool
            if let closeEducationPresenter = self.closeEducationPresenter {
                didPresent = closeEducationPresenter(button)
            } else {
                didPresent = self.presentCloseEducationPopover(
                    anchoredTo: button
                )
            }
            if didPresent {
                StatusItemCloseEducationPreference.markPresented(
                    in: self.defaults
                )
            }
        }
    }

    @discardableResult
    private func presentCloseEducationPopover(
        anchoredTo button: NSStatusBarButton
    ) -> Bool {
        guard button.window != nil else { return false }
        dismissCloseEducationPopover()
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = StatusItemCloseEducationViewController(
            localization: currentLocalization()
        )
        popover.contentSize = NSSize(width: 250, height: 64)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        guard popover.isShown else { return false }
        closeEducationPopover = popover

        let dismissWorkItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.dismissCloseEducationPopover()
            }
        }
        closeEducationDismissWorkItem = dismissWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 6,
            execute: dismissWorkItem
        )
        return true
    }

    private func dismissCloseEducationPopover() {
        closeEducationDismissWorkItem?.cancel()
        closeEducationDismissWorkItem = nil
        if closeEducationPopover?.isShown == true {
            closeEducationPopover?.performClose(nil)
        }
        closeEducationPopover = nil
    }

    @objc
    private func quitApplication(_ sender: Any?) {
        NSApp.terminate(sender)
    }
}
