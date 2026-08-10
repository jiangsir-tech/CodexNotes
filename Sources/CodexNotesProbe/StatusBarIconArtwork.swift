import AppKit
import CodexNotesCore

extension StatusBarIconID {
    var displayName: String {
        switch self {
        case .codexPencil:
            L10n.text(.settingsStatusIconCodexPencilName)
        case .chatGPTPencil:
            L10n.text(.settingsStatusIconChatGPTPencilName)
        }
    }

    var summary: String {
        switch self {
        case .codexPencil:
            L10n.text(.settingsStatusIconCodexPencilSummary)
        case .chatGPTPencil:
            L10n.text(.settingsStatusIconChatGPTPencilSummary)
        }
    }

    fileprivate var resourceName: String {
        switch self {
        case .codexPencil:
            "StatusIconCodexPencilTemplate"
        case .chatGPTPencil:
            "StatusIconChatGPTPencilTemplate"
        }
    }
}

enum StatusBarIconArtwork {
    static let pointSize = NSSize(width: 20, height: 20)

    static func image(
        for icon: StatusBarIconID,
        bundle: Bundle = .module
    ) -> NSImage? {
        guard let url = bundle.url(
            forResource: icon.resourceName,
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            return nil
        }

        image.size = pointSize
        image.isTemplate = true
        image.accessibilityDescription = L10n.text(
            .statusIconAccessibilityDescription,
            replacements: ["iconName": icon.displayName]
        )
        return image
    }

    static func fallbackImage() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "note.text",
            accessibilityDescription: "CodexNotes"
        )
        image?.isTemplate = true
        return image
    }
}
