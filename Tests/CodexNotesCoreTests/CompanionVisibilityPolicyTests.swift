import XCTest
@testable import CodexNotesCore

final class CompanionVisibilityPolicyTests: XCTestCase {
    private let companionBundleIdentifier = "tech.jiangsir.codex-task-notes"

    func testShowsWhileCodexIsFrontmost() {
        XCTAssertTrue(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: "com.openai.codex",
                companionBundleIdentifier: companionBundleIdentifier
            )
        )
    }

    func testShowsWhileCompanionIsFrontmost() {
        XCTAssertTrue(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: companionBundleIdentifier,
                companionBundleIdentifier: companionBundleIdentifier
            )
        )
    }

    func testHidesForUnrelatedApplication() {
        XCTAssertFalse(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: "com.google.Chrome",
                companionBundleIdentifier: companionBundleIdentifier
            )
        )
    }

    func testHidesWhenFrontmostApplicationIsUnknown() {
        XCTAssertFalse(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: nil,
                companionBundleIdentifier: companionBundleIdentifier
            )
        )
    }

    func testHidesMainWindowWhileSettingsIsVisible() {
        XCTAssertFalse(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: companionBundleIdentifier,
                companionBundleIdentifier: companionBundleIdentifier,
                isSettingsVisible: true
            )
        )
    }

    func testShowsMainWindowAgainAfterSettingsCloses() {
        XCTAssertTrue(
            CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: companionBundleIdentifier,
                companionBundleIdentifier: companionBundleIdentifier,
                isSettingsVisible: false
            )
        )
    }
}
