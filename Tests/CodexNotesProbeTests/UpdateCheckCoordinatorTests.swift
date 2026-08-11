import AppKit
import Foundation
import XCTest
@testable import CodexNotesProbe

@MainActor
final class UpdateCheckCoordinatorTests: XCTestCase {
    func testAutomaticChecksDefaultToOffAndStartDoesNotScheduleWork() {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let clock = TestClock(now: referenceDate)
        let scheduler = TestUpdateScheduler()
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: successfulChecker(tag: "1.4.68"),
            clock: clock,
            scheduler: scheduler
        )

        XCTAssertFalse(coordinator.isAutomaticCheckEnabled)

        coordinator.start()

        XCTAssertTrue(scheduler.activeDelays.isEmpty)
        XCTAssertFalse(
            fixture.defaults.bool(forKey: UpdateCheckPreferenceKey.automaticChecksEnabled)
        )
        coordinator.stop()
    }

    func testStartingWhenDueUsesTenSecondLaunchDelayAndRecordsRollingDay() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let clock = TestClock(now: referenceDate)
        let scheduler = TestUpdateScheduler()
        let fetcher = ScriptedUpdateFetcher(outcomes: [
            .response(releaseData(tag: "1.4.68"), httpResponse(statusCode: 200))
        ])
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            scheduler: scheduler
        )

        coordinator.start()

        XCTAssertEqual(scheduler.activeDelays, [10])
        clock.now = referenceDate.addingTimeInterval(10)
        scheduler.runNext()
        await waitUntil { coordinator.state == .upToDate }

        let fetchCallCount = await fetcher.callCount
        XCTAssertEqual(fetchCallCount, 1)
        XCTAssertEqual(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.lastAttemptAt) as? Date,
            referenceDate.addingTimeInterval(10)
        )
        XCTAssertEqual(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.lastSuccessAt) as? Date,
            referenceDate.addingTimeInterval(10)
        )
        XCTAssertEqual(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.nextEligibleAt) as? Date,
            referenceDate.addingTimeInterval(10 + 24 * 60 * 60)
        )
        XCTAssertEqual(scheduler.activeDelays, [24 * 60 * 60])
        coordinator.stop()
    }

    func testEnablingAutomaticChecksSchedulesAnImmediatelyDueBackgroundCheck() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let clock = TestClock(now: referenceDate)
        let scheduler = TestUpdateScheduler()
        let fetcher = ScriptedUpdateFetcher(outcomes: [
            .response(releaseData(tag: "1.4.68"), httpResponse(statusCode: 200))
        ])
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            scheduler: scheduler
        )
        coordinator.start()

        coordinator.setAutomaticChecksEnabled(true)

        XCTAssertTrue(coordinator.isAutomaticCheckEnabled)
        XCTAssertTrue(
            fixture.defaults.bool(forKey: UpdateCheckPreferenceKey.automaticChecksEnabled)
        )
        XCTAssertEqual(scheduler.activeDelays, [0])
        scheduler.runNext()
        await waitUntil { coordinator.state == .upToDate }
        let fetchCallCount = await fetcher.callCount
        XCTAssertEqual(fetchCallCount, 1)
        coordinator.stop()
    }

    func testManualSuccessResetsFailureCountAndTwentyFourHourSchedule() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(3, forKey: UpdateCheckPreferenceKey.consecutiveFailureCount)
        fixture.defaults.set(
            referenceDate.addingTimeInterval(-1),
            forKey: UpdateCheckPreferenceKey.nextEligibleAt
        )
        let clock = TestClock(now: referenceDate)
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: successfulChecker(tag: "1.4.68"),
            clock: clock,
            scheduler: TestUpdateScheduler()
        )

        await coordinator.manualCheck()

        XCTAssertEqual(coordinator.state, .upToDate)
        XCTAssertEqual(
            fixture.defaults.integer(
                forKey: UpdateCheckPreferenceKey.consecutiveFailureCount
            ),
            0
        )
        XCTAssertEqual(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.nextEligibleAt) as? Date,
            referenceDate.addingTimeInterval(24 * 60 * 60)
        )
    }

    func testFailuresUseOneThreeSixAndTwentyFourHourPersistentBackoff() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        let clock = TestClock(now: referenceDate)
        let fetcher = ScriptedUpdateFetcher(outcomes: [
            .failure,
            .failure,
            .failure,
            .failure,
            .failure
        ])
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            scheduler: TestUpdateScheduler()
        )
        let expectedIntervals: [TimeInterval] = [
            60 * 60,
            3 * 60 * 60,
            6 * 60 * 60,
            24 * 60 * 60,
            24 * 60 * 60
        ]

        for (index, interval) in expectedIntervals.enumerated() {
            clock.now = referenceDate.addingTimeInterval(TimeInterval(index * 100))
            await coordinator.manualCheck()
            XCTAssertEqual(coordinator.state, .failed)
            XCTAssertEqual(
                fixture.defaults.integer(
                    forKey: UpdateCheckPreferenceKey.consecutiveFailureCount
                ),
                index + 1
            )
            XCTAssertEqual(
                fixture.defaults.object(
                    forKey: UpdateCheckPreferenceKey.nextEligibleAt
                ) as? Date,
                clock.now.addingTimeInterval(interval)
            )
        }
    }

    func testAutomaticFailureIsSilentAndDoesNotReplaceCachedUpdate() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        seedCachedUpdate(in: fixture.defaults, version: "1.5.0")
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        fixture.defaults.set(
            referenceDate.addingTimeInterval(-1),
            forKey: UpdateCheckPreferenceKey.nextEligibleAt
        )
        let clock = TestClock(now: referenceDate)
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { _ in
            throw TestFetchError.failed
        }
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            scheduler: TestUpdateScheduler()
        )
        let expectedUpdate = AvailableAppUpdate(version: "1.5.0", url: releaseURL("1.5.0"))

        coordinator.start()
        clock.now = referenceDate.addingTimeInterval(10)
        await coordinator.checkIfDue()

        XCTAssertEqual(coordinator.availableUpdate, expectedUpdate)
        XCTAssertEqual(coordinator.bannerUpdate, expectedUpdate)
        XCTAssertEqual(
            coordinator.state,
            .updateAvailable(version: "1.5.0", url: releaseURL("1.5.0"))
        )
        XCTAssertEqual(
            fixture.defaults.integer(
                forKey: UpdateCheckPreferenceKey.consecutiveFailureCount
            ),
            1
        )
    }

    func testCacheIsRejectedForUnsafeURLOrVersionNotNewerThanInstalled() {
        let unsafeFixture = makeFixture()
        defer { unsafeFixture.remove() }
        unsafeFixture.defaults.set(
            "1.5.0",
            forKey: UpdateCheckPreferenceKey.availableVersion
        )
        unsafeFixture.defaults.set(
            "https://github.com.evil.example/jiangsir-tech/CodexNotes/releases/tag/v1.5.0",
            forKey: UpdateCheckPreferenceKey.availableReleaseURL
        )

        let unsafeCoordinator = makeCoordinator(
            defaults: unsafeFixture.defaults,
            checker: successfulChecker(tag: "1.4.68"),
            clock: TestClock(now: referenceDate),
            scheduler: TestUpdateScheduler()
        )

        XCTAssertNil(unsafeCoordinator.availableUpdate)
        XCTAssertNil(
            unsafeFixture.defaults.object(
                forKey: UpdateCheckPreferenceKey.availableReleaseURL
            )
        )

        let staleFixture = makeFixture()
        defer { staleFixture.remove() }
        seedCachedUpdate(in: staleFixture.defaults, version: "1.5.0")
        let staleCoordinator = makeCoordinator(
            defaults: staleFixture.defaults,
            checker: successfulChecker(tag: "1.5.0", currentVersion: "1.5.0"),
            installedVersion: "1.5.0",
            clock: TestClock(now: referenceDate),
            scheduler: TestUpdateScheduler()
        )

        XCTAssertNil(staleCoordinator.availableUpdate)
        XCTAssertEqual(staleCoordinator.state, .idle)
        XCTAssertNil(
            staleFixture.defaults.object(forKey: UpdateCheckPreferenceKey.availableVersion)
        )
    }

    func testCacheRejectsNonTagWrongTagAndNonExactReleaseURLs() {
        let invalidURLs = [
            "https://github.com/jiangsir-tech/CodexNotes/releases/download/v1.5.0/CodexNotes.zip",
            "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v9.9.9",
            "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0/extra",
            "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0?download=1",
            "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0#notes"
        ]

        for invalidURL in invalidURLs {
            let fixture = makeFixture()
            defer { fixture.remove() }
            fixture.defaults.set(
                "1.5.0",
                forKey: UpdateCheckPreferenceKey.availableVersion
            )
            fixture.defaults.set(
                invalidURL,
                forKey: UpdateCheckPreferenceKey.availableReleaseURL
            )

            let coordinator = makeCoordinator(
                defaults: fixture.defaults,
                checker: successfulChecker(tag: "1.4.68"),
                clock: TestClock(now: referenceDate),
                scheduler: TestUpdateScheduler()
            )

            XCTAssertNil(coordinator.availableUpdate, "Accepted \(invalidURL)")
            XCTAssertNil(
                fixture.defaults.object(
                    forKey: UpdateCheckPreferenceKey.availableReleaseURL
                )
            )
        }
    }

    func testBannerDismissalPersistsPerVersionAndNewVersionAppearsAgain() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        seedCachedUpdate(in: fixture.defaults, version: "1.5.0")
        fixture.defaults.set(
            "1.5.0",
            forKey: UpdateCheckPreferenceKey.dismissedBannerVersion
        )
        let clock = TestClock(now: referenceDate)
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: successfulChecker(tag: "1.6.0"),
            clock: clock,
            scheduler: TestUpdateScheduler()
        )

        XCTAssertNil(coordinator.bannerUpdate)
        await coordinator.manualCheck()

        let newUpdate = AvailableAppUpdate(version: "1.6.0", url: releaseURL("1.6.0"))
        XCTAssertEqual(coordinator.availableUpdate, newUpdate)
        XCTAssertEqual(coordinator.bannerUpdate, newUpdate)

        coordinator.dismissBanner()

        XCTAssertNil(coordinator.bannerUpdate)
        XCTAssertEqual(
            fixture.defaults.string(
                forKey: UpdateCheckPreferenceKey.dismissedBannerVersion
            ),
            "1.6.0"
        )

        let restoredCoordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: successfulChecker(tag: "1.6.0"),
            clock: clock,
            scheduler: TestUpdateScheduler()
        )
        XCTAssertEqual(restoredCoordinator.availableUpdate, newUpdate)
        XCTAssertNil(restoredCoordinator.bannerUpdate)
    }

    func testUpToDateResultClearsCachedUpdateAndBanner() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        seedCachedUpdate(in: fixture.defaults, version: "1.5.0")
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: successfulChecker(tag: "1.4.68"),
            clock: TestClock(now: referenceDate),
            scheduler: TestUpdateScheduler()
        )

        await coordinator.manualCheck()

        XCTAssertEqual(coordinator.state, .upToDate)
        XCTAssertNil(coordinator.availableUpdate)
        XCTAssertNil(coordinator.bannerUpdate)
        XCTAssertNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.availableVersion)
        )
        XCTAssertNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.availableReleaseURL)
        )
    }

    func testManualCheckJoinsAutomaticRequestAndPublishesItsResult() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let suspendedFetcher = SuspendedCoordinatorFetcher(
            result: (
                releaseData(tag: "1.5.0"),
                httpResponse(statusCode: 200)
            )
        )
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await suspendedFetcher.fetch(request)
        }
        let clock = TestClock(now: referenceDate)
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            scheduler: TestUpdateScheduler()
        )
        coordinator.start()
        clock.now = referenceDate.addingTimeInterval(10)

        let automaticCheck = Task { await coordinator.checkIfDue() }
        await waitUntil { await suspendedFetcher.callCount == 1 }
        XCTAssertEqual(coordinator.state, .idle)

        let manualCheck = Task { await coordinator.manualCheck() }
        await waitUntil { coordinator.state == .checking }
        let joinedCallCount = await suspendedFetcher.callCount
        XCTAssertEqual(joinedCallCount, 1)

        await suspendedFetcher.resume()
        await automaticCheck.value
        await manualCheck.value

        let completedCallCount = await suspendedFetcher.callCount
        XCTAssertEqual(completedCallCount, 1)
        XCTAssertEqual(
            coordinator.state,
            .updateAvailable(version: "1.5.0", url: releaseURL("1.5.0"))
        )
        XCTAssertNotNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.lastSuccessAt)
        )
    }

    func testJoinerFinishesFirstWithoutReleasingSingleFlightOwnership() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let fetcher = SuspendedCoordinatorFetcher(
            result: (
                releaseData(tag: "1.5.0"),
                httpResponse(statusCode: 200)
            )
        )
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }
        let clock = TestClock(now: referenceDate)
        let barrier = InitiatorOnlyResultDeliveryBarrier()
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            scheduler: TestUpdateScheduler(),
            resultDeliveryBarrier: barrier.wait
        )
        coordinator.start()
        clock.now = referenceDate.addingTimeInterval(10)

        let initiator = Task { await coordinator.checkIfDue() }
        await waitUntil { await fetcher.callCount == 1 }
        let manualJoiner = Task { await coordinator.manualCheck() }
        await waitUntil { coordinator.state == .checking }

        await fetcher.resume()
        await manualJoiner.value

        XCTAssertEqual(
            coordinator.state,
            .updateAvailable(version: "1.5.0", url: releaseURL("1.5.0"))
        )
        XCTAssertNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.lastSuccessAt)
        )

        await coordinator.checkIfDue()
        let callCountBeforeInitiatorDelivery = await fetcher.callCount
        XCTAssertEqual(callCountBeforeInitiatorDelivery, 1)
        XCTAssertGreaterThanOrEqual(barrier.joinedDeliveryCount, 2)

        barrier.resumeInitiator()
        await initiator.value

        let finalCallCount = await fetcher.callCount
        XCTAssertEqual(finalCallCount, 1)
        XCTAssertNotNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.lastSuccessAt)
        )
        XCTAssertNotNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.nextEligibleAt)
        )
        XCTAssertEqual(coordinator.availableUpdate?.version, "1.5.0")
        coordinator.stop()
    }

    func testStoppingCancelsAutomaticRequestWithoutRecordingFailure() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let suspendedFetcher = SuspendedCoordinatorFetcher(
            result: (
                releaseData(tag: "1.5.0"),
                httpResponse(statusCode: 200)
            )
        )
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await suspendedFetcher.fetch(request)
        }
        let clock = TestClock(now: referenceDate)
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            scheduler: TestUpdateScheduler()
        )
        coordinator.start()
        clock.now = referenceDate.addingTimeInterval(10)

        let automaticCheck = Task { await coordinator.checkIfDue() }
        await waitUntil { await suspendedFetcher.callCount == 1 }
        coordinator.stop()
        await suspendedFetcher.resume()
        await automaticCheck.value

        XCTAssertEqual(
            fixture.defaults.integer(
                forKey: UpdateCheckPreferenceKey.consecutiveFailureCount
            ),
            0
        )
        XCTAssertNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.nextEligibleAt)
        )
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testCompletedAutomaticResultIsDiscardedWhenStopWinsDeliveryRace() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let clock = TestClock(now: referenceDate)
        let barrier = TestResultDeliveryBarrier()
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: successfulChecker(tag: "1.5.0"),
            clock: clock,
            scheduler: TestUpdateScheduler(),
            resultDeliveryBarrier: barrier.wait
        )
        coordinator.start()
        clock.now = referenceDate.addingTimeInterval(10)

        let automaticCheck = Task { await coordinator.checkIfDue() }
        await waitUntil { barrier.entryCount == 1 }
        coordinator.stop()
        barrier.resume()
        await automaticCheck.value

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.availableUpdate)
        XCTAssertNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.lastSuccessAt)
        )
        XCTAssertNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.nextEligibleAt)
        )
    }

    func testCompletedAutomaticResultIsDiscardedWhenDisableWinsDeliveryRace() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let clock = TestClock(now: referenceDate)
        let barrier = TestResultDeliveryBarrier()
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: successfulChecker(tag: "1.5.0"),
            clock: clock,
            scheduler: TestUpdateScheduler(),
            resultDeliveryBarrier: barrier.wait
        )
        coordinator.start()
        clock.now = referenceDate.addingTimeInterval(10)

        let automaticCheck = Task { await coordinator.checkIfDue() }
        await waitUntil { barrier.entryCount == 1 }
        coordinator.setAutomaticChecksEnabled(false)
        barrier.resume()
        await automaticCheck.value

        XCTAssertFalse(coordinator.isAutomaticCheckEnabled)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.availableUpdate)
        XCTAssertNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.lastSuccessAt)
        )
        XCTAssertNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.nextEligibleAt)
        )
        coordinator.stop()
    }

    func testActivationAndWakeRescheduleAnOverdueCheckImmediately() {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        fixture.defaults.set(
            referenceDate.addingTimeInterval(100),
            forKey: UpdateCheckPreferenceKey.nextEligibleAt
        )
        let clock = TestClock(now: referenceDate)
        let scheduler = TestUpdateScheduler()
        let appCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: successfulChecker(tag: "1.4.68"),
            clock: clock,
            scheduler: scheduler,
            applicationNotificationCenter: appCenter,
            workspaceNotificationCenter: workspaceCenter
        )
        coordinator.start()
        XCTAssertEqual(scheduler.activeDelays, [100])

        clock.now = referenceDate.addingTimeInterval(101)
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(scheduler.activeDelays, [0])

        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(scheduler.activeDelays, [0])
        coordinator.stop()
    }

    func testActivationAndWakeCannotBypassStartupGraceDeadline() {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let clock = TestClock(now: referenceDate)
        let scheduler = TestUpdateScheduler()
        let appCenter = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: successfulChecker(tag: "1.4.68"),
            clock: clock,
            scheduler: scheduler,
            applicationNotificationCenter: appCenter,
            workspaceNotificationCenter: workspaceCenter
        )

        coordinator.start()
        XCTAssertEqual(scheduler.activeDelays, [10])

        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(scheduler.activeDelays, [10])

        clock.now = referenceDate.addingTimeInterval(4)
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(scheduler.activeDelays, [6])
        coordinator.stop()
    }

    func testForwardWallClockJumpCannotBypassMonotonicStartupGrace() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let clock = TestClock(now: referenceDate)
        let monotonicClock = TestMonotonicClock(now: 500)
        let scheduler = TestUpdateScheduler()
        let appCenter = NotificationCenter()
        let fetcher = ScriptedUpdateFetcher(outcomes: [
            .response(releaseData(tag: "1.4.68"), httpResponse(statusCode: 200))
        ])
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            monotonicClock: monotonicClock,
            scheduler: scheduler,
            applicationNotificationCenter: appCenter
        )
        coordinator.start()

        clock.now = referenceDate.addingTimeInterval(365 * 24 * 60 * 60)
        monotonicClock.now = 502
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        XCTAssertEqual(scheduler.activeDelays, [8])
        await coordinator.checkIfDue()
        let callCount = await fetcher.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(scheduler.activeDelays, [8])
        coordinator.stop()
    }

    func testBackwardWallClockJumpCannotExtendMonotonicStartupGrace() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let clock = TestClock(now: referenceDate)
        let monotonicClock = TestMonotonicClock(now: 800)
        let scheduler = TestUpdateScheduler()
        let workspaceCenter = NotificationCenter()
        let fetcher = ScriptedUpdateFetcher(outcomes: [
            .response(releaseData(tag: "1.4.68"), httpResponse(statusCode: 200))
        ])
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            monotonicClock: monotonicClock,
            scheduler: scheduler,
            workspaceNotificationCenter: workspaceCenter
        )
        coordinator.start()

        clock.now = referenceDate.addingTimeInterval(-365 * 24 * 60 * 60)
        monotonicClock.now = 804
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(scheduler.activeDelays, [6])

        monotonicClock.now = 810
        workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(scheduler.activeDelays, [0])
        scheduler.runNext()
        await waitUntil { coordinator.state == .upToDate }

        let callCount = await fetcher.callCount
        XCTAssertEqual(callCount, 1)
        coordinator.stop()
    }

    func testTimerFiringThenStopPreventsQueuedAutomaticTaskFromRequesting() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        let clock = TestClock(now: referenceDate)
        let scheduler = TestUpdateScheduler()
        let fetcher = ScriptedUpdateFetcher(outcomes: [
            .response(releaseData(tag: "1.4.68"), httpResponse(statusCode: 200))
        ])
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: clock,
            scheduler: scheduler
        )
        coordinator.start()
        clock.now = referenceDate.addingTimeInterval(10)

        scheduler.runNext()
        coordinator.stop()
        for _ in 0..<5 {
            await Task.yield()
        }

        let callCount = await fetcher.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertNil(
            fixture.defaults.object(forKey: UpdateCheckPreferenceKey.lastAttemptAt)
        )
    }

    func testCheckBeforeEligibilityDoesNotIssueRequest() async {
        let fixture = makeFixture()
        defer { fixture.remove() }
        fixture.defaults.set(
            true,
            forKey: UpdateCheckPreferenceKey.automaticChecksEnabled
        )
        fixture.defaults.set(
            referenceDate.addingTimeInterval(3_600),
            forKey: UpdateCheckPreferenceKey.nextEligibleAt
        )
        let fetcher = ScriptedUpdateFetcher(outcomes: [
            .response(releaseData(tag: "1.4.68"), httpResponse(statusCode: 200))
        ])
        let checker = AppUpdateChecker(currentVersion: "1.4.68") { request in
            try await fetcher.fetch(request)
        }
        let coordinator = makeCoordinator(
            defaults: fixture.defaults,
            checker: checker,
            clock: TestClock(now: referenceDate),
            scheduler: TestUpdateScheduler()
        )
        coordinator.start()

        await coordinator.checkIfDue()

        let fetchCallCount = await fetcher.callCount
        XCTAssertEqual(fetchCallCount, 0)
        XCTAssertEqual(coordinator.state, .idle)
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func makeCoordinator(
        defaults: UserDefaults,
        checker: AppUpdateChecker,
        installedVersion: String = "1.4.68",
        clock: TestClock,
        monotonicClock: TestMonotonicClock? = nil,
        scheduler: TestUpdateScheduler,
        applicationNotificationCenter: NotificationCenter = NotificationCenter(),
        workspaceNotificationCenter: NotificationCenter = NotificationCenter(),
        resultDeliveryBarrier: @escaping UpdateCheckCoordinator.ResultDeliveryBarrier = { _ in }
    ) -> UpdateCheckCoordinator {
        UpdateCheckCoordinator(
            defaults: defaults,
            checker: checker,
            installedVersion: installedVersion,
            clock: { clock.now },
            monotonicClock: {
                monotonicClock?.now ?? clock.now.timeIntervalSinceReferenceDate
            },
            scheduler: scheduler.schedule,
            applicationNotificationCenter: applicationNotificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter,
            resultDeliveryBarrier: resultDeliveryBarrier
        )
    }

    private func successfulChecker(
        tag: String,
        currentVersion: String = "1.4.68"
    ) -> AppUpdateChecker {
        let data = releaseData(tag: tag)
        let response = httpResponse(statusCode: 200)
        return AppUpdateChecker(currentVersion: currentVersion) { _ in
            (data, response)
        }
    }

    private func seedCachedUpdate(in defaults: UserDefaults, version: String) {
        defaults.set(version, forKey: UpdateCheckPreferenceKey.availableVersion)
        defaults.set(
            releaseURL(version).absoluteString,
            forKey: UpdateCheckPreferenceKey.availableReleaseURL
        )
    }

    private func releaseURL(_ version: String) -> URL {
        URL(
            string: "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v\(version)"
        )!
    }

    private func releaseData(tag: String) -> Data {
        let normalizedVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag,
            "html_url": releaseURL(normalizedVersion).absoluteString,
            "draft": false,
            "prerelease": false
        ])
    }

    private func httpResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: AppUpdateChecker.latestReleaseAPIURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
    }

    private func makeFixture() -> DefaultsFixture {
        DefaultsFixture()
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        _ predicate: @escaping @MainActor () async -> Bool
    ) async {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        while !(await predicate()) {
            if DispatchTime.now().uptimeNanoseconds - startedAt >= timeoutNanoseconds {
                XCTFail("Timed out waiting for asynchronous coordinator state")
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

private final class DefaultsFixture {
    let defaults: UserDefaults
    private let suiteName: String

    init() {
        suiteName = "UpdateCheckCoordinatorTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class TestMonotonicClock {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}

@MainActor
private final class TestResultDeliveryBarrier {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entryCount = 0

    func wait(initiatedRequest: Bool) async {
        entryCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class InitiatorOnlyResultDeliveryBarrier {
    private var initiatorContinuation: CheckedContinuation<Void, Never>?
    private(set) var joinedDeliveryCount = 0

    func wait(initiatedRequest: Bool) async {
        guard initiatedRequest else {
            joinedDeliveryCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            initiatorContinuation = continuation
        }
    }

    func resumeInitiator() {
        initiatorContinuation?.resume()
        initiatorContinuation = nil
    }
}

@MainActor
private final class TestUpdateScheduler {
    private final class Token {
        var isCancelled = false
    }

    private struct Entry {
        let delay: TimeInterval
        let action: UpdateCheckCoordinator.ScheduledAction
        let token: Token
    }

    private var entries: [Entry] = []

    var activeDelays: [TimeInterval] {
        entries.filter { !$0.token.isCancelled }.map(\.delay)
    }

    func schedule(
        _ delay: TimeInterval,
        _ action: @escaping UpdateCheckCoordinator.ScheduledAction
    ) -> UpdateCheckCoordinator.Cancellation {
        let token = Token()
        entries.append(Entry(delay: delay, action: action, token: token))
        return {
            token.isCancelled = true
        }
    }

    func runNext() {
        guard let index = entries.firstIndex(where: { !$0.token.isCancelled }) else {
            return
        }
        let entry = entries.remove(at: index)
        entry.token.isCancelled = true
        entry.action()
    }
}

private actor ScriptedUpdateFetcher {
    enum Outcome {
        case response(Data, URLResponse)
        case failure
    }

    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func fetch(_ request: URLRequest) throws -> (Data, URLResponse) {
        callCount += 1
        guard !outcomes.isEmpty else {
            throw TestFetchError.failed
        }
        switch outcomes.removeFirst() {
        case let .response(data, response):
            return (data, response)
        case .failure:
            throw TestFetchError.failed
        }
    }
}

private actor SuspendedCoordinatorFetcher {
    private let result: (Data, URLResponse)
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private(set) var callCount = 0

    init(result: (Data, URLResponse)) {
        self.result = result
    }

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private enum TestFetchError: Error {
    case failed
}
