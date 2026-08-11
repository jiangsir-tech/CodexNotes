import AppKit
import Carbon.HIToolbox
import XCTest
@testable import CodexNotesProbe

@MainActor
final class GlobalHotKeyControllerTests: XCTestCase {
    func testDefaultShortcutIsControlShiftSpace() {
        XCTAssertEqual(GlobalHotKeyShortcut.defaultValue.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(
            GlobalHotKeyShortcut.defaultValue.modifiers,
            [.control, .shift]
        )
        XCTAssertEqual(GlobalHotKeyShortcut.defaultValue.displayName, "⌃⇧Space")
        XCTAssertNil(GlobalHotKeyShortcut.defaultValue.validationIssue)
        XCTAssertEqual(
            CarbonGlobalHotKeyRegistrationPolicy.options,
            OptionBits(0)
        )
    }

    func testValidationRejectsUnsafeAndUnsupportedShortcuts() {
        XCTAssertEqual(
            shortcut(keyCode: kVK_ANSI_N, modifiers: []).validationIssue,
            .noModifier
        )
        XCTAssertEqual(
            shortcut(keyCode: kVK_ANSI_N, modifiers: [.shift]).validationIssue,
            .shiftOnly
        )
        XCTAssertEqual(
            shortcut(keyCode: kVK_ANSI_N, modifiers: [.command]).validationIssue,
            .insufficientModifiers
        )
        XCTAssertEqual(
            GlobalHotKeyShortcut(
                keyCode: 9_999,
                modifiers: [.control, .shift]
            ).validationIssue,
            .unsupportedKey
        )
        XCTAssertNil(
            shortcut(
                keyCode: kVK_ANSI_N,
                modifiers: [.control, .option]
            ).validationIssue
        )
        XCTAssertEqual(
            GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_Space),
                modifiers: GlobalHotKeyModifiers(rawValue: 0x30)
            ).validationIssue,
            .unsupportedKey
        )
    }

    func testCarbonBackendRetriesOnlyTheRolledBackNewReference() {
        let scheduler = TestCarbonCleanupScheduler()
        let oldReference = OpaquePointer(bitPattern: 0x101)!
        let newReference = OpaquePointer(bitPattern: 0x202)!
        var registrationReferences = [oldReference, newReference]
        var unregistrationCalls: [EventHotKeyRef] = []
        var oldReferenceAttempts = 0
        var newReferenceAttempts = 0
        let backend = CarbonGlobalHotKeyBackend(
            cleanupRetryDelays: [1, 5, 30],
            cleanupScheduler: scheduler.schedule,
            registrationOperation: { _, _ in
                (Int32(noErr), registrationReferences.removeFirst())
            },
            unregistrationOperation: { reference in
                unregistrationCalls.append(reference)
                if reference == oldReference {
                    oldReferenceAttempts += 1
                    return oldReferenceAttempts == 1 ? -71 : Int32(noErr)
                }
                XCTAssertEqual(reference, newReference)
                newReferenceAttempts += 1
                return newReferenceAttempts == 1 ? -72 : Int32(noErr)
            }
        )
        defer { backend.invalidate() }

        XCTAssertEqual(backend.register(.defaultValue), noErr)
        let replacement = shortcut(
            keyCode: kVK_ANSI_N,
            modifiers: [.control, .option]
        )

        XCTAssertEqual(backend.register(replacement), -71)
        XCTAssertEqual(unregistrationCalls, [oldReference, newReference])
        XCTAssertEqual(scheduler.scheduledDelays, [1])

        scheduler.runNext()

        XCTAssertEqual(
            unregistrationCalls,
            [oldReference, newReference, newReference]
        )
        XCTAssertEqual(scheduler.activeCount, 0)

        let releaseResult = backend.unregister()
        XCTAssertEqual(
            unregistrationCalls,
            [oldReference, newReference, newReference, oldReference]
        )
        XCTAssertTrue(releaseResult.activeRegistrationReleased)
        XCTAssertEqual(releaseResult.status, noErr)
    }

    func testCarbonBackendPendingCleanupRetriesAreBounded() {
        XCTAssertEqual(
            CarbonGlobalHotKeyBackend.defaultCleanupRetryDelays,
            [1, 5, 30]
        )
        let scheduler = TestCarbonCleanupScheduler()
        let oldReference = OpaquePointer(bitPattern: 0x303)!
        let newReference = OpaquePointer(bitPattern: 0x404)!
        var registrationReferences = [oldReference, newReference]
        var unregistrationCalls: [EventHotKeyRef] = []
        let backend = CarbonGlobalHotKeyBackend(
            cleanupScheduler: scheduler.schedule,
            registrationOperation: { _, _ in
                (Int32(noErr), registrationReferences.removeFirst())
            },
            unregistrationOperation: { reference in
                unregistrationCalls.append(reference)
                return reference == oldReference ? -81 : -82
            }
        )

        XCTAssertEqual(backend.register(.defaultValue), noErr)
        XCTAssertEqual(
            backend.register(
                shortcut(
                    keyCode: kVK_ANSI_N,
                    modifiers: [.control, .option]
                )
            ),
            -81
        )

        scheduler.runNext()
        scheduler.runNext()
        scheduler.runNext()

        XCTAssertEqual(scheduler.scheduledDelays, [1, 5, 30])
        XCTAssertEqual(scheduler.activeCount, 0)
        XCTAssertEqual(
            unregistrationCalls.filter { $0 == oldReference }.count,
            1
        )
        XCTAssertEqual(
            unregistrationCalls.filter { $0 == newReference }.count,
            4
        )

        backend.invalidate()
    }

    func testCarbonBackendInvalidateCancelsPendingCleanupRetry() {
        let scheduler = TestCarbonCleanupScheduler()
        let oldReference = OpaquePointer(bitPattern: 0x505)!
        let newReference = OpaquePointer(bitPattern: 0x606)!
        var registrationReferences = [oldReference, newReference]
        var unregistrationCalls: [EventHotKeyRef] = []
        var initialRollbackIsFailing = true
        let backend = CarbonGlobalHotKeyBackend(
            cleanupRetryDelays: [1, 5, 30],
            cleanupScheduler: scheduler.schedule,
            registrationOperation: { _, _ in
                (Int32(noErr), registrationReferences.removeFirst())
            },
            unregistrationOperation: { reference in
                unregistrationCalls.append(reference)
                if initialRollbackIsFailing {
                    return reference == oldReference ? -91 : -92
                }
                return noErr
            }
        )

        XCTAssertEqual(backend.register(.defaultValue), noErr)
        XCTAssertEqual(
            backend.register(
                shortcut(
                    keyCode: kVK_ANSI_N,
                    modifiers: [.control, .option]
                )
            ),
            -91
        )
        XCTAssertEqual(scheduler.scheduledDelays, [1])
        XCTAssertEqual(scheduler.activeCount, 1)

        initialRollbackIsFailing = false
        backend.invalidate()

        XCTAssertEqual(scheduler.activeCount, 0)
        XCTAssertEqual(
            unregistrationCalls,
            [oldReference, newReference, oldReference, newReference]
        )
        let callCountAfterInvalidation = unregistrationCalls.count
        scheduler.runNext(ignoringCancellation: true)
        backend.invalidate()
        XCTAssertEqual(unregistrationCalls.count, callCountAfterInvalidation)
    }

    func testCarbonBackendCancelledRetryCannotCleanANewerBatch() {
        let scheduler = TestCarbonCleanupScheduler()
        let oldReference = OpaquePointer(bitPattern: 0x701)!
        let firstRollbackReference = OpaquePointer(bitPattern: 0x702)!
        let newerOldReference = OpaquePointer(bitPattern: 0x703)!
        let secondRollbackReference = OpaquePointer(bitPattern: 0x704)!
        var registrationReferences = [
            oldReference,
            firstRollbackReference,
            newerOldReference,
            secondRollbackReference,
        ]
        var attemptCounts: [EventHotKeyRef: Int] = [:]
        var unregistrationCalls: [EventHotKeyRef] = []
        let backend = CarbonGlobalHotKeyBackend(
            cleanupRetryDelays: [1, 5, 30],
            cleanupScheduler: scheduler.schedule,
            registrationOperation: { _, _ in
                (Int32(noErr), registrationReferences.removeFirst())
            },
            unregistrationOperation: { reference in
                unregistrationCalls.append(reference)
                attemptCounts[reference, default: 0] += 1
                return attemptCounts[reference] == 1 ? -101 : Int32(noErr)
            }
        )
        defer { backend.invalidate() }

        XCTAssertEqual(backend.register(.defaultValue), noErr)
        XCTAssertEqual(
            backend.register(
                shortcut(
                    keyCode: kVK_ANSI_N,
                    modifiers: [.control, .option]
                )
            ),
            -101
        )
        XCTAssertEqual(scheduler.scheduledDelays, [1])

        XCTAssertEqual(backend.unregister().status, noErr)
        XCTAssertEqual(scheduler.activeCount, 0)

        XCTAssertEqual(backend.register(.defaultValue), noErr)
        XCTAssertEqual(
            backend.register(
                shortcut(
                    keyCode: kVK_ANSI_M,
                    modifiers: [.control, .option]
                )
            ),
            -101
        )
        XCTAssertEqual(scheduler.scheduledDelays, [1, 1])
        let callCountBeforeStaleAction = unregistrationCalls.count

        scheduler.runNext(ignoringCancellation: true)

        XCTAssertEqual(unregistrationCalls.count, callCountBeforeStaleAction)
        XCTAssertEqual(attemptCounts[secondRollbackReference], 1)

        scheduler.runNext()

        XCTAssertEqual(attemptCounts[secondRollbackReference], 2)
        XCTAssertEqual(attemptCounts[newerOldReference], 1)
        XCTAssertEqual(scheduler.activeCount, 0)
    }

    func testStartWhileCodexHiddenDoesNotRegister() {
        let fixture = makeFixture(isCodexAvailable: false)

        fixture.controller.start()

        XCTAssertTrue(fixture.backend.registeredShortcuts.isEmpty)
        XCTAssertEqual(fixture.controller.registrationState.activity, .codexUnavailable)
        XCTAssertNil(fixture.controller.registrationState.issue)
    }

    func testCodexAvailabilityRequiresTheRightVisibleRunningApplication() {
        let codexBundleID = "com.openai.codex"

        XCTAssertTrue(
            CodexApplicationAvailabilityPolicy.isAvailable(
                bundleIdentifier: codexBundleID,
                isTerminated: false,
                isHidden: false
            )
        )
        XCTAssertFalse(
            CodexApplicationAvailabilityPolicy.isAvailable(
                bundleIdentifier: codexBundleID,
                isTerminated: false,
                isHidden: true
            )
        )
        XCTAssertFalse(
            CodexApplicationAvailabilityPolicy.isAvailable(
                bundleIdentifier: codexBundleID,
                isTerminated: true,
                isHidden: false
            )
        )
        XCTAssertFalse(
            CodexApplicationAvailabilityPolicy.isAvailable(
                bundleIdentifier: "com.example.other",
                isTerminated: false,
                isHidden: false
            )
        )
        XCTAssertTrue(
            CodexApplicationAvailabilityPolicy.shouldRefresh(
                for: codexBundleID
            )
        )
        XCTAssertFalse(
            CodexApplicationAvailabilityPolicy.shouldRefresh(
                for: "com.example.other"
            )
        )
    }

    func testStartWhileCodexVisibleRegistersDefault() {
        let fixture = makeFixture(isCodexAvailable: true)

        fixture.controller.start()

        XCTAssertEqual(
            fixture.backend.registeredShortcuts,
            [.defaultValue]
        )
        XCTAssertEqual(fixture.controller.registrationState.activity, .registered)
    }

    func testCodexHideReleasesShortcutAndUnhideRestoresIt() {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()

        fixture.availability.update(false)

        XCTAssertEqual(fixture.backend.unregisterCount, 1)
        XCTAssertEqual(fixture.controller.registrationState.activity, .codexUnavailable)

        fixture.availability.update(true)

        XCTAssertEqual(fixture.backend.registeredShortcuts.count, 2)
        XCTAssertEqual(fixture.backend.registeredShortcuts.last, .defaultValue)
        XCTAssertEqual(fixture.controller.registrationState.activity, .registered)
    }

    func testRepeatedPressedEventTogglesOnlyAfterRelease() {
        var toggleCount = 0
        let fixture = makeFixture(
            isCodexAvailable: true,
            toggleAction: { toggleCount += 1 }
        )
        fixture.controller.start()

        fixture.backend.send(.pressed)
        fixture.backend.send(.pressed)
        XCTAssertEqual(toggleCount, 1)

        fixture.backend.send(.released)
        fixture.backend.send(.pressed)
        XCTAssertEqual(toggleCount, 2)
    }

    func testRecordingSuspendsShortcutAndCancelRestoresIt() {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()

        fixture.controller.beginRecording()

        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(fixture.backend.unregisterCount, 1)
        XCTAssertEqual(
            fixture.controller.registrationState.activity,
            .suspendedForRecording
        )

        fixture.controller.cancelRecording()

        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.backend.registeredShortcuts.count, 2)
        XCTAssertEqual(fixture.controller.registrationState.activity, .registered)
    }

    func testCodexBecomingVisibleDuringRecordingDoesNotRegister() {
        let fixture = makeFixture(isCodexAvailable: false)
        fixture.controller.start()
        fixture.controller.beginRecording()

        fixture.availability.update(true)

        XCTAssertTrue(fixture.backend.registeredShortcuts.isEmpty)
        XCTAssertEqual(
            fixture.controller.registrationState.activity,
            .suspendedForRecording
        )

        fixture.controller.cancelRecording()
        XCTAssertEqual(fixture.backend.registeredShortcuts, [.defaultValue])
    }

    func testChangingShortcutWhileCodexHiddenPersistsWithoutRegistering() {
        let fixture = makeFixture(isCodexAvailable: false)
        fixture.controller.start()
        let custom = shortcut(
            keyCode: kVK_ANSI_N,
            modifiers: [.control, .option]
        )

        XCTAssertEqual(fixture.controller.set(custom), .updated)
        XCTAssertEqual(fixture.controller.currentShortcut, custom)
        XCTAssertTrue(fixture.backend.registeredShortcuts.isEmpty)

        fixture.availability.update(true)
        XCTAssertEqual(fixture.backend.registeredShortcuts, [custom])
    }

    func testConflictKeepsOldShortcutRegisteredAndReportsAttempt() {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()
        let custom = shortcut(
            keyCode: kVK_ANSI_N,
            modifiers: [.control, .option]
        )
        fixture.backend.nextStatuses = [Int32(eventHotKeyExistsErr)]

        XCTAssertEqual(fixture.controller.set(custom), .conflict(custom))
        XCTAssertEqual(fixture.controller.currentShortcut, .defaultValue)
        XCTAssertEqual(fixture.controller.registrationState.activity, .registered)
        XCTAssertEqual(
            fixture.controller.registrationState.issue,
            .conflict(attempted: custom)
        )
        XCTAssertEqual(fixture.backend.unregisterCount, 0)
    }

    func testRecordingConflictRestoresOldShortcut() {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()
        let custom = shortcut(
            keyCode: kVK_ANSI_N,
            modifiers: [.control, .option]
        )
        fixture.controller.beginRecording()
        fixture.backend.nextStatuses = [
            Int32(eventHotKeyExistsErr),
            Int32(noErr),
        ]

        XCTAssertEqual(
            fixture.controller.commitRecordedShortcut(custom),
            .conflict(custom)
        )
        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.currentShortcut, .defaultValue)
        XCTAssertEqual(fixture.backend.registeredShortcuts.last, .defaultValue)
        XCTAssertEqual(fixture.controller.registrationState.activity, .registered)
    }

    func testRecordingTheSameShortcutReportsReregistrationConflict() {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()
        fixture.controller.beginRecording()
        fixture.backend.nextStatuses = [Int32(eventHotKeyExistsErr)]

        XCTAssertEqual(
            fixture.controller.commitRecordedShortcut(.defaultValue),
            .conflict(.defaultValue)
        )
        XCTAssertFalse(fixture.controller.isRecording)
        XCTAssertEqual(fixture.controller.registrationState.activity, .disabled)
        XCTAssertEqual(
            fixture.controller.registrationState.issue,
            .conflict(attempted: .defaultValue)
        )
    }

    func testFailedOldShortcutRestoreRetriesAutomatically() async {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()
        fixture.controller.beginRecording()
        let custom = shortcut(
            keyCode: kVK_ANSI_N,
            modifiers: [.control, .option]
        )
        fixture.backend.nextStatuses = [
            Int32(eventHotKeyExistsErr),
            -9,
            Int32(noErr),
        ]

        XCTAssertEqual(
            fixture.controller.commitRecordedShortcut(custom),
            .failed(shortcut: .defaultValue, status: -9)
        )
        XCTAssertEqual(
            fixture.controller.registrationState.issue,
            .backendFailed(status: -9)
        )

        await drainMainQueue(times: 3)

        XCTAssertEqual(fixture.controller.registrationState.activity, .registered)
        XCTAssertNil(fixture.controller.registrationState.issue)
        XCTAssertEqual(fixture.backend.registeredShortcuts.last, .defaultValue)
    }

    func testConflictRetriesAutomaticallyAfterTheBlockerReleases() async {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.backend.nextStatuses = [
            Int32(eventHotKeyExistsErr),
            Int32(noErr),
        ]

        fixture.controller.start()

        XCTAssertEqual(fixture.controller.registrationState.activity, .disabled)
        XCTAssertEqual(
            fixture.controller.registrationState.issue,
            .conflict(attempted: .defaultValue)
        )

        await drainMainQueue(times: 3)

        XCTAssertEqual(fixture.controller.registrationState.activity, .registered)
        XCTAssertNil(fixture.controller.registrationState.issue)
        XCTAssertEqual(fixture.backend.registeredShortcuts.last, .defaultValue)
    }

    func testFailedUnregisterIsReportedAndRetriedWithoutToggling() async {
        var toggleCount = 0
        let fixture = makeFixture(
            isCodexAvailable: true,
            toggleAction: { toggleCount += 1 }
        )
        fixture.controller.start()
        fixture.backend.nextUnregisterStatuses = [-7, Int32(noErr)]

        fixture.availability.update(false)

        XCTAssertEqual(fixture.controller.registrationState.activity, .codexUnavailable)
        XCTAssertEqual(
            fixture.controller.registrationState.issue,
            .backendFailed(status: -7)
        )
        fixture.backend.send(.pressed)
        XCTAssertEqual(toggleCount, 0)

        await drainMainQueue(times: 3)

        XCTAssertEqual(fixture.backend.unregisterCount, 2)
        XCTAssertEqual(fixture.controller.registrationState.activity, .codexUnavailable)
        XCTAssertNil(fixture.controller.registrationState.issue)
    }

    func testUnregisterRetriesAreBounded() async {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()
        fixture.backend.nextUnregisterStatuses = [-1, -2, -3, -4, -5]

        fixture.availability.update(false)
        await drainMainQueue(times: 7)

        XCTAssertEqual(fixture.backend.unregisterCount, 4)
        XCTAssertEqual(
            fixture.controller.registrationState.issue,
            .backendFailed(status: -4)
        )
    }

    func testPendingBackendCleanupDoesNotPretendTheShortcutIsRegistered() async {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()
        fixture.backend.nextUnregisterResults = [
            GlobalHotKeyUnregisterResult(
                activeRegistrationReleased: true,
                status: -8
            ),
            GlobalHotKeyUnregisterResult(
                activeRegistrationReleased: true,
                status: Int32(noErr)
            ),
        ]

        fixture.availability.update(false)

        XCTAssertEqual(fixture.controller.registrationState.activity, .codexUnavailable)
        XCTAssertEqual(
            fixture.controller.registrationState.issue,
            .backendFailed(status: -8)
        )

        await drainMainQueue(times: 3)

        XCTAssertEqual(fixture.backend.unregisterCount, 2)
        XCTAssertEqual(fixture.controller.registrationState.activity, .codexUnavailable)
        XCTAssertNil(fixture.controller.registrationState.issue)
    }

    func testInvalidRecordedShortcutKeepsRecorderActive() {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()
        fixture.controller.beginRecording()
        let unsafe = shortcut(
            keyCode: kVK_ANSI_C,
            modifiers: [.command]
        )

        XCTAssertEqual(
            fixture.controller.commitRecordedShortcut(unsafe),
            .rejected(.insufficientModifiers)
        )
        XCTAssertTrue(fixture.controller.isRecording)
        XCTAssertEqual(
            fixture.controller.registrationState.issue,
            .invalidShortcut(.insufficientModifiers)
        )
    }

    func testClearPersistsDisabledAndRestoreReenablesDefault() {
        let suiteName = "GlobalHotKeyControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let backend = FakeGlobalHotKeyBackend()
        let availability = FakeCodexAvailability(isAvailable: true)
        let controller = GlobalHotKeyController(
            defaults: defaults,
            backend: backend,
            availabilityMonitor: availability,
            toggleAction: {}
        )
        controller.start()

        controller.clear()

        XCTAssertNil(controller.currentShortcut)
        XCTAssertEqual(controller.registrationState.activity, .disabled)

        let restoredFromDefaults = GlobalHotKeyController(
            defaults: defaults,
            backend: FakeGlobalHotKeyBackend(),
            availabilityMonitor: FakeCodexAvailability(isAvailable: false),
            toggleAction: {}
        )
        XCTAssertNil(restoredFromDefaults.currentShortcut)

        XCTAssertEqual(controller.restore(), .updated)
        XCTAssertEqual(controller.currentShortcut, .defaultValue)
        XCTAssertTrue(controller.isDefault)
    }

    func testStopRemovesObserverAndRegistrationIdempotently() {
        let fixture = makeFixture(isCodexAvailable: true)
        fixture.controller.start()
        fixture.controller.start()

        fixture.controller.stop()
        fixture.controller.stop()

        XCTAssertEqual(fixture.availability.startCount, 1)
        XCTAssertEqual(fixture.availability.stopCount, 1)
        XCTAssertEqual(fixture.backend.unregisterCount, 1)
        XCTAssertEqual(fixture.controller.registrationState.activity, .stopped)
    }

    private func shortcut(
        keyCode: Int,
        modifiers: GlobalHotKeyModifiers
    ) -> GlobalHotKeyShortcut {
        GlobalHotKeyShortcut(
            keyCode: UInt32(keyCode),
            modifiers: modifiers
        )
    }

    private func makeFixture(
        isCodexAvailable: Bool,
        toggleAction: @escaping () -> Void = {}
    ) -> Fixture {
        let suiteName = "GlobalHotKeyControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let backend = FakeGlobalHotKeyBackend()
        let availability = FakeCodexAvailability(
            isAvailable: isCodexAvailable
        )
        let controller = GlobalHotKeyController(
            defaults: defaults,
            backend: backend,
            availabilityMonitor: availability,
            retryDelays: [0, 0, 0],
            toggleAction: toggleAction
        )
        addTeardownBlock {
            await MainActor.run {
                controller.stop()
            }
            UserDefaults(suiteName: suiteName)?
                .removePersistentDomain(forName: suiteName)
        }
        return Fixture(
            controller: controller,
            backend: backend,
            availability: availability
        )
    }

    private func drainMainQueue(times: Int) async {
        for _ in 0..<times {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }
}

