import AppKit
import Carbon.HIToolbox
import CodexNotesCore
import Combine
import Foundation

struct GlobalHotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32

    static let command = GlobalHotKeyModifiers(rawValue: 1 << 0)
    static let control = GlobalHotKeyModifiers(rawValue: 1 << 1)
    static let option = GlobalHotKeyModifiers(rawValue: 1 << 2)
    static let shift = GlobalHotKeyModifiers(rawValue: 1 << 3)

    static let supported: GlobalHotKeyModifiers = [
        .command,
        .control,
        .option,
        .shift,
    ]

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(nseventFlags: NSEvent.ModifierFlags) {
        var result: GlobalHotKeyModifiers = []
        if nseventFlags.contains(.command) { result.insert(.command) }
        if nseventFlags.contains(.control) { result.insert(.control) }
        if nseventFlags.contains(.option) { result.insert(.option) }
        if nseventFlags.contains(.shift) { result.insert(.shift) }
        self = result
    }

    var carbonFlags: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var displayName: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    var count: Int {
        rawValue.nonzeroBitCount
    }
}

enum GlobalHotKeyValidationIssue: Equatable, Sendable {
    case noModifier
    case shiftOnly
    case insufficientModifiers
    case unsupportedKey
}

struct GlobalHotKeyShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let modifiers: GlobalHotKeyModifiers

    static let defaultValue = GlobalHotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: [.control, .shift]
    )

    var validationIssue: GlobalHotKeyValidationIssue? {
        guard modifiers.subtracting(.supported).isEmpty else {
            return .unsupportedKey
        }
        guard Self.keyLabels[keyCode] != nil else { return .unsupportedKey }
        guard !modifiers.isEmpty else { return .noModifier }
        guard modifiers != [.shift] else { return .shiftOnly }
        if modifiers.count < 2 {
            return .insufficientModifiers
        }
        return nil
    }

    var displayName: String {
        modifiers.displayName + (Self.keyLabels[keyCode] ?? "?")
    }

    private static let keyLabels: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Equal): "=", UInt32(kVK_ANSI_Minus): "-",
        UInt32(kVK_ANSI_RightBracket): "]", UInt32(kVK_ANSI_LeftBracket): "[",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Period): ".",
        UInt32(kVK_ANSI_Grave): "`", UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
        UInt32(kVK_DownArrow): "↓", UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14",
        UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
    ]
}

enum GlobalHotKeyRegistrationActivity: Equatable, Sendable {
    case stopped
    case codexUnavailable
    case disabled
    case suspendedForRecording
    case registered
}

enum GlobalHotKeyRegistrationIssue: Equatable, Sendable {
    case invalidShortcut(GlobalHotKeyValidationIssue)
    case conflict(attempted: GlobalHotKeyShortcut)
    case registrationFailed(attempted: GlobalHotKeyShortcut, status: Int32)
    case backendFailed(status: Int32)
}

struct GlobalHotKeyRegistrationState: Equatable, Sendable {
    let activity: GlobalHotKeyRegistrationActivity
    let issue: GlobalHotKeyRegistrationIssue?
}

enum GlobalHotKeyUpdateResult: Equatable, Sendable {
    case updated
    case rejected(GlobalHotKeyValidationIssue)
    case conflict(GlobalHotKeyShortcut)
    case failed(shortcut: GlobalHotKeyShortcut, status: Int32)
}

enum GlobalHotKeySystemEvent: Equatable {
    case pressed
    case released
}

struct GlobalHotKeyUnregisterResult: Equatable {
    let activeRegistrationReleased: Bool
    let status: Int32
}

enum CarbonGlobalHotKeyRegistrationPolicy {
    static let options = OptionBits(0)
}

@MainActor
protocol GlobalHotKeyRegistering: AnyObject {
    var eventHandler: ((GlobalHotKeySystemEvent) -> Void)? { get set }
    func register(_ shortcut: GlobalHotKeyShortcut) -> Int32
    @discardableResult func unregister() -> GlobalHotKeyUnregisterResult
    func invalidate()
}

