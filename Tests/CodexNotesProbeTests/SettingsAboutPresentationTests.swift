import AppKit
import CryptoKit
import XCTest
@testable import CodexNotesProbe

@MainActor
final class SettingsAboutPresentationTests: XCTestCase {
    func testPublicLinksUseTheConfirmedDestinations() {
        XCTAssertEqual(
            SettingsAboutPresentation.repositoryURL.absoluteString,
            "https://github.com/jiangsir-tech/CodexNotes"
        )
        XCTAssertEqual(
            SettingsAboutPresentation.xProfileURL.absoluteString,
            "https://x.com/YongJiang_Li_"
        )
        XCTAssertEqual(
            SettingsAboutPresentation.feedbackEmailAddress,
            "li-yongjiang@foxmail.com"
        )
        XCTAssertEqual(
            SettingsAboutPresentation.feedbackEmailURL.absoluteString,
            "mailto:li-yongjiang@foxmail.com"
        )
        XCTAssertTrue(
            SettingsAboutPresentation.isAllowedProjectURL(
                SettingsAboutPresentation.repositoryURL
            )
        )
        XCTAssertTrue(
            SettingsAboutPresentation.isAllowedXProfileURL(
                SettingsAboutPresentation.xProfileURL
            )
        )
        XCTAssertTrue(
            SettingsAboutPresentation.isAllowedFeedbackEmailURL(
                SettingsAboutPresentation.feedbackEmailURL
            )
        )
    }

    func testVisibleVersionOmitsTheInternalBuildNumber() {
        let version = AppBundleVersion(version: "1.4.68", build: "88")

        XCTAssertEqual(SettingsAboutPresentation.visibleVersion(version), "1.4.68")
        XCTAssertFalse(SettingsAboutPresentation.visibleVersion(version).contains("88"))
        XCTAssertEqual(version.build, "88")
    }