@MainActor
private struct Fixture {
    let controller: GlobalHotKeyController
    let backend: FakeGlobalHotKeyBackend
    let availability: FakeCodexAvailability
}

@MainActor
private final class FakeGlobalHotKeyBackend: GlobalHotKeyRegistering {
    var eventHandler: ((GlobalHotKeySystemEvent) -> Void)?
    var nextStatuses: [Int32] = []
    var nextUnregisterStatuses: [Int32] = []
    var nextUnregisterResults: [GlobalHotKeyUnregisterResult] = []
    private(set) var registeredShortcuts: [GlobalHotKeyShortcut] = []
    private(set) var unregisterCount = 0
    private(set) var invalidateCount = 0

    func register(_ shortcut: GlobalHotKeyShortcut) -> Int32 {
        let status = nextStatuses.isEmpty ? Int32(noErr) : nextStatuses.removeFirst()
        if status == noErr {
            registeredShortcuts.append(shortcut)
        }
        return status
    }

    func unregister() -> GlobalHotKeyUnregisterResult {
        unregisterCount += 1
        if !nextUnregisterResults.isEmpty {
            return nextUnregisterResults.removeFirst()
        }
        let status = nextUnregisterStatuses.isEmpty
            ? Int32(noErr)
            : nextUnregisterStatuses.removeFirst()
        return GlobalHotKeyUnregisterResult(
            activeRegistrationReleased: status == noErr,
            status: status
        )
    }

