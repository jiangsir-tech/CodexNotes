import AppKit
import CodexNotesCore
import SwiftUI

struct ThemeColor: Equatable {
    let nsColor: NSColor

    init(nsColor: NSColor) {
        self.nsColor = nsColor
    }

    init(_ hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        nsColor = NSColor(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}

enum NoteThemeAppearance {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

struct NoteThemePalette {
    let appearance: NoteThemeAppearance
    let windowBackground: ThemeColor
    let panelBackground: ThemeColor
    let editorBackground: ThemeColor
    let selectedBackground: ThemeColor
    let primaryText: ThemeColor
    let secondaryText: ThemeColor
    let tertiaryText: ThemeColor
    let accent: ThemeColor
    let separator: ThemeColor
    let textSelection: ThemeColor
    let success: ThemeColor
    let warning: ThemeColor
    let error: ThemeColor

    var colorScheme: ColorScheme? {
        appearance.colorScheme
    }

    var appearanceName: NSAppearance.Name? {
        appearance.appearanceName
    }

    var selectionText: ThemeColor {
        switch appearance {
        case .system:
            ThemeColor(nsColor: .selectedTextColor)
        case .light, .dark:
            primaryText
        }
    }
}

extension NoteThemeID {
    var displayName: String {
        switch self {
        case .systemOriginal: L10n.text(.settingsThemeSystemOriginalName)
        case .mistPaper: L10n.text(.settingsThemeMistPaperName)
        case .warmPaper: L10n.text(.settingsThemeWarmPaperName)
        case .seaSalt: L10n.text(.settingsThemeSeaSaltName)
        case .sageMist: L10n.text(.settingsThemeSageMistName)
        case .midnightIndigo: L10n.text(.settingsThemeMidnightIndigoName)
        case .plumNight: L10n.text(.settingsThemePlumNightName)
        }
    }

    var summary: String {
        switch self {
        case .systemOriginal: L10n.text(.settingsThemeSystemOriginalSummary)
        case .mistPaper: L10n.text(.settingsThemeMistPaperSummary)
        case .warmPaper: L10n.text(.settingsThemeWarmPaperSummary)
        case .seaSalt: L10n.text(.settingsThemeSeaSaltSummary)
        case .sageMist: L10n.text(.settingsThemeSageMistSummary)
        case .midnightIndigo: L10n.text(.settingsThemeMidnightIndigoSummary)
        case .plumNight: L10n.text(.settingsThemePlumNightSummary)
        }
    }

    var palette: NoteThemePalette {
        switch self {
        case .systemOriginal:
            NoteThemePalette(
                appearance: .system,
                windowBackground: ThemeColor(nsColor: .windowBackgroundColor),
                panelBackground: ThemeColor(nsColor: .quaternaryLabelColor),
                editorBackground: ThemeColor(nsColor: .textBackgroundColor),
                selectedBackground: ThemeColor(nsColor: .controlBackgroundColor),
                primaryText: ThemeColor(nsColor: .labelColor),
                secondaryText: ThemeColor(nsColor: .secondaryLabelColor),
                tertiaryText: ThemeColor(nsColor: .tertiaryLabelColor),
                accent: ThemeColor(nsColor: .controlAccentColor),
                separator: ThemeColor(nsColor: .separatorColor),
                textSelection: ThemeColor(nsColor: .selectedTextBackgroundColor),
                success: ThemeColor(nsColor: .systemGreen),
                warning: ThemeColor(nsColor: .systemOrange),
                error: ThemeColor(nsColor: .systemRed)
            )
        case .mistPaper:
            NoteThemePalette(
                appearance: .light,
                windowBackground: ThemeColor(0xE9EDF0),
                panelBackground: ThemeColor(0xDDE3E7),
                editorBackground: ThemeColor(0xF7F9FA),
                selectedBackground: ThemeColor(0xD9E4EE),
                primaryText: ThemeColor(0x20262B),
                secondaryText: ThemeColor(0x56616A),
                tertiaryText: ThemeColor(0x66727B),
                accent: ThemeColor(0x315F82),
                separator: ThemeColor(0xC5CED4),
                textSelection: ThemeColor(0xC3D8E6),
                success: ThemeColor(0x176F46),
                warning: ThemeColor(0x895000),
                error: ThemeColor(0xAB2925)
            )
        case .warmPaper:
            NoteThemePalette(
                appearance: .light,
                windowBackground: ThemeColor(0xF5EDE1),
                panelBackground: ThemeColor(0xF1E7D9),
                editorBackground: ThemeColor(0xFCF7EF),
                selectedBackground: ThemeColor(0xF9EAD6),
                primaryText: ThemeColor(0x2B2926),
                secondaryText: ThemeColor(0x625C55),
                tertiaryText: ThemeColor(0x70695F),
                accent: ThemeColor(0xA44717),
                separator: ThemeColor(0xD7CCBE),
                textSelection: ThemeColor(0xE9C7AA),
                success: ThemeColor(0x176F3D),
                warning: ThemeColor(0x915000),
                error: ThemeColor(0xB42318)
            )
        case .seaSalt:
            NoteThemePalette(
                appearance: .light,
                windowBackground: ThemeColor(0xE1EBF4),
                panelBackground: ThemeColor(0xCFDDEA),
                editorBackground: ThemeColor(0xF4F8FC),
                selectedBackground: ThemeColor(0xBED5E9),
                primaryText: ThemeColor(0x1C2E3D),
                secondaryText: ThemeColor(0x435B6E),
                tertiaryText: ThemeColor(0x5A6F80),
                accent: ThemeColor(0x275C87),
                separator: ThemeColor(0xB6C8D7),
                textSelection: ThemeColor(0xB7D0E7),
                success: ThemeColor(0x1B6C4B),
                warning: ThemeColor(0x925000),
                error: ThemeColor(0xB42318)
            )
        case .sageMist:
            NoteThemePalette(
                appearance: .light,
                windowBackground: ThemeColor(0xE5EBE1),
                panelBackground: ThemeColor(0xD6DED2),
                editorBackground: ThemeColor(0xF3F5EF),
                selectedBackground: ThemeColor(0xDCE8DD),
                primaryText: ThemeColor(0x1E452C),
                secondaryText: ThemeColor(0x45604C),
                tertiaryText: ThemeColor(0x536B59),
                accent: ThemeColor(0x155A32),
                separator: ThemeColor(0xC3CFC2),
                textSelection: ThemeColor(0xBFD8C6),
                success: ThemeColor(0x0F6C3B),
                warning: ThemeColor(0x925000),
                error: ThemeColor(0xB42318)
            )
        case .midnightIndigo:
            NoteThemePalette(
                appearance: .dark,
                windowBackground: ThemeColor(0x1A2131),
                panelBackground: ThemeColor(0x1C2436),
                editorBackground: ThemeColor(0x0E1320),
                selectedBackground: ThemeColor(0x151C2A),
                primaryText: ThemeColor(0xF2F4F8),
                secondaryText: ThemeColor(0xA7AFBF),
                tertiaryText: ThemeColor(0x7F8796),
                accent: ThemeColor(0x8797FF),
                separator: ThemeColor(0x2A3244),
                textSelection: ThemeColor(0x35446A),
                success: ThemeColor(0x45D483),
                warning: ThemeColor(0xF2B866),
                error: ThemeColor(0xFF7D88)
            )
        case .plumNight:
            NoteThemePalette(
                appearance: .dark,
                windowBackground: ThemeColor(0x281B20),
                panelBackground: ThemeColor(0x33242A),
                editorBackground: ThemeColor(0x1B1417),
                selectedBackground: ThemeColor(0x4D3039),
                primaryText: ThemeColor(0xEAD9DE),
                secondaryText: ThemeColor(0xC3A4AD),
                tertiaryText: ThemeColor(0xA98590),
                accent: ThemeColor(0xE88C92),
                separator: ThemeColor(0x53363E),
                textSelection: ThemeColor(0x613642),
                success: ThemeColor(0x55B875),
                warning: ThemeColor(0xE4B274),
                error: ThemeColor(0xF58088)
            )
        }
    }

    var usesIndependentScopeCards: Bool {
        self == .mistPaper
            || self == .warmPaper
            || self == .seaSalt
            || self == .sageMist
            || self == .midnightIndigo
            || self == .plumNight
    }

    var usesCottonPaperTexture: Bool {
        self == .warmPaper
    }

    var usesSilverTracingPaperTexture: Bool {
        self == .mistPaper
    }

    var usesNorthSeaCyanotypeTexture: Bool {
        self == .seaSalt
    }

    var usesEucalyptusCottonPaperTexture: Bool {
        self == .sageMist
    }

    var usesBordeauxCottonPaperTexture: Bool {
        self == .plumNight
    }
}
