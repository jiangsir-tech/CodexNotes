import AppKit
@testable import CodexNotesCore
@testable import CodexNotesProbe
import XCTest

final class NoteThemePaletteTests: XCTestCase {
    private let customThemes = NoteThemeID.allCases.filter {
        $0 != .systemOriginal
    }

    func testCustomThemeTextMaintainsAccessibleContrast() throws {
        for theme in customThemes {
            let palette = theme.palette

            try assertContrast(
                palette.primaryText.nsColor,
                against: palette.editorBackground.nsColor,
                isAtLeast: 7,
                theme: theme,
                role: "primary/editor"
            )
            try assertContrast(
                palette.tertiaryText.nsColor,
                against: palette.editorBackground.nsColor,
                isAtLeast: 4.5,
                theme: theme,
                role: "tertiary/editor"
            )

            for (surfaceName, surface) in [
                ("window", palette.windowBackground),
                ("panel", palette.panelBackground),
                ("selected", palette.selectedBackground),
            ] {
                try assertContrast(
                    palette.secondaryText.nsColor,
                    against: surface.nsColor,
                    isAtLeast: 4.5,
                    theme: theme,
                    role: "secondary/\(surfaceName)"
                )
            }
        }
    }

    func testCustomThemeAccentRemainsVisibleOnPanels() throws {
        for theme in customThemes {
            let palette = theme.palette
            try assertContrast(
                palette.accent.nsColor,
                against: palette.panelBackground.nsColor,
                isAtLeast: 4.5,
                theme: theme,
                role: "accent/panel"
            )
        }
    }

    func testCustomThemeAppearanceMatchesItsIntendedMode() {
        let lightThemes: [NoteThemeID] = [
            .mistPaper,
            .warmPaper,
            .seaSalt,
            .sageMist,
        ]
        let darkThemes: [NoteThemeID] = [
            .midnightIndigo,
            .plumNight,
        ]

        for theme in lightThemes {
            XCTAssertEqual(theme.palette.colorScheme, .light, theme.rawValue)
            XCTAssertEqual(theme.palette.appearanceName, .aqua, theme.rawValue)
        }
        for theme in darkThemes {
            XCTAssertEqual(theme.palette.colorScheme, .dark, theme.rawValue)
            XCTAssertEqual(theme.palette.appearanceName, .darkAqua, theme.rawValue)
        }
    }

    func testObsidianStationeryKeepsLegacyIDAndApprovedPalette() throws {
        let restoreLanguage = selectSimplifiedChinese()
        defer { restoreLanguage() }
        let theme = NoteThemeID.midnightIndigo
        let palette = theme.palette

        XCTAssertEqual(theme.rawValue, "midnightIndigo")
        XCTAssertEqual(theme.displayName, "曜石云笺")
        XCTAssertEqual(theme.summary, "曜石深色，轻盈而专注")
        XCTAssertEqual(NoteThemePreference.normalized("midnightIndigo"), theme)

        try assertColor(palette.windowBackground.nsColor, equals: 0x1A2131)
        try assertColor(palette.panelBackground.nsColor, equals: 0x1C2436)
        try assertColor(palette.editorBackground.nsColor, equals: 0x0E1320)
        try assertColor(palette.selectedBackground.nsColor, equals: 0x151C2A)
        try assertColor(palette.primaryText.nsColor, equals: 0xF2F4F8)
        try assertColor(palette.secondaryText.nsColor, equals: 0xA7AFBF)
        try assertColor(palette.tertiaryText.nsColor, equals: 0x7F8796)
        try assertColor(palette.accent.nsColor, equals: 0x8797FF)
        try assertColor(palette.separator.nsColor, equals: 0x2A3244)
        try assertColor(palette.textSelection.nsColor, equals: 0x35446A)
        try assertColor(palette.success.nsColor, equals: 0x45D483)
        try assertColor(palette.warning.nsColor, equals: 0xF2B866)
        try assertColor(palette.error.nsColor, equals: 0xFF7D88)

        try assertContrast(
            palette.accent.nsColor,
            against: palette.selectedBackground.nsColor,
            isAtLeast: 4.5,
            theme: theme,
            role: "accent/selected"
        )
        try assertContrast(
            palette.primaryText.nsColor,
            against: palette.textSelection.nsColor,
            isAtLeast: 7,
            theme: theme,
            role: "primary/textSelection"
        )
        for (role, color) in [
            ("success", palette.success),
            ("warning", palette.warning),
            ("error", palette.error),
        ] {
            try assertContrast(
                color.nsColor,
                against: palette.windowBackground.nsColor,
                isAtLeast: 4.5,
                theme: theme,
                role: "\(role)/window"
            )
        }
    }

