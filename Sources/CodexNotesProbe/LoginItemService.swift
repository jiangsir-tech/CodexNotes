import Combine
import Foundation
import OSLog
import ServiceManagement

enum LoginItemRegistrationStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound

    var isEnabled: Bool {
        self == .enabled
    }

    var isRequestedEnabled: Bool {
        self == .enabled || self == .requiresApproval
    }

    var requiresUserApproval: Bool {
        self == .requiresApproval
    }
}

enum LoginItemOperation: Equatable, Sendable {
    case register
    case unregister
}

enum LoginItemMutation: Equatable, Sendable {
    case register
    case unregister
    case none
    case requiresApproval
}

enum LoginItemPolicy {
    static func mutation(
        forRequestedEnabled requestedEnabled: Bool,
        status: LoginItemRegistrationStatus
    ) -> LoginItemMutation {
        switch (requestedEnabled, status) {
        case (true, .enabled), (false, .notRegistered):
            return .none
        case (true, .notRegistered), (true, .notFound):
            return .register
        case (true, .requiresApproval):
            return .requiresApproval
        case (false, .enabled), (false, .requiresApproval):
            return .unregister
        case (false, .notFound):
            return .none
        }
    }
}

struct LoginItemOperationFailure: Equatable, Sendable {
    let operation: LoginItemOperation
    let message: String
}

enum LoginItemUpdateResult: Equatable, Sendable {
    case unchanged(LoginItemRegistrationStatus)
    case updated(LoginItemRegistrationStatus)
    case requiresApproval
    case failed(LoginItemOperationFailure)
}

@MainActor
protocol LoginItemServiceBackend: AnyObject {
    var status: LoginItemRegistrationStatus { get }

    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

@MainActor
final class SystemLoginItemServiceBackend: LoginItemServiceBackend {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LoginItemRegistrationStatus {
        switch service.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .notRegistered
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LoginItemService: ObservableObject {
    typealias ScheduledAction = @MainActor () -> Void
    typealias Cancellation = @MainActor () -> Void
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping ScheduledAction
    ) -> Cancellation

    static let delayedRefreshInterval: TimeInterval = 0.5
    private static let logger = Logger(
        subsystem: "tech.jiangsir.codex-task-notes",
        category: "LoginItem"
    )
    private static let appServiceErrorDomain = "SMAppServiceErrorDomain"

    @Published private(set) var status: LoginItemRegistrationStatus
    @Published private(set) var isUpdating = false
    @Published private(set) var lastFailure: LoginItemOperationFailure?

    private let backend: any LoginItemServiceBackend
    private let scheduler: Scheduler
    private var scheduledRefreshCancellation: Cancellation?

    convenience init() {
        self.init(
            backend: SystemLoginItemServiceBackend(),
            scheduler: Self.mainQueueScheduler
        )
    }

    convenience init(backend: any LoginItemServiceBackend) {
        self.init(backend: backend, scheduler: Self.mainQueueScheduler)
    }

    init(
        backend: any LoginItemServiceBackend,
        scheduler: @escaping Scheduler
    ) {
        self.backend = backend
        self.scheduler = scheduler
        status = backend.status
    }

    deinit {
        MainActor.assumeIsolated {
            scheduledRefreshCancellation?()
        }
    }

    var isEnabled: Bool {
        status.isEnabled
    }

    var isRequestedEnabled: Bool {
        status.isRequestedEnabled
    }

    var requiresUserApproval: Bool {
        status.requiresUserApproval
    }

    func refresh() {
        cancelScheduledRefresh()
        refreshFromBackend(clearFailure: true)
    }

    @discardableResult
    func setEnabled(_ requestedEnabled: Bool) -> LoginItemUpdateResult {
        guard !isUpdating else {
            return .unchanged(status)
        }

        cancelScheduledRefresh()
        refreshFromBackend(clearFailure: true)

        switch LoginItemPolicy.mutation(
            forRequestedEnabled: requestedEnabled,
            status: status
        ) {
        case .none:
            return .unchanged(status)
        case .requiresApproval:
            return .requiresApproval
        case .register:
            return perform(.register)
        case .unregister:
            return perform(.unregister)
        }
    }

