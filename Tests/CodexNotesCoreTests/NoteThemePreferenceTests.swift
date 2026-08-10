import XCTest
@testable import CodexNotesCore

final class NoteThemePreferenceTests: XCTestCase {
    func testKeepsEverySupportedThemeIdentifier() {
        for theme in NoteThemeID.allCases {
            XCTAssertEqual(NoteThemePreference.normalized(theme.rawValue), theme)
        }
    }

    func testFallsBackToDefaultForUnknownIdentifier() {
        XCTAssertEqual(
            NoteThemePreference.normalized("theme-that-does-not-exist"),
            NoteThemePreference.defaultValue
        )
    }

    func testDefaultThemeIsMistPaper() {
        XCTAssertEqual(NoteThemePreference.defaultValue, .mistPaper)
    }

    func testSystemOriginalIdentifierRemainsStable() {
        XCTAssertEqual(NoteThemeID.systemOriginal.rawValue, "systemOriginal")
        XCTAssertEqual(
            NoteThemePreference.normalized("systemOriginal"),
            .systemOriginal
        )
    }

    func testPlumNightIdentifierRemainsStable() {
        XCTAssertEqual(NoteThemeID.plumNight.rawValue, "plumNight")
        XCTAssertEqual(
            NoteThemePreference.normalized("plumNight"),
            .plumNight
        )
    }
}
