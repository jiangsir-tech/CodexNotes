import XCTest
@testable import CodexNotesCore

final class EditorFontSizePreferenceTests: XCTestCase {
    func testKeepsSupportedWholePointSize() {
        XCTAssertEqual(EditorFontSizePreference.normalized(18), 18)
    }

    func testRoundsAndClampsUnsupportedValues() {
        XCTAssertEqual(EditorFontSizePreference.normalized(17.6), 18)
        XCTAssertEqual(EditorFontSizePreference.normalized(2), 12)
        XCTAssertEqual(EditorFontSizePreference.normalized(80), 24)
    }

    func testFallsBackForNonFiniteValues() {
        XCTAssertEqual(
            EditorFontSizePreference.normalized(.infinity),
            EditorFontSizePreference.defaultValue
        )
        XCTAssertEqual(
            EditorFontSizePreference.normalized(.nan),
            EditorFontSizePreference.defaultValue
        )
    }
}