    func openSystemSettingsLoginItems() {
        backend.openSystemSettingsLoginItems()
    }

    private func perform(_ operation: LoginItemOperation) -> LoginItemUpdateResult {
        isUpdating = true
        defer { isUpdating = false }

        do {
            switch operation {
            case .register:
                try backend.register()
            case .unregister:
                try backend.unregister()
            }

            refreshFromBackend(clearFailure: true)
            scheduleDelayedRefresh(after: operation)
            if status.requiresUserApproval {
                return .requiresApproval
            }
            guard hasReachedRequestedState(for: operation) else {
                let failure = LoginItemOperationFailure(
                    operation: operation,
                    message: Self.verificationFailureMessage(for: operation)
                )
                lastFailure = failure
                Self.logger.error(
                    "Login item \(String(describing: operation), privacy: .public) did not reach the requested state; observed=\(String(describing: self.status), privacy: .public)"
                )
                return .failed(failure)
            }
            return .updated(status)
        } catch {
            let nsError = error as NSError
            Self.logger.error(
                "Login item \(String(describing: operation), privacy: .public) returned domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .public)"
            )
            refreshFromBackend(clearFailure: true)

            if Self.isServiceManagementError(
                nsError,
                code: Int(kSMErrorAlreadyRegistered)
            ), operation == .register {
                scheduleDelayedRefresh(after: operation)
                if status.requiresUserApproval {
                    return .requiresApproval
                }
                return .updated(status)
            }

            if Self.isServiceManagementError(
                nsError,
                code: Int(kSMErrorLaunchDeniedByUser)
            ), operation == .register {
                status = .requiresApproval
                scheduleDelayedRefresh(after: operation)
                return .requiresApproval
            }

            if Self.isServiceManagementError(
                nsError,
                code: Int(kSMErrorJobNotFound)
            ), operation == .unregister {
                status = .notRegistered
                scheduleDelayedRefresh(after: operation)
                return .updated(status)
            }

            let failure = LoginItemOperationFailure(
                operation: operation,
                message: error.localizedDescription
            )
            lastFailure = failure
            scheduleDelayedRefresh(after: operation)
            return .failed(failure)
        }
    }

    private func refreshFromBackend(clearFailure: Bool) {
        status = backend.status
        if clearFailure {
            lastFailure = nil
        }
    }

    private func scheduleDelayedRefresh(after operation: LoginItemOperation) {
        cancelScheduledRefresh()
        scheduledRefreshCancellation = scheduler(Self.delayedRefreshInterval) { [weak self] in
            guard let self else { return }
            self.scheduledRefreshCancellation = nil
            self.refreshFromBackend(clearFailure: false)
            if self.hasReachedRequestedState(for: operation) {
                self.lastFailure = nil
            }
        }
    }

    private func hasReachedRequestedState(for operation: LoginItemOperation) -> Bool {
        switch (operation, status) {
        case (.register, .enabled), (.register, .requiresApproval):
            return true
        case (.unregister, .notRegistered), (.unregister, .notFound):
            return true
        default:
            return false
        }
    }

    private static func isServiceManagementError(
        _ error: NSError,
        code: Int
    ) -> Bool {
        guard error.code == code else { return false }
        return error.domain == NSOSStatusErrorDomain
            || error.domain == Self.appServiceErrorDomain
    }

    private static func verificationFailureMessage(
        for operation: LoginItemOperation
    ) -> String {
        switch operation {
        case .register:
            return "The system did not report the login item as enabled."
        case .unregister:
            return "The system still reported the login item as enabled."
        }
    }

    private func cancelScheduledRefresh() {
        scheduledRefreshCancellation?()
        scheduledRefreshCancellation = nil
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
