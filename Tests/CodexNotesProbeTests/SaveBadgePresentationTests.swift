import CodexNotesCore
@testable import CodexNotesProbe
import XCTest

final class SaveBadgePresentationTests: XCTestCase {
    func testNormalSaveStatesUseStableShortLabelsAndNonFailureTone() {
        let idle = SaveBadgePresentation(.idle)
        let saving = SaveBadgePresentation(.saving)
        let saved = SaveBadgePresentation(.saved)

        XCTAssertEqual(idle.title, L10n.text(.saveStatusIdleTitle))
        XCTAssertEqual(idle.systemImage, "circle")
        XCTAssertEqual(idle.iconTone, .neutral)
        XCTAssertEqual(idle.textTone, .neutral)
        XCTAssertFalse(idle.requiresText)

        XCTAssertEqual(saving.title, L10n.text(.saveStatusSavingTitle))
        XCTAssertEqual(saving.systemImage, "arrow.clockwise")
        XCTAssertEqual(saving.iconTone, .neutral)
        XCTAssertEqual(saving.textTone, .neutral)
        XCTAssertFalse(saving.requiresText)

        XCTAssertEqual(saved.title, L10n.text(.saveStatusSavedTitle))
        XCTAssertEqual(saved.systemImage, "checkmark")
        XCTAssertEqual(saved.iconTone, .success)
        XCTAssertEqual(saved.textTone, .neutral)
        XCTAssertFalse(saved.requiresText)
    }

    func testFailureKeepsVisibleTextAndExposesFailureReason() {
        let presentation = SaveBadgePresentation(.failed("磁盘已满"))

        XCTAssertEqual(presentation.title, L10n.text(.saveStatusFailedTitle))
        XCTAssertEqual(presentation.systemImage, "exclamationmark.circle.fill")
        XCTAssertEqual(presentation.iconTone, .failure)
        XCTAssertEqual(presentation.textTone, .failure)
        XCTAssertTrue(presentation.requiresText)
        XCTAssertEqual(
            presentation.helpText,
            L10n.text(
                .saveStatusFailedHelp,
                replacements: ["message": "磁盘已满"]
            )
        )
        XCTAssertEqual(
            presentation.accessibilityValue,
            L10n.text(
                .saveStatusFailedAccessibilityValue,
                replacements: ["message": "磁盘已满"]
            )
        )
    }

    func testAllSaveStatesProvideHelpAndAccessibilityValues() {
        let presentations = [
            SaveBadgePresentation(.idle),
            SaveBadgePresentation(.saving),
            SaveBadgePresentation(.saved),
            SaveBadgePresentation(.failed("无法写入")),
        ]

        for presentation in presentations {
            XCTAssertFalse(presentation.helpText.isEmpty)
            XCTAssertFalse(presentation.accessibilityValue.isEmpty)
        }
    }
}