    func invalidate() {
        invalidateCount += 1
    }

    func send(_ event: GlobalHotKeySystemEvent) {
        eventHandler?(event)
    }
}

@MainActor
private final class FakeCodexAvailability:
    CodexApplicationAvailabilityObserving
{
    var isCodexAvailable: Bool
    private var onChange: ((Bool) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(isAvailable: Bool) {
        isCodexAvailable = isAvailable
    }

    func start(onChange: @escaping (Bool) -> Void) {
        startCount += 1
        self.onChange = onChange
    }

    func stop() {
        stopCount += 1
        onChange = nil
    }

    func update(_ isAvailable: Bool) {
        isCodexAvailable = isAvailable
        onChange?(isAvailable)
    }
}

@MainActor
private final class TestCarbonCleanupScheduler {
    private final class Item {
        let delay: TimeInterval
        let action: CarbonGlobalHotKeyBackend.CleanupScheduledAction
        var isCancelled = false

        init(
            delay: TimeInterval,
            action: @escaping CarbonGlobalHotKeyBackend.CleanupScheduledAction
        ) {
            self.delay = delay
            self.action = action
        }
    }

    private var items: [Item] = []
    private(set) var scheduledDelays: [TimeInterval] = []

    var activeCount: Int {
        items.filter { !$0.isCancelled }.count
    }

    func schedule(
        delay: TimeInterval,
        action: @escaping CarbonGlobalHotKeyBackend.CleanupScheduledAction
    ) -> CarbonGlobalHotKeyBackend.CleanupCancellation {
        let item = Item(delay: delay, action: action)
        items.append(item)
        scheduledDelays.append(delay)
        return {
            item.isCancelled = true
        }
    }

    func runNext(ignoringCancellation: Bool = false) {
        guard !items.isEmpty else { return }
        let item = items.removeFirst()
        guard ignoringCancellation || !item.isCancelled else { return }
        item.action()
    }
}
