import CodexNotesCore
@testable import CodexNotesProbe
import XCTest

final class BottomBarActionPresentationTests: XCTestCase {
    func testIconSymbolsMatchTheirActions() {
        XCTAssertEqual(BottomBarActionPresentation.files.systemImage, "folder")

        XCTAssertEqual(BottomBarActionPresentation.shortcuts.systemImage, "keyboard")

        XCTAssertEqual(BottomBarActionPresentation.settings.systemImage, "gearshape")
    }

    func testIconOnlyActionsKeepExplicitHelpAndAccessibilityMeaning() {
        XCTAssertEqual(
            BottomBarActionPresentation.files.helpText,
            L10n.text(.bottomBarFilesHelp)
        )
        XCTAssertEqual(
            BottomBarActionPresentation.files.accessibilityLabel,
            L10n.text(.bottomBarFilesHelp)
        )
        XCTAssertEqual(
            BottomBarActionPresentation.shortcuts.helpText,
            L10n.text(.bottomBarShortcutsHelp)
        )
        XCTAssertEqual(
            BottomBarActionPresentation.shortcuts.accessibilityLabel,
            L10n.text(.bottomBarShortcutsHelp)
        )
        XCTAssertEqual(
            BottomBarActionPresentation.settings.helpText,
            L10n.text(.bottomBarSettingsHelp)
        )
        XCTAssertEqual(
            BottomBarActionPresentation.settings.accessibilityLabel,
            L10n.text(.bottomBarSettingsHelp)
        )
    }

    func testActionTargetsRemainComfortablyClickableInResponsiveLayouts() {
        XCTAssertEqual(BottomBarActionMetrics.minimumHitSize, 28)
        XCTAssertGreaterThan(BottomBarActionMetrics.minimumHitSize, 18)
    }

    func testBottomBarUsesCompactBaselineWithoutShrinkingActionTargets() {
        XCTAssertEqual(BottomBarActionMetrics.editorSpacing, 8)
        XCTAssertEqual(BottomBarActionMetrics.groupVerticalPadding, 0)
        XCTAssertEqual(BottomBarActionMetrics.bottomPadding, 12)
        XCTAssertEqual(BottomBarActionMetrics.baselineVerticalFootprint, 48)
        XCTAssertGreaterThanOrEqual(BottomBarActionMetrics.minimumHitSize, 28)
    }

    func testMinimumWindowKeepsSpaceForResponsiveStatusContent() {
        XCTAssertEqual(BottomBarActionMetrics.minimumWindowWidth, 340)
        XCTAssertEqual(BottomBarActionMetrics.minimumInnerWidth, 308)
        XCTAssertEqual(BottomBarActionMetrics.actionGroupMinimumWidth, 92)
        XCTAssertEqual(
            BottomBarActionMetrics.minimumInnerWidth
                - BottomBarActionMetrics.actionGroupMinimumWidth,
            216
        )
        XCTAssertLessThan(
            BottomBarActionMetrics.actionGroupMinimumWidth,
            BottomBarActionMetrics.minimumInnerWidth
        )
    }

}