    func testIvoryCottonPaperKeepsLegacyIDAndApprovedPalette() throws {
        let restoreLanguage = selectSimplifiedChinese()
        defer { restoreLanguage() }
        let theme = NoteThemeID.warmPaper
        let palette = theme.palette

        XCTAssertEqual(theme.rawValue, "warmPaper")
        XCTAssertEqual(theme.displayName, "象牙棉纸")
        XCTAssertEqual(theme.summary, "细腻棉纸，明亮而不刺眼")
        XCTAssertEqual(NoteThemePreference.normalized("warmPaper"), theme)
        XCTAssertTrue(theme.usesIndependentScopeCards)
        XCTAssertTrue(theme.usesCottonPaperTexture)
        XCTAssertFalse(NoteThemeID.systemOriginal.usesCottonPaperTexture)
        XCTAssertTrue(NoteThemeID.midnightIndigo.usesIndependentScopeCards)
        XCTAssertTrue(NoteThemeID.mistPaper.usesIndependentScopeCards)

        try assertColor(palette.windowBackground.nsColor, equals: 0xF5EDE1)
        try assertColor(palette.panelBackground.nsColor, equals: 0xF1E7D9)
        try assertColor(palette.editorBackground.nsColor, equals: 0xFCF7EF)
        try assertColor(palette.selectedBackground.nsColor, equals: 0xF9EAD6)
        try assertColor(palette.primaryText.nsColor, equals: 0x2B2926)
        try assertColor(palette.secondaryText.nsColor, equals: 0x625C55)
        try assertColor(palette.tertiaryText.nsColor, equals: 0x70695F)
        try assertColor(palette.accent.nsColor, equals: 0xA44717)
        try assertColor(palette.separator.nsColor, equals: 0xD7CCBE)
        try assertColor(palette.textSelection.nsColor, equals: 0xE9C7AA)
        try assertColor(palette.success.nsColor, equals: 0x176F3D)
        try assertColor(palette.warning.nsColor, equals: 0x915000)
        try assertColor(palette.error.nsColor, equals: 0xB42318)

        try assertContrast(
            palette.accent.nsColor,
            against: palette.selectedBackground.nsColor,
            isAtLeast: 4.5,
            theme: theme,
            role: "accent/selected"
        )
        try assertContrast(
            palette.primaryText.nsColor,
            against: palette.textSelection.nsColor,
            isAtLeast: 7,
            theme: theme,
            role: "primary/textSelection"
        )
    }

