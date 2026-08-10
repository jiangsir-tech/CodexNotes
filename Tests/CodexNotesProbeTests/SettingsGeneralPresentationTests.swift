import CodexNotesCore
import XCTest
@testable import CodexNotesProbe

final class SettingsGeneralPresentationTests: XCTestCase {
    func testLanguagePickerUsesCompactWidth() {
        XCTAssertEqual(SettingsGeneralPresentation.languagePickerWidth, 112)
    }

    func testLanguageOptionsUseTheExpectedOrder() {
        XCTAssertEqual(
            SettingsGeneralPresentation.languageOptions,
            [.system, .simplifiedChinese, .english]
        )
    }

    func testEveryLanguageOptionUsesItsDedicatedLocalizedLabel() {
        XCTAssertEqual(
            SettingsGeneralPresentation.languageLabelKey(for: .system),
            .languageSystem
        )
        XCTAssertEqual(
            SettingsGeneralPresentation.languageLabelKey(for: .simplifiedChinese),
            .languageSimplifiedChinese
        )
        XCTAssertEqual(
            SettingsGeneralPresentation.languageLabelKey(for: .english),
            .languageEnglish
        )
    }
}
