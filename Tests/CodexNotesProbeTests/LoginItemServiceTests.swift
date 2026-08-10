import ServiceManagement
import ServiceManagement
import XCTest
@testable import CodexNotesProbe

@MainActor
final class LoginItemServiceTests: XCTestCase {
    func testPolicyCoversEveryStatusAndRequestedValue() {
        XCTAssertEqual(
            LoginItemPolicy.mutation(forRequestedEnabled: true, status: .enabled),
            .none
        )
        XCTAssertEqual(
            LoginItemPolicy.mutation(forRequestedEnabled: false, status: .enabled),
            .unregister
        )
        XCTAssertEqual(
            LoginItemPolicy.mutation(forRequestedEnabled: true, status: .notRegistered),
            .register
        )
        XCTAssertEqual(
            LoginItemPolicy.mutation(forRequestedEnabled: false, status: .notRegistered),
            .none
        )
        XCTAssertEqual(
            LoginItemPolicy.mutation(forRequestedEnabled: true, status: .requiresApproval),
            .requiresApproval
        )
        XCTAssertEqual(
            LoginItemPolicy.mutation(forRequestedEnabled: false, status: .requiresApproval),
            .unregister
        )
        XCTAssertEqual(
            LoginItemPolicy.mutation(forRequestedEnabled: true, status: .notFound),
            .register
        )
        XCTAssertEqual(
            LoginItemPolicy.mutation(forRequestedEnabled: false, status: .notFound),
            .none
        )
    }