    func testSilverTracingPaperKeepsLegacyIDAndApprovedPalette() throws {
        let restoreLanguage = selectSimplifiedChinese()
        defer { restoreLanguage() }
        let theme = NoteThemeID.mistPaper
        let palette = theme.palette

        XCTAssertEqual(theme.rawValue, "mistPaper")
        XCTAssertEqual(theme.displayName, "银雾描图纸")
        XCTAssertEqual(theme.summary, "冷灰描图纸，清透而专注")
        XCTAssertEqual(NoteThemePreference.normalized("mistPaper"), theme)
        XCTAssertTrue(theme.usesIndependentScopeCards)
        XCTAssertTrue(theme.usesSilverTracingPaperTexture)
        XCTAssertFalse(NoteThemeID.systemOriginal.usesSilverTracingPaperTexture)
        XCTAssertFalse(NoteThemeID.warmPaper.usesSilverTracingPaperTexture)
        XCTAssertFalse(NoteThemeID.midnightIndigo.usesSilverTracingPaperTexture)
        XCTAssertTrue(NoteThemeID.warmPaper.usesCottonPaperTexture)
        XCTAssertFalse(theme.usesCottonPaperTexture)

        try assertColor(palette.windowBackground.nsColor, equals: 0xE9EDF0)
        try assertColor(palette.panelBackground.nsColor, equals: 0xDDE3E7)
        try assertColor(palette.editorBackground.nsColor, equals: 0xF7F9FA)
        try assertColor(palette.selectedBackground.nsColor, equals: 0xD9E4EE)
        try assertColor(palette.primaryText.nsColor, equals: 0x20262B)
        try assertColor(palette.secondaryText.nsColor, equals: 0x56616A)
        try assertColor(palette.tertiaryText.nsColor, equals: 0x66727B)
        try assertColor(palette.accent.nsColor, equals: 0x315F82)
        try assertColor(palette.separator.nsColor, equals: 0xC5CED4)
        try assertColor(palette.textSelection.nsColor, equals: 0xC3D8E6)
        try assertColor(palette.success.nsColor, equals: 0x176F46)
        try assertColor(palette.warning.nsColor, equals: 0x895000)
        try assertColor(palette.error.nsColor, equals: 0xAB2925)

        try assertContrast(
            palette.accent.nsColor,
            against: palette.selectedBackground.nsColor,
            isAtLeast: 4.5,
            theme: theme,
            role: "accent/selected"
        )
        try assertContrast(
            palette.primaryText.nsColor,
            against: palette.textSelection.nsColor,
            isAtLeast: 7,
            theme: theme,
            role: "primary/textSelection"
        )
        for (role, color) in [
            ("success", palette.success),
            ("warning", palette.warning),
            ("error", palette.error),
        ] {
            try assertContrast(
                color.nsColor,
                against: palette.windowBackground.nsColor,
                isAtLeast: 4.5,
                theme: theme,
                role: "\(role)/window"
            )
        }
    }

    func testNorthSeaCyanotypeKeepsLegacyIDAndApprovedPalette() throws {
        let restoreLanguage = selectSimplifiedChinese()
        defer { restoreLanguage() }
        let theme = NoteThemeID.seaSalt
        let palette = theme.palette

        XCTAssertEqual(theme.rawValue, "seaSalt")
        XCTAssertEqual(theme.displayName, "北海蓝晒")
        XCTAssertEqual(theme.summary, "淡蓝纸感，冷静而专业")
        XCTAssertEqual(NoteThemePreference.normalized("seaSalt"), theme)
        XCTAssertTrue(theme.usesIndependentScopeCards)
        XCTAssertTrue(theme.usesNorthSeaCyanotypeTexture)
        XCTAssertFalse(theme.usesCottonPaperTexture)
        XCTAssertFalse(theme.usesSilverTracingPaperTexture)

        for otherTheme in NoteThemeID.allCases where otherTheme != theme {
            XCTAssertFalse(
                otherTheme.usesNorthSeaCyanotypeTexture,
                otherTheme.rawValue
            )
        }

        try assertColor(palette.windowBackground.nsColor, equals: 0xE1EBF4)
        try assertColor(palette.panelBackground.nsColor, equals: 0xCFDDEA)
        try assertColor(palette.editorBackground.nsColor, equals: 0xF4F8FC)
        try assertColor(palette.selectedBackground.nsColor, equals: 0xBED5E9)
        try assertColor(palette.primaryText.nsColor, equals: 0x1C2E3D)
        try assertColor(palette.secondaryText.nsColor, equals: 0x435B6E)
        try assertColor(palette.tertiaryText.nsColor, equals: 0x5A6F80)
        try assertColor(palette.accent.nsColor, equals: 0x275C87)
        try assertColor(palette.separator.nsColor, equals: 0xB6C8D7)
        try assertColor(palette.textSelection.nsColor, equals: 0xB7D0E7)
        try assertColor(palette.success.nsColor, equals: 0x1B6C4B)
        try assertColor(palette.warning.nsColor, equals: 0x925000)
        try assertColor(palette.error.nsColor, equals: 0xB42318)

        try assertContrast(
            palette.accent.nsColor,
            against: palette.selectedBackground.nsColor,
            isAtLeast: 4.5,
            theme: theme,
            role: "accent/selected"
        )
        try assertContrast(
            palette.primaryText.nsColor,
            against: palette.textSelection.nsColor,
            isAtLeast: 7,
            theme: theme,
            role: "primary/textSelection"
        )
        for (role, color) in [
            ("success", palette.success),
            ("warning", palette.warning),
            ("error", palette.error),
        ] {
            try assertContrast(
                color.nsColor,
                against: palette.windowBackground.nsColor,
                isAtLeast: 4.5,
                theme: theme,
                role: "\(role)/window"
            )
        }
    }

