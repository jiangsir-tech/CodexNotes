@testable import CodexNotesCore
@testable import CodexNotesProbe
import XCTest

final class TodoStatusPresentationTests: XCTestCase {
    func testNoTodosUsesAnExplicitNonInteractiveStatus() {
        let presentation = TodoStatusPresentation(
            MarkdownChecklistProgress(completed: 0, total: 0)
        )

        XCTAssertEqual(presentation.wideTitle, L10n.text(.todoBadgeEmpty))
        XCTAssertEqual(presentation.compactTitle, L10n.text(.todoBadgeEmpty))
        XCTAssertEqual(presentation.minimalTitle, L10n.text(.todoBadgeMinimal))
        XCTAssertEqual(presentation.systemImage, "checklist")
        XCTAssertEqual(presentation.accessibilityValue, L10n.text(.todoBadgeEmpty))
        XCTAssertFalse(presentation.isComplete)
    }

    func testPartialProgressKeepsTodoMeaningInBothWidths() {
        let presentation = TodoStatusPresentation(
            MarkdownChecklistProgress(completed: 5, total: 8)
        )

        let replacements = ["completed": "5", "total": "8"]
        XCTAssertEqual(
            presentation.wideTitle,
            L10n.text(.todoBadgeProgressWide, replacements: replacements)
        )
        XCTAssertEqual(
            presentation.compactTitle,
            L10n.text(.todoBadgeProgressCompact, replacements: replacements)
        )
        XCTAssertEqual(presentation.minimalTitle, "5/8")
        XCTAssertEqual(presentation.systemImage, "checklist")
        XCTAssertEqual(
            presentation.accessibilityValue,
            L10n.text(.todoAccessibilityProgress, replacements: replacements)
        )
        XCTAssertFalse(presentation.isComplete)
    }

    func testCompletedProgressUsesSuccessIconWithoutChangingTheCopy() {
        let presentation = TodoStatusPresentation(
            MarkdownChecklistProgress(completed: 8, total: 8)
        )

        let replacements = ["completed": "8", "total": "8"]
        XCTAssertEqual(
            presentation.wideTitle,
            L10n.text(.todoBadgeProgressWide, replacements: replacements)
        )
        XCTAssertEqual(
            presentation.compactTitle,
            L10n.text(.todoBadgeProgressCompact, replacements: replacements)
        )
        XCTAssertEqual(presentation.minimalTitle, "8/8")
        XCTAssertEqual(presentation.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(
            presentation.accessibilityValue,
            L10n.text(.todoAccessibilityProgress, replacements: replacements)
        )
        XCTAssertTrue(presentation.isComplete)
    }
}
