import XCTest
@testable import CodexNotesProbe

final class CodexApplicationControllerTests: XCTestCase {
    func testRunningCodexIsActivatedInsteadOfRelaunched() {
        XCTAssertEqual(
            CodexApplicationActivationPolicy.plan(
                hasRunningApplication: true,
                hasInstalledApplication: true
            ),
            .activateRunning
        )
    }

    func testInstalledCodexIsLaunchedWhenNotRunning() {
        XCTAssertEqual(
            CodexApplicationActivationPolicy.plan(
                hasRunningApplication: false,
                hasInstalledApplication: true
            ),
            .launchInstalled
        )
    }

    func testMissingCodexIsUnavailable() {
        XCTAssertEqual(
            CodexApplicationActivationPolicy.plan(
                hasRunningApplication: false,
                hasInstalledApplication: false
            ),
            .unavailable
        )
    }

    func testCooperativeActivationIsOnlyUsedWhileCompanionIsActive() {
        XCTAssertTrue(
            CodexApplicationActivationPolicy.shouldUseCooperativeActivation(
                isCompanionApplicationActive: true
            )
        )
        XCTAssertFalse(
            CodexApplicationActivationPolicy.shouldUseCooperativeActivation(
                isCompanionApplicationActive: false
            )
        )
    }

    func testActivationTimeoutIsFiniteAndPositive() {
        XCTAssertGreaterThan(
            CodexApplicationActivationPolicy.timeoutInterval,
            0
        )
        XCTAssertLessThanOrEqual(
            CodexApplicationActivationPolicy.timeoutInterval,
            15
        )
    }

    @MainActor
    func testLaunchConfigurationActivatesExistingApplicationInstance() {
        let configuration = CodexApplicationController.launchConfiguration()

        XCTAssertTrue(configuration.activates)
        XCTAssertFalse(configuration.createsNewApplicationInstance)
        XCTAssertFalse(configuration.addsToRecentItems)
    }
}
