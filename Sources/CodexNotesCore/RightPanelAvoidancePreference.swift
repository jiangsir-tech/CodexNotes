import Foundation

/// Shared persistence contract for the optional Codex right-panel avoidance.
///
/// Installations that have already saved an explicit choice retain it. Every
/// installation without this key starts with the optional behavior disabled,
/// including upgrades from public versions that predate automatic avoidance.
/// `migrateIfNeeded` persists that decision before any `@AppStorage` reader is
/// created, so every window observes one stable value for the entire launch.
public enum RightPanelAvoidancePreference {
    public static let key = "rightPanelAvoidanceEnabled"
    public static let defaultValue = false

    @discardableResult
    public static func migrateIfNeeded(
        defaults: UserDefaults = .standard,
        persistentDomainName: String
    ) -> Bool {
        let persistentDomain = defaults.persistentDomain(
            forName: persistentDomainName
        )

        if let storedValue = persistentDomain?[key] as? NSNumber {
            return storedValue.boolValue
        }

        defaults.set(defaultValue, forKey: key)
        return defaultValue
    }

    public static func load(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}
