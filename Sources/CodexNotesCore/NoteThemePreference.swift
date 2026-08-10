import Foundation

public enum NoteThemeID: String, CaseIterable, Codable, Sendable {
    case systemOriginal
    case mistPaper
    case warmPaper
    case seaSalt
    case sageMist
    case midnightIndigo
    case plumNight
}

public enum NoteThemePreference {
    public static let key = "noteColorTheme"
    public static let defaultValue: NoteThemeID = .mistPaper

    public static func normalized(_ rawValue: String) -> NoteThemeID {
        NoteThemeID(rawValue: rawValue) ?? defaultValue
    }
}