    func testFeedbackEmailCopiesTheExactPublicAddress() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("SettingsAboutPresentationTests.\(UUID().uuidString)")
        )
        defer { pasteboard.releaseGlobally() }

        XCTAssertTrue(SettingsAboutPresentation.copyFeedbackEmail(to: pasteboard))
        XCTAssertEqual(
            pasteboard.string(forType: .string),
            SettingsAboutPresentation.feedbackEmailAddress
        )
        XCTAssertEqual(
            SettingsAboutPresentation.copyConfirmationDurationNanoseconds,
            1_500_000_000
        )
    }

    func testAboutSourceUsesTheSharedCoordinatorAndAccessibleAutomaticToggle() throws {
        let source = try repositorySource(
            at: "Sources/CodexNotesProbe/AboutCodexNotesView.swift"
        )

        XCTAssertTrue(source.contains(
            "@ObservedObject private var updateCoordinator: UpdateCheckCoordinator"
        ))
        XCTAssertTrue(source.contains("updateCoordinator.manualCheck()"))
        XCTAssertTrue(source.contains("updateCoordinator.setAutomaticChecksEnabled($0)"))
        XCTAssertTrue(source.contains(".settingsAboutAutomaticCheck"))
        XCTAssertTrue(source.contains(".settingsAboutAutomaticCheckDescription"))
        XCTAssertTrue(source.contains(".toggleStyle(.switch)"))
        XCTAssertTrue(source.contains(
            ".accessibilityLabel(Text(L10n.text(.settingsAboutAutomaticCheck)))"
        ))
        XCTAssertTrue(source.contains(
            ".accessibilityValue(Text(L10n.text("
        ))
        XCTAssertTrue(source.contains(
            ".accessibilityHint(Text(L10n.text(.settingsAboutAutomaticCheckDescription)))"
        ))
        XCTAssertFalse(source.contains("@StateObject private var updateChecker"))
        XCTAssertFalse(source.contains("updateChecker.cancel()"))
    }

    func testSettingsSourceRequiresAndForwardsTheSharedCoordinator() throws {
        let source = try repositorySource(
            at: "Sources/CodexNotesProbe/SettingsView.swift"
        )

        XCTAssertTrue(source.contains(
            "init(\n        updateCoordinator: UpdateCheckCoordinator,\n"
                + "        globalHotKeyController: GlobalHotKeyController\n    )"
        ))
        XCTAssertTrue(source.contains(
            "@ObservedObject private var updateCoordinator: UpdateCheckCoordinator"
        ))
        XCTAssertTrue(source.contains(
            "@ObservedObject private var globalHotKeyController: GlobalHotKeyController"
        ))
        XCTAssertTrue(source.contains("updateCoordinator: updateCoordinator"))
        XCTAssertFalse(source.contains("AboutCodexNotesView(\n                        palette: palette,\n                        languageRevision: languageRevision\n"))
    }

    func testSettingsCardsFollowTheRequestedInformationHierarchy() throws {
        let source = try repositorySource(
            at: "Sources/CodexNotesProbe/SettingsView.swift"
        )
        let titleKeys = [
            "settingsGeneralTitle",
            "settingsEditorTitle",
            "settingsAppearanceTitle",
            "settingsStatusBarIconTitle",
            "settingsAboutTitle"
        ]
        let positions = try titleKeys.map { titleKey in
            try XCTUnwrap(
                source.range(
                    of: "settingsPanel(title: L10n.text(.\(titleKey)))"
                )?.lowerBound
            )
        }

        XCTAssertEqual(positions, positions.sorted())
    }

    func testExternalLinksProvideHoverFocusAndCursorFeedback() throws {
        let source = try repositorySource(
            at: "Sources/CodexNotesProbe/AboutCodexNotesView.swift"
        )

        XCTAssertTrue(source.contains("private struct AboutLinkButton: View"))
        XCTAssertTrue(source.contains("@State private var isHovered = false"))
        XCTAssertTrue(source.contains("@FocusState private var isFocused: Bool"))
        XCTAssertTrue(source.contains("trailingSystemImage: \"arrow.up.right\""))
        XCTAssertTrue(source.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(source.contains("PointingHandCursorRegion()"))
        XCTAssertTrue(source.contains("addCursorRect(bounds, cursor: .pointingHand)"))
        XCTAssertTrue(source.contains("isHovered || isFocused"))
        XCTAssertTrue(source.contains(".frame(minHeight: 30)"))
        XCTAssertTrue(source.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(source.contains("private func externalLinkButton("))
        XCTAssertFalse(source.contains(".buttonStyle(.link)\n        .fixedSize"))
        XCTAssertFalse(source.contains("NSCursor.push"))
        XCTAssertFalse(source.contains("NSCursor.pop"))
    }

    func testFeedbackEmailKeepsMailAndCopyAsSeparateAccessibleActions() throws {
        let source = try repositorySource(
            at: "Sources/CodexNotesProbe/AboutCodexNotesView.swift"
        )

        XCTAssertTrue(source.contains("private struct CopyFeedbackEmailButton: View"))
        XCTAssertTrue(source.contains(
            "private var feedbackEmailRow: some View {\n        HStack(alignment: .center, spacing: 4)"
        ))
        XCTAssertTrue(source.contains("trailingSystemImage: nil"))
        XCTAssertTrue(source.contains("Image(systemName: isCopied ? \"checkmark\" : \"doc.on.doc\")"))
        XCTAssertTrue(source.contains("SettingsAboutPresentation.copyFeedbackEmail()"))
        XCTAssertTrue(source.contains(".task(id: emailCopyNoticeID)"))
        XCTAssertTrue(source.contains("emailCopyNoticeID == noticeID"))
        XCTAssertTrue(source.contains(".settingsAboutCopyEmailAccessibilityHint"))
        XCTAssertTrue(source.contains(".settingsAboutEmailCopied"))
    }

    func testPublicLinkAllowListsRejectLookalikesAndInsecureSchemes() throws {
        XCTAssertFalse(SettingsAboutPresentation.isAllowedProjectURL(try url(
            "http://github.com/jiangsir-tech/CodexNotes"
        )))
        XCTAssertFalse(SettingsAboutPresentation.isAllowedProjectURL(try url(
            "https://github.com.example.com/jiangsir-tech/CodexNotes"
        )))
        XCTAssertFalse(SettingsAboutPresentation.isAllowedProjectURL(try url(
            "https://github.com/jiangsir-tech/AnotherProject"
        )))
        XCTAssertFalse(SettingsAboutPresentation.isAllowedXProfileURL(try url(
            "http://x.com/YongJiang_Li_"
        )))
        XCTAssertFalse(SettingsAboutPresentation.isAllowedXProfileURL(try url(
            "https://x.com.example.com/YongJiang_Li_"
        )))
        XCTAssertFalse(SettingsAboutPresentation.isAllowedXProfileURL(try url(
            "https://x.com/SomeoneElse"
        )))
        XCTAssertFalse(SettingsAboutPresentation.isAllowedFeedbackEmailURL(try url(
            "mailto:someone@example.com"
        )))
        XCTAssertFalse(SettingsAboutPresentation.isAllowedFeedbackEmailURL(try url(
            "https://example.com/li-yongjiang@foxmail.com"
        )))
    }

    func testRewardCodeResourceIsTheReviewedImage() throws {
        let resourceURL = try XCTUnwrap(SettingsAboutPresentation.rewardCodeURL())
        let data = try Data(contentsOf: resourceURL)
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        let image = try XCTUnwrap(SettingsAboutPresentation.rewardCodeImage())

        XCTAssertEqual(
            digest,
            "7d3cb0fae45d7b5cc44ed5a092edac8305cbaace0c190ed7a7803ee73aae578f"
        )
        XCTAssertEqual(image.size.width, 1_152, accuracy: 0.5)
        XCTAssertEqual(image.size.height, 1_152, accuracy: 0.5)
        XCTAssertFalse(image.representations.isEmpty)
    }

    private func url(_ value: String) throws -> URL {
        try XCTUnwrap(URL(string: value))
    }

    private func repositorySource(at relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