    func testInitializationReadsStatusWithoutRegisteringByDefault() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)

        let service = LoginItemService(backend: backend)

        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertFalse(service.isEnabled)
        XCTAssertFalse(service.isRequestedEnabled)
        XCTAssertEqual(backend.registerCallCount, 0)
        XCTAssertEqual(backend.unregisterCallCount, 0)
    }

    func testRefreshAlwaysReadsTheBackendStatus() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        let service = LoginItemService(backend: backend)
        backend.status = .enabled

        service.refresh()

        XCTAssertEqual(service.status, .enabled)
        XCTAssertTrue(service.isEnabled)
    }

    func testEnableRegistersAndRefreshesTheEffectiveStatus() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        backend.statusAfterRegister = .enabled
        let service = LoginItemService(backend: backend)

        let result = service.setEnabled(true)

        XCTAssertEqual(result, .updated(.enabled))
        XCTAssertEqual(service.status, .enabled)
        XCTAssertTrue(service.isEnabled)
        XCTAssertTrue(service.isRequestedEnabled)
        XCTAssertEqual(backend.registerCallCount, 1)
        XCTAssertEqual(backend.unregisterCallCount, 0)
        XCTAssertNil(service.lastFailure)
    }

    func testSuccessfulRegistrationCanStillRequireApproval() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        backend.statusAfterRegister = .requiresApproval
        let service = LoginItemService(backend: backend)

        let result = service.setEnabled(true)

        XCTAssertEqual(result, .requiresApproval)
        XCTAssertEqual(service.status, .requiresApproval)
        XCTAssertTrue(service.requiresUserApproval)
        XCTAssertFalse(service.isEnabled)
        XCTAssertTrue(service.isRequestedEnabled)
    }

    func testEnableWhileApprovalIsRequiredDoesNotRegisterAgain() {
        let backend = StubLoginItemServiceBackend(status: .requiresApproval)
        let service = LoginItemService(backend: backend)

        let result = service.setEnabled(true)

        XCTAssertEqual(result, .requiresApproval)
        XCTAssertEqual(backend.registerCallCount, 0)
        XCTAssertEqual(backend.unregisterCallCount, 0)
    }

    func testDisableUnregistersAnEnabledService() {
        let backend = StubLoginItemServiceBackend(status: .enabled)
        backend.statusAfterUnregister = .notRegistered
        let service = LoginItemService(backend: backend)

        let result = service.setEnabled(false)

        XCTAssertEqual(result, .updated(.notRegistered))
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(backend.unregisterCallCount, 1)
    }

    func testDisableUnregistersAServiceAwaitingApproval() {
        let backend = StubLoginItemServiceBackend(status: .requiresApproval)
        backend.statusAfterUnregister = .notRegistered
        let service = LoginItemService(backend: backend)

        let result = service.setEnabled(false)

        XCTAssertEqual(result, .updated(.notRegistered))
        XCTAssertEqual(backend.unregisterCallCount, 1)
    }

    func testRedundantRequestsDoNotCallTheBackend() {
        let enabledBackend = StubLoginItemServiceBackend(status: .enabled)
        let enabledService = LoginItemService(backend: enabledBackend)
        let enabledResult = enabledService.setEnabled(true)

        let disabledBackend = StubLoginItemServiceBackend(status: .notRegistered)
        let disabledService = LoginItemService(backend: disabledBackend)
        let disabledResult = disabledService.setEnabled(false)

        XCTAssertEqual(enabledResult, .unchanged(.enabled))
        XCTAssertEqual(disabledResult, .unchanged(.notRegistered))
        XCTAssertEqual(enabledBackend.registerCallCount, 0)
        XCTAssertEqual(enabledBackend.unregisterCallCount, 0)
        XCTAssertEqual(disabledBackend.registerCallCount, 0)
        XCTAssertEqual(disabledBackend.unregisterCallCount, 0)
    }

    func testNotFoundAttemptsRegistrationWhenEnablingAndDoesNothingWhenDisabling() {
        let backend = StubLoginItemServiceBackend(status: .notFound)
        let service = LoginItemService(backend: backend)

        let enableResult = service.setEnabled(true)
        XCTAssertEqual(
            enableResult,
            .failed(LoginItemOperationFailure(
                operation: .register,
                message: "The system did not report the login item as enabled."
            ))
        )
        XCTAssertNotNil(service.lastFailure)

        let disableResult = service.setEnabled(false)

        XCTAssertEqual(disableResult, .unchanged(.notFound))
        XCTAssertEqual(backend.registerCallCount, 1)
        XCTAssertEqual(backend.unregisterCallCount, 0)
    }

    func testRegisterFailureIsPublishedAndStatusIsRefreshed() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        backend.registerError = StubError.register
        backend.statusAfterRegisterFailure = .requiresApproval
        let service = LoginItemService(backend: backend)

        let result = service.setEnabled(true)

        let expectedFailure = LoginItemOperationFailure(
            operation: .register,
            message: StubError.register.localizedDescription
        )
        XCTAssertEqual(result, .failed(expectedFailure))
        XCTAssertEqual(service.lastFailure, expectedFailure)
        XCTAssertEqual(service.status, .requiresApproval)
        XCTAssertFalse(service.isUpdating)
    }

    func testUnregisterFailureIsPublishedAndStatusIsRefreshed() {
        let backend = StubLoginItemServiceBackend(status: .enabled)
        backend.unregisterError = StubError.unregister
        backend.statusAfterUnregisterFailure = .notRegistered
        let service = LoginItemService(backend: backend)

        let result = service.setEnabled(false)

        let expectedFailure = LoginItemOperationFailure(
            operation: .unregister,
            message: StubError.unregister.localizedDescription
        )
        XCTAssertEqual(result, .failed(expectedFailure))
        XCTAssertEqual(service.lastFailure, expectedFailure)
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertFalse(service.isUpdating)
    }

    func testAlreadyRegisteredIsTreatedAsIdempotentSuccess() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        backend.registerError = serviceManagementError(kSMErrorAlreadyRegistered)
        backend.statusAfterRegisterFailure = .enabled
        let scheduler = TestScheduler()
        let service = LoginItemService(
            backend: backend,
            scheduler: scheduler.schedule
        )

        let result = service.setEnabled(true)

        XCTAssertEqual(result, .updated(.enabled))
        XCTAssertEqual(service.status, .enabled)
        XCTAssertNil(service.lastFailure)
        XCTAssertEqual(scheduler.pendingActionCount, 1)
    }

    func testLaunchDeniedIsMappedToApprovalWithoutPublishingFailure() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        backend.registerError = serviceManagementError(kSMErrorLaunchDeniedByUser)
        let scheduler = TestScheduler()
        let service = LoginItemService(
            backend: backend,
            scheduler: scheduler.schedule
        )

        let result = service.setEnabled(true)

        XCTAssertEqual(result, .requiresApproval)
        XCTAssertEqual(service.status, .requiresApproval)
        XCTAssertTrue(service.requiresUserApproval)
        XCTAssertTrue(service.isRequestedEnabled)
        XCTAssertNil(service.lastFailure)
        XCTAssertEqual(scheduler.pendingActionCount, 1)
    }

    func testJobNotFoundIsTreatedAsAlreadyUnregistered() {
        let backend = StubLoginItemServiceBackend(status: .enabled)
        backend.unregisterError = serviceManagementError(kSMErrorJobNotFound)
        let scheduler = TestScheduler()
        let service = LoginItemService(
            backend: backend,
            scheduler: scheduler.schedule
        )

        let result = service.setEnabled(false)

        XCTAssertEqual(result, .updated(.notRegistered))
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertNil(service.lastFailure)
        XCTAssertEqual(scheduler.pendingActionCount, 1)
    }

    func testMatchingErrorCodeFromAnotherDomainIsNotTreatedAsServiceManagement() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        backend.registerError = NSError(
            domain: "UnrelatedErrorDomain",
            code: Int(kSMErrorLaunchDeniedByUser),
            userInfo: [NSLocalizedDescriptionKey: "unrelated failure"]
        )
        let service = LoginItemService(backend: backend)

        let result = service.setEnabled(true)

        XCTAssertEqual(
            result,
            .failed(LoginItemOperationFailure(
                operation: .register,
                message: "unrelated failure"
            ))
        )
        XCTAssertEqual(service.status, .notRegistered)
        XCTAssertFalse(service.requiresUserApproval)
        XCTAssertNotNil(service.lastFailure)
    }

    func testDelayedRefreshClearsRegisterFailureAfterRequestedStateAppears() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        backend.registerError = StubError.register
        let scheduler = TestScheduler()
        let service = LoginItemService(
            backend: backend,
            scheduler: scheduler.schedule
        )
        _ = service.setEnabled(true)
        XCTAssertNotNil(service.lastFailure)

        backend.status = .enabled
        scheduler.advance(by: LoginItemService.delayedRefreshInterval)

        XCTAssertEqual(service.status, .enabled)
        XCTAssertNil(service.lastFailure)
    }

    func testDelayedRefreshClearsUnregisterFailureAfterOffStateAppears() {
        let backend = StubLoginItemServiceBackend(status: .enabled)
        backend.unregisterError = StubError.unregister
        let scheduler = TestScheduler()
        let service = LoginItemService(
            backend: backend,
            scheduler: scheduler.schedule
        )
        _ = service.setEnabled(false)
        XCTAssertNotNil(service.lastFailure)

        backend.status = .notFound
        scheduler.advance(by: LoginItemService.delayedRefreshInterval)

        XCTAssertEqual(service.status, .notFound)
        XCTAssertNil(service.lastFailure)
    }

    func testMutationSchedulesHalfSecondStatusRefresh() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        let scheduler = TestScheduler()
        let service = LoginItemService(
            backend: backend,
            scheduler: scheduler.schedule
        )

        _ = service.setEnabled(true)

        XCTAssertEqual(
            scheduler.scheduledDelays,
            [LoginItemService.delayedRefreshInterval]
        )
        XCTAssertEqual(scheduler.pendingActionCount, 1)

        backend.status = .enabled
        scheduler.advance(by: LoginItemService.delayedRefreshInterval)

        XCTAssertEqual(service.status, .enabled)
        XCTAssertEqual(scheduler.pendingActionCount, 0)
    }

    func testNewMutationCancelsThePreviousDelayedRefresh() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        backend.statusAfterRegister = .enabled
        backend.statusAfterUnregister = .notRegistered
        let scheduler = TestScheduler()
        let service = LoginItemService(
            backend: backend,
            scheduler: scheduler.schedule
        )

        _ = service.setEnabled(true)
        XCTAssertEqual(scheduler.pendingActionCount, 1)

        _ = service.setEnabled(false)

        XCTAssertEqual(scheduler.pendingActionCount, 1)
        XCTAssertEqual(scheduler.cancellationCount, 1)
    }

    func testExternalRefreshCancelsTheDelayedRefresh() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        let scheduler = TestScheduler()
        let service = LoginItemService(
            backend: backend,
            scheduler: scheduler.schedule
        )
        _ = service.setEnabled(true)
        XCTAssertEqual(scheduler.pendingActionCount, 1)

        service.refresh()

        XCTAssertEqual(scheduler.pendingActionCount, 0)
        XCTAssertEqual(scheduler.cancellationCount, 1)
    }

    func testExternalRefreshClearsAStaleFailure() {
        let backend = StubLoginItemServiceBackend(status: .notRegistered)
        backend.registerError = StubError.register
        let service = LoginItemService(backend: backend)
        _ = service.setEnabled(true)
        XCTAssertNotNil(service.lastFailure)

        backend.status = .enabled
        service.refresh()

        XCTAssertEqual(service.status, .enabled)
        XCTAssertNil(service.lastFailure)
    }

    func testOpeningLoginItemSettingsIsForwardedToTheBackend() {
        let backend = StubLoginItemServiceBackend(status: .requiresApproval)
        let service = LoginItemService(backend: backend)

        service.openSystemSettingsLoginItems()

        XCTAssertEqual(backend.openSettingsCallCount, 1)
    }

    private func serviceManagementError(_ code: Int) -> NSError {
        let domain: String
        if #available(macOS 15.0, *) {
            domain = SMAppServiceErrorDomain
        } else {
            domain = NSOSStatusErrorDomain
        }
        return NSError(
            domain: domain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "service management error"]
        )
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
        let action: LoginItemService.ScheduledAction
    }

    private var now: TimeInterval = 0
    private var entries: [Entry] = []
    private(set) var scheduledDelays: [TimeInterval] = []
    private(set) var cancellationCount = 0

    var pendingActionCount: Int {
        entries.filter { !$0.token.isCancelled }.count
    }

    func schedule(
        after delay: TimeInterval,
        action: @escaping LoginItemService.ScheduledAction
    ) -> LoginItemService.Cancellation {
        let token = Token()
        entries.append(
            Entry(deadline: now + delay, token: token, action: action)
        )
        scheduledDelays.append(delay)
        return { [weak self] in
            guard !token.isCancelled else { return }
            token.isCancelled = true
            self?.cancellationCount += 1
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

@MainActor
private final class StubLoginItemServiceBackend: LoginItemServiceBackend {
    var status: LoginItemRegistrationStatus
    var statusAfterRegister: LoginItemRegistrationStatus?
    var statusAfterRegisterFailure: LoginItemRegistrationStatus?
    var statusAfterUnregister: LoginItemRegistrationStatus?
    var statusAfterUnregisterFailure: LoginItemRegistrationStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(status: LoginItemRegistrationStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            if let statusAfterRegisterFailure {
                status = statusAfterRegisterFailure
            }
            throw registerError
        }
        if let statusAfterRegister {
            status = statusAfterRegister
        }
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            if let statusAfterUnregisterFailure {
                status = statusAfterUnregisterFailure
            }
            throw unregisterError
        }
        if let statusAfterUnregister {
            status = statusAfterUnregister
        }
    }

    func openSystemSettingsLoginItems() {
        openSettingsCallCount += 1
    }
}

private enum StubError: LocalizedError {
    case register
    case unregister

    var errorDescription: String? {
        switch self {
        case .register:
            return "register failed"
        case .unregister:
            return "unregister failed"
        }
    }
}
