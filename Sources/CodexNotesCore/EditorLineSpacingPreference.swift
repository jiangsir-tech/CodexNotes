import Foundation

public enum EditorLineSpacingPreference {
    public static let key = "editorLineSpacing"
    public static let minimum = 0.0
    public static let maximum = 12.0
    public static let defaultValue = 4.0

    public static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(max(value.rounded(), minimum), maximum)
    }
}
