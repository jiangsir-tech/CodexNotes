import CodexNotesCore
import Foundation
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

    func testSettingsActionAnnouncesAnAvailableUpdate() {
        let presentation = BottomBarActionPresentation.settings(updateVersion: "1.5.0")
        let expected = L10n.text(
            .bottomBarSettingsUpdateAvailableHelp,
            replacements: ["version": "1.5.0"]
        )

        XCTAssertEqual(presentation.systemImage, "gearshape")
        XCTAssertEqual(presentation.helpText, expected)
        XCTAssertEqual(presentation.accessibilityLabel, expected)
    }

    func testUpdateBannerPresentationKeepsActionsExplicit() {
        let update = AvailableAppUpdate(
            version: "1.5.0",
            url: URL(
                string: "https://github.com/jiangsir-tech/CodexNotes/releases/tag/v1.5.0"
            )!
        )
        let presentation = AppUpdateBannerPresentation(update)

        XCTAssertEqual(
            presentation.title,
            L10n.text(
                .appUpdateBannerAvailable,
                replacements: ["version": "1.5.0"]
            )
        )
        XCTAssertEqual(presentation.viewTitle, L10n.text(.settingsAboutViewUpdate))
        XCTAssertEqual(presentation.laterTitle, L10n.text(.appUpdateBannerLater))
        XCTAssertEqual(
            presentation.viewAccessibilityHint,
            L10n.text(.settingsAboutViewUpdateAccessibilityHint)
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
