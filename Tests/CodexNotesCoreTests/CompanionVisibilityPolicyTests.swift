import XCTest
@testable import CodexNotesCore

final class CompanionVisibilityPolicyTests: XCTestCase {
    private let companionBundleIdentifier = "tech.jiangsir.codex-task-notes"

    func testShowsWhileCodexIsFrontmost() {
        XCTAssertTrue(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: "com.openai.codex",
                companionBundleIdentifier: companionBundleIdentifier,
                isCodexAvailable: true
            )
        )
    }

    func testShowsWhileCompanionIsFrontmost() {
        XCTAssertTrue(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: companionBundleIdentifier,
                companionBundleIdentifier: companionBundleIdentifier,
                isCodexAvailable: true
            )
        )
    }

    func testHidesForUnrelatedApplication() {
        XCTAssertFalse(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: "com.google.Chrome",
                companionBundleIdentifier: companionBundleIdentifier,
                isCodexAvailable: true
            )
        )
    }

    func testHidesWhenFrontmostApplicationIsUnknown() {
        XCTAssertFalse(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: nil,
                companionBundleIdentifier: companionBundleIdentifier,
                isCodexAvailable: true
            )
        )
    }

    func testHidesWhenCodexIsUnavailableEvenIfSettingsIsFrontmost() {
        XCTAssertFalse(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: companionBundleIdentifier,
                companionBundleIdentifier: companionBundleIdentifier,
                isCodexAvailable: false
            )
        )
    }

    func testSettingsFrontmostDoesNotSuppressAnAvailableCodexCompanion() {
        XCTAssertTrue(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: companionBundleIdentifier,
                companionBundleIdentifier: companionBundleIdentifier,
                isCodexAvailable: true
            )
        )
    }
}