@MainActor
protocol CodexApplicationAvailabilityObserving: AnyObject {
    var isCodexAvailable: Bool { get }
    func start(onChange: @escaping (Bool) -> Void)
    func stop()
}

enum CodexApplicationAvailabilityPolicy {
    static func isAvailable(
        bundleIdentifier: String?,
        isTerminated: Bool,
        isHidden: Bool
    ) -> Bool {
        bundleIdentifier == CompanionVisibilityPolicy.codexBundleIdentifier
            && !isTerminated
            && !isHidden
    }

    static func shouldRefresh(for bundleIdentifier: String?) -> Bool {
        bundleIdentifier == CompanionVisibilityPolicy.codexBundleIdentifier
    }

}

@MainActor
final class CodexApplicationAvailabilityMonitor:
    CodexApplicationAvailabilityObserving
{
    private let workspace: NSWorkspace
    private var observerTokens: [NSObjectProtocol] = []
    private var onChange: ((Bool) -> Void)?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    var isCodexAvailable: Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: CompanionVisibilityPolicy.codexBundleIdentifier
        ).contains {
            CodexApplicationAvailabilityPolicy.isAvailable(
                bundleIdentifier: $0.bundleIdentifier,
                isTerminated: $0.isTerminated,
                isHidden: $0.isHidden
            )
        }
    }

    func start(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        guard observerTokens.isEmpty else { return }
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        observerTokens = names.map { name in
            workspace.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.handle(notification)
                }
            }
        }
    }

    func stop() {
        observerTokens.forEach(workspace.notificationCenter.removeObserver)
        observerTokens.removeAll()
        onChange = nil
    }

    private func handle(_ notification: Notification) {
        guard let application = notification.userInfo?[
            NSWorkspace.applicationUserInfoKey
        ] as? NSRunningApplication,
        CodexApplicationAvailabilityPolicy.shouldRefresh(
            for: application.bundleIdentifier
        ) else { return }
        onChange?(isCodexAvailable)
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }
}

