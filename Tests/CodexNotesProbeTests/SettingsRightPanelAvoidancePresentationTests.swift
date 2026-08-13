import CodexNotesCore
import XCTest
@testable import CodexNotesProbe

final class SettingsRightPanelAvoidancePresentationTests: XCTestCase {
    func testSettingsUsesTheSharedPersistentPreferenceForTheToggle() throws {
        let source = try settingsSource()

        XCTAssertTrue(source.contains(
            "@AppStorage(RightPanelAvoidancePreference.key)"
        ))
        XCTAssertTrue(source.contains(
            "RightPanelAvoidancePreference.defaultValue"
        ))
        XCTAssertTrue(source.contains("isOn: $rightPanelAvoidanceEnabled"))
        XCTAssertTrue(source.contains(".toggleStyle(.switch)"))
        XCTAssertTrue(source.contains(
            ".accessibilityLabel(Text(L10n.text(\n"
                + "                    .settingsRightPanelAvoidanceTitle"
        ))
        XCTAssertTrue(source.contains(
            ".accessibilityHint(Text(L10n.text(\n"
                + "                    .settingsRightPanelAvoidanceDescription"
        ))
    }

    func testPermissionStatusIsSeparateFromTheFeatureToggle() throws {
        let source = try settingsSource()

        XCTAssertTrue(source.contains(
            ".settingsRightPanelAvoidancePermissionTitle"
        ))
        XCTAssertTrue(source.contains(
            ".settingsRightPanelAvoidanceAuthorized"
        ))
        XCTAssertTrue(source.contains(
            ".settingsRightPanelAvoidanceNotAuthorized"
        ))
        XCTAssertTrue(source.contains(
            "if rightPanelAvoidanceEnabled && !isAccessibilityAuthorized"
        ))
        XCTAssertFalse(source.contains("if !isAccessibilityAuthorized {"))
        XCTAssertTrue(source.contains(
            ".settingsRightPanelAvoidanceRequestPermission"
        ))
        XCTAssertTrue(source.contains(
            ".settingsRightPanelAvoidanceOpenSystemSettings"
        ))
    }

    func testCopyExplainsAutomaticBehaviorAndIndependentManualCollapse() {
        let chinese = AppLocalization(preference: .simplifiedChinese)
        let english = AppLocalization(preference: .english)

        XCTAssertEqual(
            chinese.text(.settingsRightPanelAvoidancePermissionTitle),
            "辅助功能权限"
        )
        XCTAssertEqual(
            english.text(.settingsRightPanelAvoidancePermissionTitle),
            "Accessibility Permission"
        )
        XCTAssertTrue(
            chinese.text(.settingsRightPanelAvoidanceDescription)
                .contains("手动折叠和展开")
        )
        XCTAssertTrue(
            english.text(.settingsRightPanelAvoidanceDescription)
                .contains("manually")
        )
    }

    private func settingsSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/CodexNotesProbe/SettingsView.swift"
            ),
            encoding: .utf8
        )
    }
}
