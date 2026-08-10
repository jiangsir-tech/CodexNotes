import Foundation
import XCTest
@testable import CodexNotesCore

final class StatusBarIconPreferenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "StatusBarIconPreferenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testKeepsEverySupportedIconIdentifier() {
        for icon in StatusBarIconID.allCases {
            XCTAssertEqual(StatusBarIconPreference.normalized(icon.rawValue), icon)
        }
    }

    func testDefaultIconIsCodexPencil() {
        XCTAssertEqual(StatusBarIconPreference.defaultValue, .codexPencil)
        XCTAssertEqual(StatusBarIconID.codexPencil.rawValue, "codexPencil")
    }

    func testChatGPTPencilIdentifierRemainsStable() {
        XCTAssertEqual(StatusBarIconID.chatGPTPencil.rawValue, "chatGPTPencil")
    }

    func testFallsBackToDefaultForUnknownIdentifier() {
        XCTAssertEqual(
            StatusBarIconPreference.normalized("legacy-icon-that-does-not-exist"),
            StatusBarIconPreference.defaultValue
        )
    }

    func testLoadsDefaultWhenNoPreferenceHasBeenSaved() {
        XCTAssertEqual(
            StatusBarIconPreference.load(from: defaults),
            StatusBarIconPreference.defaultValue
        )
    }

    func testSavesAndLoadsSelectedIconThroughUserDefaults() {
        StatusBarIconPreference.save(.chatGPTPencil, to: defaults)

        XCTAssertEqual(
            defaults.string(forKey: StatusBarIconPreference.key),
            StatusBarIconID.chatGPTPencil.rawValue
        )
        XCTAssertEqual(
            StatusBarIconPreference.load(from: defaults),
            .chatGPTPencil
        )
    }

    func testRepairsUnknownStoredIdentifierToDefault() {
        defaults.set(
            "legacy-icon-that-does-not-exist",
            forKey: StatusBarIconPreference.key
        )

        XCTAssertEqual(
            StatusBarIconPreference.load(from: defaults),
            StatusBarIconPreference.defaultValue
        )
        XCTAssertEqual(
            defaults.string(forKey: StatusBarIconPreference.key),
            StatusBarIconPreference.defaultValue.rawValue
        )
    }
}