@MainActor
final class CarbonGlobalHotKeyBackend: GlobalHotKeyRegistering {
    typealias CleanupScheduledAction = @MainActor () -> Void
    typealias CleanupCancellation = @MainActor () -> Void
    typealias CleanupScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping CleanupScheduledAction
    ) -> CleanupCancellation
    typealias RegistrationOperation = @MainActor (
        _ shortcut: GlobalHotKeyShortcut,
        _ identifier: EventHotKeyID
    ) -> (status: Int32, reference: EventHotKeyRef?)
    typealias UnregistrationOperation = @MainActor (
        _ reference: EventHotKeyRef
    ) -> Int32

    nonisolated static let defaultCleanupRetryDelays: [TimeInterval] = [1, 5, 30]

    var eventHandler: ((GlobalHotKeySystemEvent) -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeID: EventHotKeyID?
    private var pendingCleanupRefs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    private let cleanupRetryDelays: [TimeInterval]
    private let cleanupScheduler: CleanupScheduler
    private let registrationOperation: RegistrationOperation?
    private let unregistrationOperation: UnregistrationOperation
    private var cleanupRetryIndex = 0
    private var cleanupRetryCancellation: CleanupCancellation?
    private var cleanupRetryGeneration = 0
    private var isInvalidated = false

    init(
        cleanupRetryDelays: [TimeInterval] = CarbonGlobalHotKeyBackend
            .defaultCleanupRetryDelays,
        cleanupScheduler: CleanupScheduler? = nil,
        registrationOperation: RegistrationOperation? = nil,
        unregistrationOperation: @escaping UnregistrationOperation = {
            UnregisterEventHotKey($0)
        }
    ) {
        self.cleanupRetryDelays = cleanupRetryDelays.map { max(0, $0) }
        self.cleanupScheduler = cleanupScheduler
            ?? CarbonGlobalHotKeyBackend.mainQueueCleanupScheduler
        self.registrationOperation = registrationOperation
        self.unregistrationOperation = unregistrationOperation
    }

    func register(_ shortcut: GlobalHotKeyShortcut) -> Int32 {
        guard !isInvalidated else { return Int32(eventNotHandledErr) }
        let pendingCleanupStatus = cleanupPendingRefs()
        guard pendingCleanupStatus == noErr else {
            schedulePendingCleanupRetryIfNeeded()
            return pendingCleanupStatus
        }
        if registrationOperation == nil {
            let handlerStatus = installHandlerIfNeeded()
            guard handlerStatus == noErr else { return handlerStatus }
        }

        let newID = EventHotKeyID(signature: Self.signature, id: nextID)
        nextID &+= 1
        if nextID == 0 { nextID = 1 }
        let registration = performRegistration(
            shortcut: shortcut,
            identifier: newID
        )
        let status = registration.status
        let newRef = registration.reference
        guard status == noErr, let newRef else {
            return status == noErr ? Int32(paramErr) : status
        }

        if let oldRef = hotKeyRef {
            let cleanupStatus = unregistrationOperation(oldRef)
            guard cleanupStatus == noErr else {
                let rollbackStatus = unregistrationOperation(newRef)
                if rollbackStatus != noErr {
                    enqueuePendingCleanup(newRef)
                }
                return cleanupStatus
            }
        }
        hotKeyRef = newRef
        activeID = newID
        return noErr
    }

    @discardableResult
    func unregister() -> GlobalHotKeyUnregisterResult {
        var firstFailure = Int32(noErr)
        if let hotKeyRef {
            let status = unregistrationOperation(hotKeyRef)
            if status == noErr {
                self.hotKeyRef = nil
            } else {
                firstFailure = status
            }
        }
        let pendingCleanupStatus = cleanupPendingRefs()
        if firstFailure == noErr, pendingCleanupStatus != noErr {
            firstFailure = pendingCleanupStatus
        }
        if !pendingCleanupRefs.isEmpty {
            schedulePendingCleanupRetryIfNeeded()
        }
        if hotKeyRef == nil, pendingCleanupRefs.isEmpty {
            activeID = nil
        }
        return GlobalHotKeyUnregisterResult(
            activeRegistrationReleased: hotKeyRef == nil,
            status: firstFailure
        )
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        cancelPendingCleanupRetry(resetIndex: false)
        _ = unregister()
        cancelPendingCleanupRetry(resetIndex: false)
        if let handlerRef {
            _ = RemoveEventHandler(handlerRef)
        }
        handlerRef = nil
        eventHandler = nil
    }

    private func performRegistration(
        shortcut: GlobalHotKeyShortcut,
        identifier: EventHotKeyID
    ) -> (status: Int32, reference: EventHotKeyRef?) {
        if let registrationOperation {
            return registrationOperation(shortcut, identifier)
        }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers.carbonFlags,
            identifier,
            GetApplicationEventTarget(),
            CarbonGlobalHotKeyRegistrationPolicy.options,
            &reference
        )
        return (status, reference)
    }

    private func installHandlerIfNeeded() -> Int32 {
        guard handlerRef == nil else { return noErr }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        return eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                Self.carbonEventHandler,
                buffer.count,
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &handlerRef
            )
        }
    }

    private func cleanupPendingRefs() -> Int32 {
        guard !pendingCleanupRefs.isEmpty else { return noErr }
        var firstFailure = Int32(noErr)
        var remainingRefs: [EventHotKeyRef] = []
        for reference in pendingCleanupRefs {
            let status = unregistrationOperation(reference)
            if status != noErr {
                if firstFailure == noErr {
                    firstFailure = status
                }
                remainingRefs.append(reference)
            }
        }
        pendingCleanupRefs = remainingRefs
        if pendingCleanupRefs.isEmpty {
            cancelPendingCleanupRetry(resetIndex: true)
        }
        if hotKeyRef == nil, pendingCleanupRefs.isEmpty {
            activeID = nil
        }
        return firstFailure
    }

    private func enqueuePendingCleanup(_ reference: EventHotKeyRef) {
        guard !pendingCleanupRefs.contains(reference) else { return }
        pendingCleanupRefs.append(reference)
        cleanupRetryIndex = 0
        schedulePendingCleanupRetryIfNeeded()
    }

    private func schedulePendingCleanupRetryIfNeeded() {
        guard !isInvalidated,
              !pendingCleanupRefs.isEmpty,
              cleanupRetryCancellation == nil,
              cleanupRetryIndex < cleanupRetryDelays.count else { return }
        let delay = cleanupRetryDelays[cleanupRetryIndex]
        cleanupRetryIndex += 1
        cleanupRetryGeneration &+= 1
        let generation = cleanupRetryGeneration
        cleanupRetryCancellation = cleanupScheduler(delay) { [weak self] in
            guard let self,
                  !self.isInvalidated,
                  generation == self.cleanupRetryGeneration else { return }
            self.cleanupRetryCancellation = nil
            _ = self.cleanupPendingRefs()
            self.schedulePendingCleanupRetryIfNeeded()
        }
    }

    private func cancelPendingCleanupRetry(resetIndex: Bool) {
        cleanupRetryGeneration &+= 1
        cleanupRetryCancellation?()
        cleanupRetryCancellation = nil
        if resetIndex {
            cleanupRetryIndex = 0
        }
    }

    private static func mainQueueCleanupScheduler(
        delay: TimeInterval,
        action: @escaping CleanupScheduledAction
    ) -> CleanupCancellation {
        let workItem = DispatchWorkItem {
            MainActor.assumeIsolated {
                action()
            }
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, delay),
            execute: workItem
        )
        return {
            workItem.cancel()
        }
    }

    private func handle(_ event: EventRef?) -> OSStatus {
        guard let event, let activeID else { return OSStatus(eventNotHandledErr) }
        var receivedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedID
        )
        guard status == noErr,
              receivedID.signature == activeID.signature,
              receivedID.id == activeID.id else {
            return OSStatus(eventNotHandledErr)
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            eventHandler?(.pressed)
        case UInt32(kEventHotKeyReleased):
            eventHandler?(.released)
        default:
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }

    private static let signature: OSType = 0x434E484B // CNHK
    private static let carbonEventHandler: EventHandlerUPP = {
        _, event, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        return MainActor.assumeIsolated {
            let backend = Unmanaged<CarbonGlobalHotKeyBackend>
                .fromOpaque(userData)
                .takeUnretainedValue()
            return backend.handle(event)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            invalidate()
        }
    }
}

