import Foundation
import XCTest
@testable import CodexNotesCore

final class RightPanelAvoidancePreferenceTests: XCTestCase {
    func testFreshInstallDefaultsOffAndPersistsDecision() {
        withDefaults { defaults, suiteName in
            XCTAssertNil(defaults.object(
                forKey: RightPanelAvoidancePreference.key
            ))
            XCTAssertFalse(RightPanelAvoidancePreference.migrateIfNeeded(
                defaults: defaults,
                persistentDomainName: suiteName
            ))
            XCTAssertEqual(
                defaults.object(forKey: RightPanelAvoidancePreference.key) as? Bool,
                false
            )
            XCTAssertFalse(RightPanelAvoidancePreference.load(from: defaults))
        }
    }

    func testExistingInstallWithoutPreferenceDefaultsOff() {
        withDefaults { defaults, suiteName in
            defaults.set(20, forKey: "editorFontSize")

            XCTAssertFalse(RightPanelAvoidancePreference.migrateIfNeeded(
                defaults: defaults,
                persistentDomainName: suiteName
            ))
            XCTAssertFalse(defaults.bool(
                forKey: RightPanelAvoidancePreference.key
            ))
        }
    }

    func testExplicitPreferenceWinsAndRoundTripsBothValues() {
        withDefaults { defaults, suiteName in
            defaults.set(false, forKey: RightPanelAvoidancePreference.key)
            defaults.set(20, forKey: "editorFontSize")
            XCTAssertFalse(RightPanelAvoidancePreference.migrateIfNeeded(
                defaults: defaults,
                persistentDomainName: suiteName
            ))
            XCTAssertFalse(RightPanelAvoidancePreference.load(from: defaults))

            defaults.set(true, forKey: RightPanelAvoidancePreference.key)
            XCTAssertTrue(RightPanelAvoidancePreference.migrateIfNeeded(
                defaults: defaults,
                persistentDomainName: suiteName
            ))
            XCTAssertTrue(RightPanelAvoidancePreference.load(from: defaults))
        }
    }

    func testEmptyPersistentDomainStillCountsAsFreshInstall() {
        withDefaults { defaults, suiteName in
            defaults.set(true, forKey: "temporary")
            defaults.removeObject(forKey: "temporary")

            XCTAssertEqual(
                defaults.persistentDomain(forName: suiteName)?.isEmpty,
                true
            )
            XCTAssertFalse(RightPanelAvoidancePreference.migrateIfNeeded(
                defaults: defaults,
                persistentDomainName: suiteName
            ))
        }
    }

    private func withDefaults(_ body: (UserDefaults, String) -> Void) {
        let suiteName = "CodexNotesTests.RightPanelAvoidance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults, suiteName)
    }
}
