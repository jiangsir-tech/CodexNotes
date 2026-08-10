import XCTest
@testable import CodexNotesCore

final class EditorLineSpacingPreferenceTests: XCTestCase {
    func testKeepsSupportedWholePointSpacing() {
        XCTAssertEqual(EditorLineSpacingPreference.normalized(0), 0)
        XCTAssertEqual(
            EditorLineSpacingPreference.normalized(4),
            EditorLineSpacingPreference.defaultValue
        )
        XCTAssertEqual(EditorLineSpacingPreference.normalized(6), 6)
        XCTAssertEqual(EditorLineSpacingPreference.normalized(12), 12)
    }

    func testRoundsAndClampsUnsupportedValues() {
        XCTAssertEqual(EditorLineSpacingPreference.normalized(4.6), 5)
        XCTAssertEqual(EditorLineSpacingPreference.normalized(-2), 0)
        XCTAssertEqual(EditorLineSpacingPreference.normalized(30), 12)
    }

    func testFallsBackForNonFiniteValues() {
        XCTAssertEqual(
            EditorLineSpacingPreference.normalized(.infinity),
            EditorLineSpacingPreference.defaultValue
        )
        XCTAssertEqual(
            EditorLineSpacingPreference.normalized(.nan),
            EditorLineSpacingPreference.defaultValue
        )
    }
}