    func testMistEucalyptusCottonPaperKeepsLegacyIDAndApprovedPalette() throws {
        let restoreLanguage = selectSimplifiedChinese()
        defer { restoreLanguage() }
        let theme = NoteThemeID.sageMist
        let palette = theme.palette

        XCTAssertEqual(theme.rawValue, "sageMist")
        XCTAssertEqual(theme.displayName, "雾桉棉纸")
        XCTAssertEqual(theme.summary, "雾桉浅绿，清润而安静")
        XCTAssertEqual(NoteThemePreference.normalized("sageMist"), theme)
        XCTAssertTrue(theme.usesIndependentScopeCards)
        XCTAssertTrue(theme.usesEucalyptusCottonPaperTexture)
        XCTAssertFalse(theme.usesCottonPaperTexture)
        XCTAssertFalse(theme.usesSilverTracingPaperTexture)
        XCTAssertFalse(theme.usesNorthSeaCyanotypeTexture)

        for otherTheme in NoteThemeID.allCases where otherTheme != theme {
            XCTAssertFalse(
                otherTheme.usesEucalyptusCottonPaperTexture,
                otherTheme.rawValue
            )
        }

        try assertColor(palette.windowBackground.nsColor, equals: 0xE5EBE1)
        try assertColor(palette.panelBackground.nsColor, equals: 0xD6DED2)
        try assertColor(palette.editorBackground.nsColor, equals: 0xF3F5EF)
        try assertColor(palette.selectedBackground.nsColor, equals: 0xDCE8DD)
        try assertColor(palette.primaryText.nsColor, equals: 0x1E452C)
        try assertColor(palette.secondaryText.nsColor, equals: 0x45604C)
        try assertColor(palette.tertiaryText.nsColor, equals: 0x536B59)
        try assertColor(palette.accent.nsColor, equals: 0x155A32)
        try assertColor(palette.separator.nsColor, equals: 0xC3CFC2)
        try assertColor(palette.textSelection.nsColor, equals: 0xBFD8C6)
        try assertColor(palette.success.nsColor, equals: 0x0F6C3B)
        try assertColor(palette.warning.nsColor, equals: 0x925000)
        try assertColor(palette.error.nsColor, equals: 0xB42318)

        try assertContrast(
            palette.accent.nsColor,
            against: palette.selectedBackground.nsColor,
            isAtLeast: 4.5,
            theme: theme,
            role: "accent/selected"
        )
        try assertContrast(
            palette.primaryText.nsColor,
            against: palette.textSelection.nsColor,
            isAtLeast: 7,
            theme: theme,
            role: "primary/textSelection"
        )
        for (role, color) in [
            ("success", palette.success),
            ("warning", palette.warning),
            ("error", palette.error),
        ] {
            try assertContrast(
                color.nsColor,
                against: palette.windowBackground.nsColor,
                isAtLeast: 4.5,
                theme: theme,
                role: "\(role)/window"
            )
        }
    }

