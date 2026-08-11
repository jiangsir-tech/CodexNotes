import AppKit
import CodexNotesCore
import SwiftUI

enum SettingsAboutPresentation {
    static let appName = "CodexNotes"
    static let repositoryURL = URL(string: "https://github.com/jiangsir-tech/CodexNotes")!
    static let xProfileURL = URL(string: "https://x.com/YongJiang_Li_")!
    static let feedbackEmailAddress = "li-yongjiang@foxmail.com"
    static let feedbackEmailURL = URL(string: "mailto:\(feedbackEmailAddress)")!
    static let rewardCodeResourceName = "WeChatRewardCode"
    static let rewardCodeResourceExtension = "jpg"
    static let appIconSize: CGFloat = 64
    static let copyConfirmationDurationNanoseconds: UInt64 = 1_500_000_000

    static func visibleVersion(_ bundleVersion: AppBundleVersion) -> String {
        bundleVersion.version
    }

    static func rewardCodeURL(bundle: Bundle = .module) -> URL? {
        bundle.url(
            forResource: rewardCodeResourceName,
            withExtension: rewardCodeResourceExtension
        )
    }

    static func rewardCodeImage(bundle: Bundle = .module) -> NSImage? {
        guard let url = rewardCodeURL(bundle: bundle) else { return nil }
        return NSImage(contentsOf: url)
    }

    @MainActor
    @discardableResult
    static func copyFeedbackEmail(to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(feedbackEmailAddress, forType: .string)
    }

    static func isAllowedProjectURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host?.lowercased() == "github.com"
            && url.path == "/jiangsir-tech/CodexNotes"
    }

    static func isAllowedXProfileURL(_ url: URL) -> Bool {
        url.scheme == "https"
            && url.host?.lowercased() == "x.com"
            && url.path == "/YongJiang_Li_"
    }

    static func isAllowedFeedbackEmailURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "mailto"
            && url.absoluteString == "mailto:\(feedbackEmailAddress)"
    }
}

struct AboutCodexNotesView: View {
    let palette: NoteThemePalette
    let languageRevision: String

    @ObservedObject private var updateCoordinator: UpdateCheckCoordinator
    @State private var isShowingRewardCode = false
    @State private var emailCopyNoticeID: UUID?

    private let bundleVersion = AppBundleVersion.current

    init(
        palette: NoteThemePalette,
        languageRevision: String,
        updateCoordinator: UpdateCheckCoordinator
    ) {
        self.palette = palette
        self.languageRevision = languageRevision
        _updateCoordinator = ObservedObject(wrappedValue: updateCoordinator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            appIdentity

            Divider()
                .overlay(palette.separator.color)

            VStack(alignment: .leading, spacing: 12) {
                versionRow
                automaticCheckRow
                informationRow(
                    label: L10n.text(.settingsAboutAuthor),
                    value: L10n.text(.settingsAboutAuthorName)
                )
                feedbackEmailRow
            }

            Divider()
                .overlay(palette.separator.color)

            supportRow
        }
        .sheet(isPresented: $isShowingRewardCode) {
            WeChatRewardCodeSheet(
                palette: palette,
                image: SettingsAboutPresentation.rewardCodeImage()
            )
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(
                    width: SettingsAboutPresentation.appIconSize,
                    height: SettingsAboutPresentation.appIconSize
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(SettingsAboutPresentation.appName)
                    .font(.title2.weight(.semibold))
                Text(L10n.text(.settingsAboutSubtitle))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var versionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(L10n.text(.settingsAboutVersion))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.secondaryText.color)
                .frame(width: 64, alignment: .leading)

            Text(SettingsAboutPresentation.visibleVersion(bundleVersion))
                .font(.subheadline)
                .monospacedDigit()
                .lineLimit(1)

            Spacer(minLength: 8)

            updateStatus

            Button(updateActionTitle) {
                performUpdateAction()
            }
            .disabled(updateCoordinator.state == .checking)
            .controlSize(.regular)
            .accessibilityHint(Text(updateActionAccessibilityHint))
        }
    }