@MainActor
final class GlobalHotKeyController: ObservableObject {
    static let preferenceKey = "globalHotKeyPreference"

    @Published private(set) var currentShortcut: GlobalHotKeyShortcut?
    @Published private(set) var registrationState = GlobalHotKeyRegistrationState(
        activity: .stopped,
        issue: nil
    )
    @Published private(set) var isRecording = false

    var displayName: String {
        currentShortcut?.displayName ?? ""
    }

    var isDefault: Bool {
        currentShortcut == .defaultValue
    }

    private struct StoredPreference: Codable {
        let shortcut: GlobalHotKeyShortcut?
    }

    private let defaults: UserDefaults
    private let backend: GlobalHotKeyRegistering
    private let availabilityMonitor: CodexApplicationAvailabilityObserving
    private let toggleAction: () -> Void
    private let retryDelays: [TimeInterval]
    private var isStarted = false
    private var isCodexAvailable = false
    private var registeredShortcut: GlobalHotKeyShortcut?
    private var backendCleanupPending = false
    private var keyIsPressed = false
    private var reconciliationRetryWorkItem: DispatchWorkItem?
    private var reconciliationRetryIndex = 0
    private var reconciliationRetryGeneration: UInt = 0

    init(
        defaults: UserDefaults = .standard,
        backend: GlobalHotKeyRegistering? = nil,
        availabilityMonitor: CodexApplicationAvailabilityObserving? = nil,
        retryDelays: [TimeInterval] = [1, 5, 30],
        toggleAction: @escaping () -> Void = {
            NotificationCenter.default.post(
                name: MainWindowCommandNotification.toggle,
                object: nil
            )
        }
    ) {
        self.defaults = defaults
        self.backend = backend ?? CarbonGlobalHotKeyBackend()
        self.availabilityMonitor = availabilityMonitor
            ?? CodexApplicationAvailabilityMonitor()
        self.retryDelays = retryDelays.map { max(0, $0) }
        self.toggleAction = toggleAction
        currentShortcut = Self.loadPreference(from: defaults)
        self.backend.eventHandler = { [weak self] event in
            self?.handle(event)
        }
    }