    func testBordeauxCottonPaperKeepsLegacyIDAndApprovedPalette() throws {
        let restoreLanguage = selectSimplifiedChinese()
        defer { restoreLanguage() }
        let theme = NoteThemeID.plumNight
        let palette = theme.palette

        XCTAssertEqual(theme.rawValue, "plumNight")
        XCTAssertEqual(theme.displayName, "波尔多棉纸")
        XCTAssertEqual(theme.summary, "深酒红棉纸，温润而沉静")
        XCTAssertEqual(NoteThemePreference.normalized("plumNight"), theme)
        XCTAssertEqual(palette.colorScheme, .dark)
        XCTAssertEqual(palette.appearanceName, .darkAqua)
        XCTAssertTrue(theme.usesIndependentScopeCards)
        XCTAssertTrue(theme.usesBordeauxCottonPaperTexture)
        XCTAssertFalse(theme.usesCottonPaperTexture)
        XCTAssertFalse(theme.usesSilverTracingPaperTexture)
        XCTAssertFalse(theme.usesNorthSeaCyanotypeTexture)
        XCTAssertFalse(theme.usesEucalyptusCottonPaperTexture)

        XCTAssertEqual(
            NoteThemeID.allCases.filter { $0.usesIndependentScopeCards },
            [.mistPaper, .warmPaper, .seaSalt, .sageMist, .midnightIndigo, .plumNight]
        )
        for candidate in NoteThemeID.allCases {
            let materialFlags = [
                candidate.usesCottonPaperTexture,
                candidate.usesSilverTracingPaperTexture,
                candidate.usesNorthSeaCyanotypeTexture,
                candidate.usesEucalyptusCottonPaperTexture,
                candidate.usesBordeauxCottonPaperTexture,
            ]
            XCTAssertLessThanOrEqual(
                materialFlags.filter { $0 }.count,
                1,
                candidate.rawValue
            )
            if candidate != theme {
                XCTAssertFalse(
                    candidate.usesBordeauxCottonPaperTexture,
                    candidate.rawValue
                )
            }
        }

        try assertColor(palette.windowBackground.nsColor, equals: 0x281B20)
        try assertColor(palette.panelBackground.nsColor, equals: 0x33242A)
        try assertColor(palette.editorBackground.nsColor, equals: 0x1B1417)
        try assertColor(palette.selectedBackground.nsColor, equals: 0x4D3039)
        try assertColor(palette.primaryText.nsColor, equals: 0xEAD9DE)
        try assertColor(palette.secondaryText.nsColor, equals: 0xC3A4AD)
        try assertColor(palette.tertiaryText.nsColor, equals: 0xA98590)
        try assertColor(palette.accent.nsColor, equals: 0xE88C92)
        try assertColor(palette.separator.nsColor, equals: 0x53363E)
        try assertColor(palette.textSelection.nsColor, equals: 0x613642)
        try assertColor(palette.success.nsColor, equals: 0x55B875)
        try assertColor(palette.warning.nsColor, equals: 0xE4B274)
        try assertColor(palette.error.nsColor, equals: 0xF58088)

        try assertContrast(
            palette.accent.nsColor,
            against: palette.selectedBackground.nsColor,
            isAtLeast: 4.5,
            theme: theme,
            role: "accent/selected"
        )
        try assertContrast(
            palette.primaryText.nsColor,
            against: palette.textSelection.nsColor,
            isAtLeast: 7,
            theme: theme,
            role: "primary/textSelection"
        )
        for (role, color) in [
            ("success", palette.success),
            ("warning", palette.warning),
            ("error", palette.error),
        ] {
            try assertContrast(
                color.nsColor,
                against: palette.windowBackground.nsColor,
                isAtLeast: 4.5,
                theme: theme,
                role: "\(role)/window"
            )
        }
        for (role, color) in [
            ("success", palette.success),
            ("error", palette.error),
        ] {
            try assertContrast(
                color.nsColor,
                against: palette.selectedBackground.nsColor,
                isAtLeast: 4.5,
                theme: theme,
                role: "\(role)/selected"
            )
        }
    }