    private var automaticCheckRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(.settingsAboutAutomaticCheck))
                    .font(.subheadline.weight(.medium))
                Text(L10n.text(.settingsAboutAutomaticCheckDescription))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)

            Toggle(
                L10n.text(.settingsAboutAutomaticCheck),
                isOn: automaticCheckPreference
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
            .accessibilityLabel(Text(L10n.text(.settingsAboutAutomaticCheck)))
            .accessibilityValue(Text(L10n.text(
                updateCoordinator.isAutomaticCheckEnabled
                    ? .accessibilityValueOn
                    : .accessibilityValueOff
            )))
            .accessibilityHint(Text(L10n.text(.settingsAboutAutomaticCheckDescription)))
        }
        .frame(maxWidth: .infinity)
    }

    private var automaticCheckPreference: Binding<Bool> {
        Binding(
            get: { updateCoordinator.isAutomaticCheckEnabled },
            set: { updateCoordinator.setAutomaticChecksEnabled($0) }
        )
    }

    private func informationRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.secondaryText.color)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    private var feedbackEmailRow: some View {
        HStack(alignment: .center, spacing: 4) {
            Text(L10n.text(.settingsAboutFeedbackEmail))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.secondaryText.color)
                .frame(width: 64, alignment: .leading)

            HStack(spacing: 4) {
                AboutLinkButton(
                    title: SettingsAboutPresentation.feedbackEmailAddress,
                    url: SettingsAboutPresentation.feedbackEmailURL,
                    accessibilityHint: L10n.text(
                        .settingsAboutFeedbackEmailAccessibilityHint
                    ),
                    trailingSystemImage: nil,
                    palette: palette
                )

                CopyFeedbackEmailButton(
                    isCopied: isShowingEmailCopied,
                    palette: palette,
                    action: copyFeedbackEmail
                )

                Text(L10n.text(.settingsAboutEmailCopied))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.accent.color)
                    .lineLimit(1)
                    .frame(minWidth: 50, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(isShowingEmailCopied ? 1 : 0)
                    .accessibilityHidden(true)
            }

            Spacer(minLength: 0)
        }
        .task(id: emailCopyNoticeID) { @MainActor in
            guard let noticeID = emailCopyNoticeID else { return }

            do {
                try await Task.sleep(
                    nanoseconds: SettingsAboutPresentation
                        .copyConfirmationDurationNanoseconds
                )
            } catch {
                return
            }
            guard !Task.isCancelled, emailCopyNoticeID == noticeID else { return }
            emailCopyNoticeID = nil
        }
    }

    private var isShowingEmailCopied: Bool {
        emailCopyNoticeID != nil
    }

    private func copyFeedbackEmail() {
        guard SettingsAboutPresentation.copyFeedbackEmail() else {
            emailCopyNoticeID = nil
            return
        }
        emailCopyNoticeID = UUID()
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateCoordinator.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.text(.settingsAboutChecking))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText.color)
            }
            .accessibilityElement(children: .combine)
        case .upToDate:
            Text(L10n.text(.settingsAboutUpToDate))
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.accent.color)
        case let .updateAvailable(version, _):
            Text(L10n.text(
                .settingsAboutUpdateAvailable,
                replacements: ["version": version]
            ))
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.accent.color)
        case .failed:
            Text(L10n.text(.settingsAboutUpdateFailed))
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.error.color)
        }
    }

    private var updateActionTitle: String {
        switch updateCoordinator.state {
        case .checking:
            return L10n.text(.settingsAboutChecking)
        case .updateAvailable:
            return L10n.text(.settingsAboutViewUpdate)
        case .failed:
            return L10n.text(.commonActionRetry)
        case .idle, .upToDate:
            return L10n.text(.settingsAboutCheckUpdates)
        }
    }

    private var updateActionAccessibilityHint: String {
        switch updateCoordinator.state {
        case .updateAvailable:
            return L10n.text(.settingsAboutViewUpdateAccessibilityHint)
        case .idle, .checking, .upToDate, .failed:
            return L10n.text(.settingsAboutCheckUpdatesAccessibilityHint)
        }
    }

    private func performUpdateAction() {
        if case let .updateAvailable(_, url) = updateCoordinator.state {
            updateCoordinator.dismissBanner()
            NSWorkspace.shared.open(url)
            return
        }

        Task { @MainActor [updateCoordinator] in
            await updateCoordinator.manualCheck()
        }
    }

    private var supportRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                supportLinks
                Spacer(minLength: 8)
                coffeeButton
            }

            VStack(alignment: .leading, spacing: 10) {
                supportLinks
                coffeeButton
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var supportLinks: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                gitHubLink
                xProfileLink
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 2) {
                gitHubLink
                xProfileLink
            }
        }
    }

    private var gitHubLink: some View {
        AboutLinkButton(
            title: L10n.text(.settingsAboutGitHub),
            url: SettingsAboutPresentation.repositoryURL,
            accessibilityHint: L10n.text(.settingsAboutGitHubAccessibilityHint),
            trailingSystemImage: "arrow.up.right",
            palette: palette
        )
    }

    private var xProfileLink: some View {
        AboutLinkButton(
            title: L10n.text(.settingsAboutX),
            url: SettingsAboutPresentation.xProfileURL,
            accessibilityHint: L10n.text(.settingsAboutXAccessibilityHint),
            trailingSystemImage: "arrow.up.right",
            palette: palette
        )
    }

    private var coffeeButton: some View {
        Button(L10n.text(.settingsAboutCoffee)) {
            isShowingRewardCode = true
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 0.84, green: 0.57, blue: 0.14))
        .foregroundStyle(Color.black.opacity(0.82))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHint(Text(L10n.text(.settingsAboutCoffeeAccessibilityHint)))
    }
}