    func start() {
        guard !isStarted else { return }
        cancelReconciliationRetry()
        isStarted = true
        availabilityMonitor.start { [weak self] isAvailable in
            self?.availabilityDidChange(isAvailable)
        }
        isCodexAvailable = availabilityMonitor.isCodexAvailable
        reconcileRegistration(clearingIssue: true)
    }

    func stop() {
        guard isStarted
                || registrationState.activity != .stopped
                || registeredShortcut != nil else { return }
        cancelReconciliationRetry()
        if isStarted {
            availabilityMonitor.stop()
        }
        isStarted = false
        isCodexAvailable = false
        isRecording = false
        let unregisterStatus = unregisterActiveShortcut()
        registrationState = GlobalHotKeyRegistrationState(
            activity: .stopped,
            issue: unregisterStatus == noErr
                ? nil
                : .backendFailed(status: unregisterStatus)
        )
    }

    func beginRecording() {
        guard !isRecording else { return }
        cancelReconciliationRetry()
        isRecording = true
        let unregisterStatus = unregisterActiveShortcut()
        registrationState = GlobalHotKeyRegistrationState(
            activity: .suspendedForRecording,
            issue: unregisterStatus == noErr
                ? nil
                : .backendFailed(status: unregisterStatus)
        )
    }

    func cancelRecording() {
        guard isRecording else { return }
        cancelReconciliationRetry()
        isRecording = false
        reconcileRegistration(clearingIssue: true)
    }

    @discardableResult
    func set(_ shortcut: GlobalHotKeyShortcut) -> GlobalHotKeyUpdateResult {
        if isRecording {
            return commitRecordedShortcut(shortcut)
        }
        cancelReconciliationRetry()
        return apply(shortcut, restorePreviousOnFailure: false)
    }

    @discardableResult
    func commitRecordedShortcut(
        _ shortcut: GlobalHotKeyShortcut
    ) -> GlobalHotKeyUpdateResult {
        cancelReconciliationRetry()
        guard let issue = shortcut.validationIssue else {
            let restorePreviousOnFailure = registeredShortcut == nil
            isRecording = false
            return apply(
                shortcut,
                restorePreviousOnFailure: restorePreviousOnFailure
            )
        }
        registrationState = GlobalHotKeyRegistrationState(
            activity: .suspendedForRecording,
            issue: .invalidShortcut(issue)
        )
        return .rejected(issue)
    }

    func clear() {
        cancelReconciliationRetry()
        isRecording = false
        let unregisterStatus = unregisterActiveShortcut()
        currentShortcut = nil
        persistCurrentPreference()
        registrationState = GlobalHotKeyRegistrationState(
            activity: .disabled,
            issue: unregisterStatus == noErr
                ? nil
                : .backendFailed(status: unregisterStatus)
        )
    }

    @discardableResult
    func restore() -> GlobalHotKeyUpdateResult {
        set(.defaultValue)
    }