    func testSystemOriginalRemainsFullySystemDefined() {
        let palette = NoteThemeID.systemOriginal.palette

        XCTAssertNil(palette.colorScheme)
        XCTAssertNil(palette.appearanceName)
        XCTAssertTrue(
            palette.windowBackground.nsColor.isEqual(NSColor.windowBackgroundColor)
        )
        XCTAssertTrue(
            palette.panelBackground.nsColor.isEqual(NSColor.quaternaryLabelColor)
        )
        XCTAssertTrue(
            palette.editorBackground.nsColor.isEqual(NSColor.textBackgroundColor)
        )
        XCTAssertTrue(
            palette.selectedBackground.nsColor.isEqual(NSColor.controlBackgroundColor)
        )
        XCTAssertTrue(palette.primaryText.nsColor.isEqual(NSColor.labelColor))
        XCTAssertTrue(
            palette.secondaryText.nsColor.isEqual(NSColor.secondaryLabelColor)
        )
        XCTAssertTrue(
            palette.tertiaryText.nsColor.isEqual(NSColor.tertiaryLabelColor)
        )
        XCTAssertTrue(palette.accent.nsColor.isEqual(NSColor.controlAccentColor))
        XCTAssertTrue(palette.separator.nsColor.isEqual(NSColor.separatorColor))
        XCTAssertTrue(
            palette.textSelection.nsColor.isEqual(NSColor.selectedTextBackgroundColor)
        )
        XCTAssertTrue(palette.success.nsColor.isEqual(NSColor.systemGreen))
        XCTAssertTrue(palette.warning.nsColor.isEqual(NSColor.systemOrange))
        XCTAssertTrue(palette.error.nsColor.isEqual(NSColor.systemRed))
    }

    private func selectSimplifiedChinese() -> () -> Void {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: AppLanguagePreference.key)
        AppLanguagePreference.save(.simplifiedChinese, to: defaults)
        return {
            if let previousValue {
                defaults.set(previousValue, forKey: AppLanguagePreference.key)
            } else {
                defaults.removeObject(forKey: AppLanguagePreference.key)
            }
        }
    }

    private func assertContrast(
        _ foreground: NSColor,
        against background: NSColor,
        isAtLeast minimum: Double,
        theme: NoteThemeID,
        role: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let ratio = try contrastRatio(foreground, background)
        XCTAssertGreaterThanOrEqual(
            ratio,
            minimum,
            "\(theme.rawValue) \(role) contrast was \(ratio)",
            file: file,
            line: line
        )
    }

    private func assertColor(
        _ color: NSColor,
        equals hex: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let srgb = try XCTUnwrap(color.usingColorSpace(.sRGB), file: file, line: line)
        let expectedRed = CGFloat((hex >> 16) & 0xFF) / 255
        let expectedGreen = CGFloat((hex >> 8) & 0xFF) / 255
        let expectedBlue = CGFloat(hex & 0xFF) / 255

        XCTAssertEqual(srgb.redComponent, expectedRed, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(
            srgb.greenComponent,
            expectedGreen,
            accuracy: 0.0001,
            file: file,
            line: line
        )
        XCTAssertEqual(srgb.blueComponent, expectedBlue, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(srgb.alphaComponent, 1, accuracy: 0.0001, file: file, line: line)
    }

    private func contrastRatio(_ first: NSColor, _ second: NSColor) throws -> Double {
        let firstLuminance = try relativeLuminance(first)
        let secondLuminance = try relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) throws -> Double {
        let srgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        let components = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
            .map(Double.init)
            .map { component in
                component <= 0.04045
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
        return 0.2126 * components[0]
            + 0.7152 * components[1]
            + 0.0722 * components[2]
    }
}
