import Foundation

public enum StatusBarIconID: String, CaseIterable, Codable, Sendable {
    case codexPencil
    case chatGPTPencil
}

public enum StatusBarIconPreference {
    public static let key = "statusBarIcon"
    public static let defaultValue: StatusBarIconID = .codexPencil

    public static func normalized(_ rawValue: String) -> StatusBarIconID {
        StatusBarIconID(rawValue: rawValue) ?? defaultValue
    }

    public static func load(from defaults: UserDefaults = .standard) -> StatusBarIconID {
        guard let rawValue = defaults.string(forKey: key),
              let icon = StatusBarIconID(rawValue: rawValue) else {
            if defaults.object(forKey: key) != nil {
                defaults.set(defaultValue.rawValue, forKey: key)
            }
            return defaultValue
        }

        return icon
    }

    public static func save(
        _ icon: StatusBarIconID,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(icon.rawValue, forKey: key)
    }
}
