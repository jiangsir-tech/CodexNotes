import AppKit
import CodexNotesCore

enum MainWindowChromePolicy {
    static let allowsZoom = false

    @MainActor
    static func apply(
        to window: NSWindow,
        isCollapsed: Bool = false,
        localization: AppLocalization = AppLocalization(
            preference: AppLanguagePreference.load()
        )
    ) {
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.isEnabled = !isCollapsed
            closeButton.isHidden = isCollapsed
            // AppKit's native tooltip intentionally waits several seconds.
            // The hover controller supplies a fast, local hint instead.
            closeButton.toolTip = nil
            closeButton.setAccessibilityLabel(
                localization.text(.mainWindowCloseAccessibilityLabel)
            )
            closeButton.setAccessibilityHelp(
                localization.text(.mainWindowCloseAccessibilityHelp)
            )
        }
        if let miniaturizeButton = window.standardWindowButton(.miniaturizeButton) {
            miniaturizeButton.isEnabled = false
            miniaturizeButton.isHidden = true
        }
        if let zoomButton = window.standardWindowButton(.zoomButton) {
            zoomButton.isEnabled = false
            zoomButton.isHidden = true
        }
    }
}