    private func apply(
        _ shortcut: GlobalHotKeyShortcut,
        restorePreviousOnFailure: Bool
    ) -> GlobalHotKeyUpdateResult {
        if let issue = shortcut.validationIssue {
            registrationState = GlobalHotKeyRegistrationState(
                activity: activityForCurrentRegistration(),
                issue: .invalidShortcut(issue)
            )
            return .rejected(issue)
        }

        let oldShortcut = currentShortcut
        if oldShortcut == shortcut {
            reconcileRegistration(clearingIssue: true)
            return updateResultAfterReconcile(for: shortcut)
        }

        guard isStarted, isCodexAvailable else {
            currentShortcut = shortcut
            persistCurrentPreference()
            reconcileRegistration(clearingIssue: true)
            return .updated
        }

        let status = backend.register(shortcut)
        if status == noErr {
            backendCleanupPending = false
            registeredShortcut = shortcut
            keyIsPressed = false
            currentShortcut = shortcut
            persistCurrentPreference()
            registrationState = GlobalHotKeyRegistrationState(
                activity: .registered,
                issue: nil
            )
            return .updated
        }

        if restorePreviousOnFailure,
           registeredShortcut == nil,
           let oldShortcut {
            let restoreStatus = backend.register(oldShortcut)
            if restoreStatus == noErr {
                backendCleanupPending = false
                registeredShortcut = oldShortcut
            } else {
                registeredShortcut = nil
                registrationState = GlobalHotKeyRegistrationState(
                    activity: .disabled,
                    issue: .backendFailed(status: restoreStatus)
                )
                scheduleReconciliationRetryIfNeeded()
                return .failed(shortcut: oldShortcut, status: restoreStatus)
            }
        }

        let activity = activityForCurrentRegistration()
        if status == eventHotKeyExistsErr {
            registrationState = GlobalHotKeyRegistrationState(
                activity: activity,
                issue: .conflict(attempted: shortcut)
            )
            return .conflict(shortcut)
        }
        registrationState = GlobalHotKeyRegistrationState(
            activity: activity,
            issue: .registrationFailed(attempted: shortcut, status: status)
        )
        return .failed(shortcut: shortcut, status: status)
    }

    private func availabilityDidChange(_ isAvailable: Bool) {
        guard isStarted else { return }
        cancelReconciliationRetry()
        isCodexAvailable = isAvailable
        reconcileRegistration(clearingIssue: true)
    }

    private func reconcileRegistration(clearingIssue: Bool) {
        if !isStarted {
            let unregisterStatus = unregisterActiveShortcut()
            registrationState = GlobalHotKeyRegistrationState(
                activity: .stopped,
                issue: inactiveIssue(
                    unregisterStatus: unregisterStatus,
                    clearingIssue: clearingIssue
                )
            )
            return
        }
        if isRecording {
            let unregisterStatus = unregisterActiveShortcut()
            registrationState = GlobalHotKeyRegistrationState(
                activity: .suspendedForRecording,
                issue: inactiveIssue(
                    unregisterStatus: unregisterStatus,
                    clearingIssue: clearingIssue
                )
            )
            return
        }
        guard let currentShortcut else {
            let unregisterStatus = unregisterActiveShortcut()
            registrationState = GlobalHotKeyRegistrationState(
                activity: .disabled,
                issue: inactiveIssue(
                    unregisterStatus: unregisterStatus,
                    clearingIssue: clearingIssue
                )
            )
            return
        }
        guard isCodexAvailable else {
            let unregisterStatus = unregisterActiveShortcut()
            registrationState = GlobalHotKeyRegistrationState(
                activity: .codexUnavailable,
                issue: inactiveIssue(
                    unregisterStatus: unregisterStatus,
                    clearingIssue: clearingIssue
                )
            )
            return
        }
        if registeredShortcut == currentShortcut {
            cancelReconciliationRetry()
            registrationState = GlobalHotKeyRegistrationState(
                activity: .registered,
                issue: clearingIssue ? nil : registrationState.issue
            )
            return
        }

        let previouslyRegisteredShortcut = registeredShortcut
        let status = backend.register(currentShortcut)
        if status == noErr {
            cancelReconciliationRetry()
            backendCleanupPending = false
            registeredShortcut = currentShortcut
            keyIsPressed = false
            registrationState = GlobalHotKeyRegistrationState(
                activity: .registered,
                issue: nil
            )
        } else if status == eventHotKeyExistsErr {
            registeredShortcut = previouslyRegisteredShortcut
            registrationState = GlobalHotKeyRegistrationState(
                activity: activityForCurrentRegistration(),
                issue: .conflict(attempted: currentShortcut)
            )
            scheduleReconciliationRetryIfNeeded()
        } else {
            registeredShortcut = previouslyRegisteredShortcut
            registrationState = GlobalHotKeyRegistrationState(
                activity: activityForCurrentRegistration(),
                issue: .registrationFailed(
                    attempted: currentShortcut,
                    status: status
                )
            )
            scheduleReconciliationRetryIfNeeded()
        }
    }

