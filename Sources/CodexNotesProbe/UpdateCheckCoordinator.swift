import AppKit
import Combine
import Foundation

enum UpdateCheckPreferenceKey {
    static let automaticChecksEnabled = "updateCheck.automaticChecksEnabled"
    static let nextEligibleAt = "updateCheck.nextEligibleAt"
    static let lastAttemptAt = "updateCheck.lastAttemptAt"
    static let lastSuccessAt = "updateCheck.lastSuccessAt"
    static let consecutiveFailureCount = "updateCheck.consecutiveFailureCount"
    static let availableVersion = "updateCheck.availableVersion"
    static let availableReleaseURL = "updateCheck.availableReleaseURL"
    static let dismissedBannerVersion = "updateCheck.dismissedBannerVersion"
}

@MainActor
final class UpdateCheckCoordinator: ObservableObject {
    typealias ScheduledAction = @MainActor () -> Void
    typealias Cancellation = @MainActor () -> Void
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping ScheduledAction
    ) -> Cancellation
    typealias Clock = @MainActor () -> Date
    typealias MonotonicClock = @MainActor () -> TimeInterval
    typealias ResultDeliveryBarrier = @MainActor (
        _ initiatedRequest: Bool
    ) async -> Void

    static let successfulCheckInterval: TimeInterval = 24 * 60 * 60
    static let launchDelay: TimeInterval = 10
    static let failureRetryIntervals: [TimeInterval] = [
        60 * 60,
        3 * 60 * 60,
        6 * 60 * 60,
        24 * 60 * 60
    ]

    @Published private(set) var state: AppUpdateState
    @Published private(set) var isAutomaticCheckEnabled: Bool
    @Published private(set) var availableUpdate: AvailableAppUpdate?
    @Published private(set) var bannerUpdate: AvailableAppUpdate?

    private enum CheckSource: Equatable {
        case automatic
        case manual
    }

    private struct ActiveCheck {
        let generation: Int
        let source: CheckSource
        let task: Task<AppUpdateState?, Never>
        var hasManualWaiter: Bool
    }

    private struct SharedCheckResult {
        let state: AppUpdateState?
        let initiatedRequest: Bool
    }

    private let defaults: UserDefaults
    private let checker: AppUpdateChecker
    private let installedVersion: String
    private let clock: Clock
    private let monotonicClock: MonotonicClock
    private let scheduler: Scheduler
    private let applicationNotificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let resultDeliveryBarrier: ResultDeliveryBarrier

    private var isStarted = false
    private var scheduledCheckCancellation: Cancellation?
    private var applicationActivationObserver: NSObjectProtocol?
    private var workspaceWakeObserver: NSObjectProtocol?
    private var automaticStartupGraceDeadline: TimeInterval?
    private var activeCheck: ActiveCheck?
    private var checkGeneration = 0

    convenience init() {
        self.init(
            defaults: .standard,
            checker: AppUpdateChecker(),
            installedVersion: AppBundleVersion.current.version,
            clock: Date.init,
            monotonicClock: { ProcessInfo.processInfo.systemUptime },
            scheduler: Self.mainQueueScheduler,
            applicationNotificationCenter: .default,
            workspaceNotificationCenter: NSWorkspace.shared.notificationCenter,
            resultDeliveryBarrier: { _ in }
        )
    }

    init(
        defaults: UserDefaults,
        checker: AppUpdateChecker,
        installedVersion: String,
        clock: @escaping Clock,
        monotonicClock: @escaping MonotonicClock = {
            ProcessInfo.processInfo.systemUptime
        },
        scheduler: @escaping Scheduler,
        applicationNotificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        resultDeliveryBarrier: @escaping ResultDeliveryBarrier = { _ in }
    ) {
        self.defaults = defaults
        self.checker = checker
        self.installedVersion = installedVersion
        self.clock = clock
        self.monotonicClock = monotonicClock
        self.scheduler = scheduler
        self.applicationNotificationCenter = applicationNotificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.resultDeliveryBarrier = resultDeliveryBarrier

        isAutomaticCheckEnabled = defaults.bool(
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )

        let restoredUpdate = Self.restoreAvailableUpdate(
            from: defaults,
            installedVersion: installedVersion
        )
        availableUpdate = restoredUpdate
        if let restoredUpdate {
            state = .updateAvailable(
                version: restoredUpdate.version,
                url: restoredUpdate.url
            )
            let dismissedVersion = defaults.string(
                forKey: UpdateCheckPreferenceKey.dismissedBannerVersion
            )
            bannerUpdate = dismissedVersion == restoredUpdate.version
                ? nil
                : restoredUpdate
        } else {
            state = .idle
            bannerUpdate = nil
        }
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        applicationActivationObserver = applicationNotificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.automaticCheckOpportunity()
            }
        }
        workspaceWakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.automaticCheckOpportunity()
            }
        }

        if isAutomaticCheckEnabled {
            automaticStartupGraceDeadline = monotonicClock() + Self.launchDelay
            scheduleNextAutomaticCheck(minimumDelay: 0)
        }
    }

    func setAutomaticChecksEnabled(_ isEnabled: Bool) {
        guard isAutomaticCheckEnabled != isEnabled else {
            return
        }

        isAutomaticCheckEnabled = isEnabled
        defaults.set(
            isEnabled,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )

        if isEnabled {
            automaticStartupGraceDeadline = nil
            if isStarted {
                scheduleNextAutomaticCheck(minimumDelay: 0)
            }
            return
        }

        automaticStartupGraceDeadline = nil
        cancelScheduledCheck()
        if let activeCheck,
           activeCheck.source == .automatic,
           !activeCheck.hasManualWaiter {
            cancelActiveCheck()
        }
    }

    func manualCheck() async {
        let previousState = state
        state = .checking

        let result = await performSharedCheck(source: .manual)
        guard let resultState = result.state else {
            if state == .checking {
                state = previousState
            }
            return
        }

        if result.initiatedRequest {
            applyCompletedCheck(resultState, source: .manual)
        } else {
            publishManualResult(resultState)
        }
    }

    func checkIfDue() async {
        guard isStarted, isAutomaticCheckEnabled else {
            return
        }

        let currentMonotonicTime = monotonicClock()
        if let graceDeadline = automaticStartupGraceDeadline,
           currentMonotonicTime < graceDeadline {
            scheduleNextAutomaticCheck(minimumDelay: 0)
            return
        }
        automaticStartupGraceDeadline = nil
        let currentDate = clock()
        guard isDue(at: currentDate) else {
            if isStarted {
                scheduleNextAutomaticCheck(minimumDelay: 0)
            }
            return
        }

        let result = await performSharedCheck(source: .automatic)
        guard result.initiatedRequest, let resultState = result.state else {
            return
        }
        applyCompletedCheck(resultState, source: .automatic)
    }

    func dismissBanner() {
        guard let update = bannerUpdate ?? availableUpdate else {
            return
        }

        defaults.set(
            update.version,
            forKey: UpdateCheckPreferenceKey.dismissedBannerVersion
        )
        bannerUpdate = nil
    }

    func stop() {
        isStarted = false
        automaticStartupGraceDeadline = nil
        cancelScheduledCheck()
        cancelActiveCheck()

        if let applicationActivationObserver {
            applicationNotificationCenter.removeObserver(applicationActivationObserver)
            self.applicationActivationObserver = nil
        }
        if let workspaceWakeObserver {
            workspaceNotificationCenter.removeObserver(workspaceWakeObserver)
            self.workspaceWakeObserver = nil
        }
    }

    private func automaticCheckOpportunity() {
        guard isStarted, isAutomaticCheckEnabled else {
            return
        }
        scheduleNextAutomaticCheck(minimumDelay: 0)
    }

    private func performSharedCheck(source: CheckSource) async -> SharedCheckResult {
        if var activeCheck {
            if source == .manual, !activeCheck.hasManualWaiter {
                activeCheck.hasManualWaiter = true
                self.activeCheck = activeCheck
            }
            let generation = activeCheck.generation
            let result = await activeCheck.task.value
            await resultDeliveryBarrier(false)
            guard generation == checkGeneration else {
                return SharedCheckResult(state: nil, initiatedRequest: false)
            }
            return SharedCheckResult(state: result, initiatedRequest: false)
        }

        checkGeneration &+= 1
        let generation = checkGeneration
        defaults.set(clock(), forKey: UpdateCheckPreferenceKey.lastAttemptAt)

        let checker = checker
        let task = Task { @MainActor in
            await checker.checkForUpdates()
        }
        activeCheck = ActiveCheck(
            generation: generation,
            source: source,
            task: task,
            hasManualWaiter: source == .manual
        )

        let result = await task.value
        await resultDeliveryBarrier(true)
        guard generation == checkGeneration else {
            return SharedCheckResult(state: nil, initiatedRequest: true)
        }
        clearActiveCheck(ifGenerationMatches: generation)
        return SharedCheckResult(state: result, initiatedRequest: true)
    }

    private func clearActiveCheck(ifGenerationMatches generation: Int) {
        guard activeCheck?.generation == generation else {
            return
        }
        activeCheck = nil
    }

    private func cancelActiveCheck() {
        guard let activeCheck else {
            return
        }

        checkGeneration &+= 1
        self.activeCheck = nil
        activeCheck.task.cancel()
        checker.cancel()
    }

    private func applyCompletedCheck(_ result: AppUpdateState, source: CheckSource) {
        let completionDate = clock()

        switch result {
        case .upToDate:
            recordSuccessfulCheck(at: completionDate)
            clearAvailableUpdate()
            state = .upToDate
        case let .updateAvailable(version, url):
            guard let update = AppUpdateValidation.availableUpdate(
                version: version,
                url: url.absoluteString,
                installedVersion: installedVersion
            ) else {
                recordFailedCheck(at: completionDate)
                if source == .manual {
                    publishManualResult(.failed)
                }
                scheduleAfterCompletionIfNeeded()
                return
            }

            recordSuccessfulCheck(at: completionDate)
            persistAvailableUpdate(update)
            state = .updateAvailable(version: update.version, url: update.url)
        case .failed:
            recordFailedCheck(at: completionDate)
            if source == .manual {
                publishManualResult(.failed)
            }
        case .idle, .checking:
            return
        }

        scheduleAfterCompletionIfNeeded()
    }

    private func publishManualResult(_ result: AppUpdateState) {
        switch result {
        case let .updateAvailable(version, url):
            state = .updateAvailable(version: version, url: url)
        case .upToDate:
            state = .upToDate
        case .failed:
            state = .failed
        case .idle, .checking:
            break
        }
    }

    private func recordSuccessfulCheck(at date: Date) {
        defaults.set(date, forKey: UpdateCheckPreferenceKey.lastSuccessAt)
        defaults.set(0, forKey: UpdateCheckPreferenceKey.consecutiveFailureCount)
        defaults.set(
            date.addingTimeInterval(Self.successfulCheckInterval),
            forKey: UpdateCheckPreferenceKey.nextEligibleAt
        )
    }

    private func recordFailedCheck(at date: Date) {
        let previousFailureCount = max(
            0,
            defaults.integer(forKey: UpdateCheckPreferenceKey.consecutiveFailureCount)
        )
        let failureCount = previousFailureCount == Int.max
            ? Int.max
            : previousFailureCount + 1
        let intervalIndex = min(
            failureCount - 1,
            Self.failureRetryIntervals.count - 1
        )
        defaults.set(
            failureCount,
            forKey: UpdateCheckPreferenceKey.consecutiveFailureCount
        )
        defaults.set(
            date.addingTimeInterval(Self.failureRetryIntervals[intervalIndex]),
            forKey: UpdateCheckPreferenceKey.nextEligibleAt
        )
    }

    private func persistAvailableUpdate(_ update: AvailableAppUpdate) {
        defaults.set(
            update.version,
            forKey: UpdateCheckPreferenceKey.availableVersion
        )
        defaults.set(
            update.url.absoluteString,
            forKey: UpdateCheckPreferenceKey.availableReleaseURL
        )
        availableUpdate = update

        let dismissedVersion = defaults.string(
            forKey: UpdateCheckPreferenceKey.dismissedBannerVersion
        )
        bannerUpdate = dismissedVersion == update.version ? nil : update
    }

    private func clearAvailableUpdate() {
        Self.clearPersistedAvailableUpdate(in: defaults)
        availableUpdate = nil
        bannerUpdate = nil
    }

    private func scheduleAfterCompletionIfNeeded() {
        guard isStarted, isAutomaticCheckEnabled else {
            return
        }
        scheduleNextAutomaticCheck(minimumDelay: 0)
    }

    private func isDue(at date: Date) -> Bool {
        guard let nextEligibleDate = storedNextEligibleDate(relativeTo: date) else {
            return true
        }
        return nextEligibleDate <= date
    }

    private func storedNextEligibleDate(relativeTo date: Date) -> Date? {
        guard let storedDate = defaults.object(
            forKey: UpdateCheckPreferenceKey.nextEligibleAt
        ) as? Date else {
            return nil
        }

        let latestReasonableDate = date.addingTimeInterval(Self.successfulCheckInterval)
        if storedDate > latestReasonableDate {
            defaults.set(
                latestReasonableDate,
                forKey: UpdateCheckPreferenceKey.nextEligibleAt
            )
            return latestReasonableDate
        }
        return storedDate
    }

    private func scheduleNextAutomaticCheck(minimumDelay: TimeInterval) {
        cancelScheduledCheck()
        guard isStarted, isAutomaticCheckEnabled else {
            return
        }

        let currentDate = clock()
        let dueDate = storedNextEligibleDate(relativeTo: currentDate) ?? currentDate
        let graceDelay = max(
            (automaticStartupGraceDeadline ?? 0) - monotonicClock(),
            0
        )
        let delay = max(
            minimumDelay,
            max(max(dueDate.timeIntervalSince(currentDate), graceDelay), 0)
        )
        scheduledCheckCancellation = scheduler(delay) { [weak self] in
            guard let self else {
                return
            }
            self.scheduledCheckCancellation = nil
            Task { @MainActor [weak self] in
                await self?.checkIfDue()
            }
        }
    }

    private func cancelScheduledCheck() {
        scheduledCheckCancellation?()
        scheduledCheckCancellation = nil
    }

    private static func restoreAvailableUpdate(
        from defaults: UserDefaults,
        installedVersion: String
    ) -> AvailableAppUpdate? {
        guard
            let version = defaults.string(forKey: UpdateCheckPreferenceKey.availableVersion),
            let url = defaults.string(forKey: UpdateCheckPreferenceKey.availableReleaseURL),
            let update = AppUpdateValidation.availableUpdate(
                version: version,
                url: url,
                installedVersion: installedVersion
            )
        else {
            clearPersistedAvailableUpdate(in: defaults)
            return nil
        }
        return update
    }

    private static func clearPersistedAvailableUpdate(in defaults: UserDefaults) {
        defaults.removeObject(forKey: UpdateCheckPreferenceKey.availableVersion)
        defaults.removeObject(forKey: UpdateCheckPreferenceKey.availableReleaseURL)
    }

    private static func mainQueueScheduler(
        delay: TimeInterval,
        action: @escaping ScheduledAction
    ) -> Cancellation {
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
}
