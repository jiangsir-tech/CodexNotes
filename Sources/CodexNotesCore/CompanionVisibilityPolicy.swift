import Foundation

public enum CompanionVisibilityPolicy {
    public static let codexBundleIdentifier = "com.openai.codex"

    public static func shouldShow(
        frontmostBundleIdentifier: String?,
        companionBundleIdentifier: String?,
        isSettingsVisible: Bool = false
    ) -> Bool {
        guard !isSettingsVisible else { return false }
        guard let frontmostBundleIdentifier else { return false }
        return frontmostBundleIdentifier == codexBundleIdentifier
            || frontmostBundleIdentifier == companionBundleIdentifier
    }
}
