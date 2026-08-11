import AppKit
import CodexNotesCore
import XCTest
@testable import CodexNotesProbe

final class SettingsEditorPresentationTests: XCTestCase {
    func testLocalizedEditorLabelsFitTheReservedControlColumn() {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)

        for preference in [
            AppLanguagePreference.simplifiedChinese,
            AppLanguagePreference.english,
        ] {
            let localization = AppLocalization(preference: preference)

            for key in [
                L10n.Key.settingsEditorFontSize,
                L10n.Key.settingsEditorLineSpacing,
            ] {
                let label = localization.text(key)
                let width = (label as NSString).size(
                    withAttributes: [.font: font]
                ).width

                XCTAssertLessThanOrEqual(
                    width,
                    SettingsEditorPresentation.controlLabelWidth,
                    "\(preference.rawValue) label \(label) is wider than the reserved column"
                )
            }
        }
    }

    func testResizeHintAndIndependentRestoreActionsUseAnAdaptiveFooter() throws {
        let source = try repositorySource(
            at: "Sources/CodexNotesProbe/SettingsView.swift"
        )

        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains(
            ".fixedSize(horizontal: false, vertical: true)"
        ))
        XCTAssertTrue(source.contains("HStack(spacing: 8)"))
        XCTAssertTrue(source.contains("VStack(alignment: .trailing, spacing: 6)"))
        XCTAssertTrue(source.contains(".settingsEditorWindowResizeHint"))
        XCTAssertFalse(source.contains("settingsEditorPreviewText"))
        XCTAssertFalse(source.contains("settingsEditorPreviewAccessibilityLabel"))
        XCTAssertFalse(source.contains("settings.editor.preview_text"))
        XCTAssertTrue(source.contains("value: editorFontSize"))
        XCTAssertTrue(source.contains("value: editorLineSpacing"))
        XCTAssertTrue(source.contains("editorRestoreWindowSizeButton"))
        XCTAssertTrue(source.contains(".settingsEditorRestoreWindowSize"))
        XCTAssertTrue(source.contains(
            "Label(\n                L10n.text(.settingsEditorRestoreWindowSize),"
        ))
        XCTAssertTrue(source.contains(
            "MainWindowCommandNotification.restoreDefaultSize"
        ))
        XCTAssertTrue(source.contains(
            "MainWindowCommandNotification.didRestoreDefaultSize"
        ))
        XCTAssertTrue(source.contains(
            "Image(systemName: \"arrow.up.left.and.arrow.down.right\")"
        ))
        XCTAssertTrue(source.contains(".accessibilityElement(children: .combine)"))

        let hintRange = try XCTUnwrap(source.range(of: "editorWindowResizeHint"))
        let windowRestoreRange = try XCTUnwrap(
            source.range(of: "editorRestoreWindowSizeButton")
        )
        let restoreRange = try XCTUnwrap(source.range(of: "editorRestoreDefaultsButton"))
        XCTAssertLessThan(hintRange.lowerBound, windowRestoreRange.lowerBound)
        XCTAssertLessThan(windowRestoreRange.lowerBound, restoreRange.lowerBound)
        XCTAssertEqual(
            SettingsEditorPresentation.restoreConfirmationDurationNanoseconds,
            1_500_000_000
        )
    }

    private func repositorySource(at relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
