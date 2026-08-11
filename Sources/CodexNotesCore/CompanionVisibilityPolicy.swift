import Foundation

public enum CompanionVisibilityPolicy {
    public static let codexBundleIdentifier = "com.openai.codex"

    public static func shouldShow(
        frontmostBundleIdentifier: String?,
        companionBundleIdentifier: String?,
        isCodexAvailable: Bool
    ) -> Bool {
        guard isCodexAvailable else { return false }
        guard let frontmostBundleIdentifier else { return false }
        return frontmostBundleIdentifier == codexBundleIdentifier
            || frontmostBundleIdentifier == companionBundleIdentifier
    }
}