    @discardableResult
    private func unregisterActiveShortcut() -> Int32 {
        keyIsPressed = false
        guard registeredShortcut != nil || backendCleanupPending else {
            cancelReconciliationRetry()
            return noErr
        }
        let result = backend.unregister()
        if result.activeRegistrationReleased {
            registeredShortcut = nil
        }
        backendCleanupPending = result.status != noErr
            && result.activeRegistrationReleased
        if result.status == noErr {
            backendCleanupPending = false
            cancelReconciliationRetry()
        } else {
            scheduleReconciliationRetryIfNeeded()
        }
        return result.status
    }

    private func inactiveIssue(
        unregisterStatus: Int32,
        clearingIssue: Bool
    ) -> GlobalHotKeyRegistrationIssue? {
        if unregisterStatus != noErr {
            return .backendFailed(status: unregisterStatus)
        }
        if case .backendFailed = registrationState.issue {
            return nil
        }
        return clearingIssue ? nil : registrationState.issue
    }

    private func updateResultAfterReconcile(
        for shortcut: GlobalHotKeyShortcut
    ) -> GlobalHotKeyUpdateResult {
        switch registrationState.issue {
        case nil:
            return .updated
        case let .invalidShortcut(issue):
            return .rejected(issue)
        case let .conflict(attempted):
            return .conflict(attempted)
        case let .registrationFailed(attempted, status):
            return .failed(shortcut: attempted, status: status)
        case let .backendFailed(status):
            return .failed(shortcut: shortcut, status: status)
        }
    }

    private func scheduleReconciliationRetryIfNeeded() {
        guard reconciliationRetryWorkItem == nil,
              reconciliationRetryIndex < retryDelays.count else { return }
        let delay = retryDelays[reconciliationRetryIndex]
        reconciliationRetryIndex += 1
        let generation = reconciliationRetryGeneration
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.reconciliationRetryGeneration == generation else {
                    return
                }
                self.reconciliationRetryWorkItem = nil
                self.reconcileRegistration(clearingIssue: false)
            }
        }
        reconciliationRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    private func cancelReconciliationRetry() {
        reconciliationRetryWorkItem?.cancel()
        reconciliationRetryWorkItem = nil
        reconciliationRetryIndex = 0
        reconciliationRetryGeneration &+= 1
    }

    private func activityForCurrentRegistration() -> GlobalHotKeyRegistrationActivity {
        registeredShortcut == nil ? .disabled : .registered
    }

    private func handle(_ event: GlobalHotKeySystemEvent) {
        guard isStarted,
              isCodexAvailable,
              !isRecording,
              registeredShortcut == currentShortcut else { return }
        switch event {
        case .pressed:
            guard !keyIsPressed else { return }
            keyIsPressed = true
            toggleAction()
        case .released:
            keyIsPressed = false
        }
    }

    private func persistCurrentPreference() {
        let preference = StoredPreference(shortcut: currentShortcut)
        guard let data = try? PropertyListEncoder().encode(preference) else {
            return
        }
        defaults.set(data, forKey: Self.preferenceKey)
    }

    private static func loadPreference(
        from defaults: UserDefaults
    ) -> GlobalHotKeyShortcut? {
        guard let data = defaults.data(forKey: preferenceKey) else {
            return .defaultValue
        }
        guard let stored = try? PropertyListDecoder().decode(
            StoredPreference.self,
            from: data
        ) else {
            return .defaultValue
        }
        guard let shortcut = stored.shortcut else { return nil }
        return shortcut.validationIssue == nil ? shortcut : .defaultValue
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
            backend.invalidate()
        }
    }
}
