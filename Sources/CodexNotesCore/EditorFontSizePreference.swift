import Foundation

public enum EditorFontSizePreference {
    public static let key = "editorFontSize"
    public static let minimum = 12.0
    public static let maximum = 24.0
    public static let defaultValue = 15.0

    public static func normalized(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(max(value.rounded(), minimum), maximum)
    }
}