private struct AboutLinkButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    let title: String
    let url: URL
    let accessibilityHint: String
    let trailingSystemImage: String?
    let palette: NoteThemePalette

    private var isHighlighted: Bool {
        isHovered || isFocused
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .lineLimit(1)

                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .offset(
                            x: isHighlighted && !reduceMotion ? 1 : 0,
                            y: isHighlighted && !reduceMotion ? -1 : 0
                        )
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(
                isHighlighted ? palette.accent.color : palette.primaryText.color
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 30)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(palette.accent.color.opacity(isHighlighted ? 0.09 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        palette.accent.color.opacity(isHighlighted ? 0.30 : 0),
                        lineWidth: 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .focused($isFocused)
        .overlay {
            PointingHandCursorRegion()
                .allowsHitTesting(false)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onDisappear {
            isHovered = false
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.13),
            value: isHighlighted
        )
        .help(accessibilityHint)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(accessibilityHint))
    }
}

private struct CopyFeedbackEmailButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    let isCopied: Bool
    let palette: NoteThemePalette
    let action: () -> Void

    private var isHighlighted: Bool {
        isHovered || isFocused || isCopied
    }

    private var accessibilityLabel: String {
        L10n.text(isCopied ? .settingsAboutEmailCopied : .settingsAboutCopyEmail)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    isHighlighted ? palette.accent.color : palette.secondaryText.color
                )
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.accent.color.opacity(isHighlighted ? 0.09 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            palette.accent.color.opacity(isHighlighted ? 0.30 : 0),
                            lineWidth: 1
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .overlay {
            PointingHandCursorRegion()
                .allowsHitTesting(false)
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onDisappear {
            isHovered = false
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.13),
            value: isHighlighted
        )
        .help(accessibilityLabel)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityHint(Text(L10n.text(.settingsAboutCopyEmailAccessibilityHint)))
    }
}

private struct PointingHandCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        PointingHandCursorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class PointingHandCursorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }
}

private struct WeChatRewardCodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let palette: NoteThemePalette
    let image: NSImage?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Text(L10n.text(.settingsAboutQRCodeTitle))
                    .font(.title2.weight(.semibold))
                Text(L10n.text(.settingsAboutQRCodeMessage))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText.color)
                    .multilineTextAlignment(.center)
            }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 360, height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(Text(L10n.text(.settingsAboutQRCodeAccessibilityLabel)))
            } else {
                ContentUnavailableView(
                    L10n.text(.settingsAboutQRCodeUnavailable),
                    systemImage: "qrcode"
                )
                .frame(width: 360, height: 360)
            }

            Button(L10n.text(.settingsAboutClose)) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 420)
        .foregroundStyle(palette.primaryText.color)
        .background(palette.windowBackground.color)
    }
}
