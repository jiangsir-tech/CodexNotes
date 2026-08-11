import AppKit
import CodexNotesCore
import SwiftUI

enum SettingsWindowVisibilityNotification {
    static let name = Notification.Name("CodexNotesSettingsWindowVisibilityChanged")
    static let isVisibleKey = "isVisible"

    static func post(isVisible: Bool) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: [isVisibleKey: isVisible]
        )
    }
}

enum SettingsGeneralPresentation {
    static let languagePickerWidth: CGFloat = 112

    static let languageOptions: [AppLanguagePreference] = [
        .system,
        .simplifiedChinese,
        .english,
    ]

    static func languageLabelKey(
        for preference: AppLanguagePreference
    ) -> L10n.Key {
        switch preference {
        case .system:
            return .languageSystem
        case .simplifiedChinese:
            return .languageSimplifiedChinese
        case .english:
            return .languageEnglish
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var updateCoordinator: UpdateCheckCoordinator
    @ObservedObject private var globalHotKeyController: GlobalHotKeyController
    @Environment(\.colorScheme) private var inheritedColorScheme
    @StateObject private var loginItemService = LoginItemService()
    @State private var globalHotKeyErrorKey: L10n.Key?
    @AppStorage(AppLanguagePreference.key)
    private var storedLanguage = AppLanguagePreference.defaultValue.rawValue
    @AppStorage(EditorFontSizePreference.key)
    private var storedEditorFontSize = EditorFontSizePreference.defaultValue
    @AppStorage(EditorLineSpacingPreference.key)
    private var storedEditorLineSpacing = EditorLineSpacingPreference.defaultValue
    @AppStorage(NoteThemePreference.key)
    private var storedThemeID = NoteThemePreference.defaultValue.rawValue
    @AppStorage(StatusBarIconPreference.key)
    private var storedStatusBarIconID = StatusBarIconPreference.defaultValue.rawValue

    init(
        updateCoordinator: UpdateCheckCoordinator,
        globalHotKeyController: GlobalHotKeyController
    ) {
        _updateCoordinator = ObservedObject(wrappedValue: updateCoordinator)
        _globalHotKeyController = ObservedObject(
            wrappedValue: globalHotKeyController
        )
    }

    private var activeTheme: NoteThemeID {
        NoteThemePreference.normalized(storedThemeID)
    }

    private var palette: NoteThemePalette {
        activeTheme.palette
    }

    private var activeStatusBarIcon: StatusBarIconID {
        StatusBarIconPreference.normalized(storedStatusBarIconID)
    }

    private var activeLanguage: AppLanguagePreference {
        AppLanguagePreference.normalized(storedLanguage)
    }

    private var resolvedLanguage: ResolvedAppLanguage {
        AppLocalization.resolve(activeLanguage)
    }

    private var languageRevision: String {
        "\(activeLanguage.rawValue):\(resolvedLanguage.rawValue)"
    }

    private var languagePreference: Binding<AppLanguagePreference> {
        Binding(
            get: { activeLanguage },
            set: { storedLanguage = $0.rawValue }
        )
    }

    private var launchAtLoginPreference: Binding<Bool> {
        Binding(
            get: { loginItemService.isRequestedEnabled },
            set: { loginItemService.setEnabled($0) }
        )
    }

    private var editorFontSize: Binding<Double> {
        Binding(
            get: { EditorFontSizePreference.normalized(storedEditorFontSize) },
            set: { storedEditorFontSize = EditorFontSizePreference.normalized($0) }
        )
    }

    private var editorLineSpacing: Binding<Double> {
        Binding(
            get: { EditorLineSpacingPreference.normalized(storedEditorLineSpacing) },
            set: { storedEditorLineSpacing = EditorLineSpacingPreference.normalized($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsPanel(title: L10n.text(.settingsGeneralTitle)) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text(L10n.text(.settingsLanguageTitle))
                                .font(.subheadline.weight(.medium))

                            Spacer(minLength: 24)

                            Picker(
                                selection: languagePreference,
                                content: {
                                    ForEach(SettingsGeneralPresentation.languageOptions) { language in
                                        Text(L10n.text(
                                            SettingsGeneralPresentation.languageLabelKey(for: language)
                                        ))
                                        .tag(language)
                                    }
                                },
                                label: {
                                    Text(L10n.text(.settingsLanguageTitle))
                                }
                            )
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(
                                width: SettingsGeneralPresentation.languagePickerWidth,
                                alignment: .trailing
                            )
                            .accessibilityLabel(Text(L10n.text(.settingsLanguageTitle)))
                            .accessibilityHint(
                                Text(L10n.text(.settingsLanguageAccessibilityHint))
                            )
                        }
                        .frame(maxWidth: .infinity)

                        Divider()
                            .overlay(palette.separator.color)

                        globalHotKeyControls

                        Divider()
                            .overlay(palette.separator.color)

                        launchAtLoginControls
                    }
                    .frame(maxWidth: .infinity)
                }

                settingsPanel(title: L10n.text(.settingsEditorTitle)) {
                    HStack(spacing: 12) {
                        Text(L10n.text(.settingsEditorFontSize))
                            .font(.subheadline.weight(.medium))
                            .frame(width: 72, alignment: .leading)

                        Slider(
                            value: editorFontSize,
                            in: EditorFontSizePreference.minimum...EditorFontSizePreference.maximum,
                            step: 1
                        )
                        .accessibilityLabel(Text(L10n.text(.settingsEditorFontSize)))
                        .accessibilityValue(Text("\(Int(editorFontSize.wrappedValue)) pt"))
                        .accessibilityHint(Text(L10n.text(.settingsEditorFontSizeAccessibilityHint)))

                        Text("\(Int(editorFontSize.wrappedValue)) pt")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                            .accessibilityHidden(true)
                    }

                    HStack(spacing: 12) {
                        Text(L10n.text(.settingsEditorLineSpacing))
                            .font(.subheadline.weight(.medium))
                            .frame(width: 72, alignment: .leading)

                        Slider(
                            value: editorLineSpacing,
                            in: EditorLineSpacingPreference.minimum...EditorLineSpacingPreference.maximum,
                            step: 1
                        )
                        .accessibilityLabel(Text(L10n.text(.settingsEditorLineSpacing)))
                        .accessibilityValue(Text("\(Int(editorLineSpacing.wrappedValue)) pt"))
                        .accessibilityHint(Text(L10n.text(.settingsEditorLineSpacingAccessibilityHint)))

                        Text("\(Int(editorLineSpacing.wrappedValue)) pt")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                            .accessibilityHidden(true)
                    }

                    Text(L10n.text(.settingsEditorPreviewText))
                        .font(.system(size: editorFontSize.wrappedValue, design: .monospaced))
                        .lineSpacing(editorLineSpacing.wrappedValue)
                        .foregroundStyle(palette.primaryText.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            palette.editorBackground.color,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(palette.separator.color, lineWidth: 0.7)
                        )
                        .accessibilityLabel(Text(L10n.text(.settingsEditorPreviewAccessibilityLabel)))

                    editorFooter
                }

                settingsPanel(title: L10n.text(.settingsAppearanceTitle)) {
                    Text(L10n.text(.settingsAppearanceDescription))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)

                    VStack(spacing: 12) {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            ForEach(
                                NoteThemeID.allCases.filter { $0 != .systemOriginal },
                                id: \.self
                            ) { theme in
                                ThemeChoiceCard(
                                    theme: theme,
                                    isSelected: theme == activeTheme,
                                    languageRevision: languageRevision
                                ) {
                                    storedThemeID = theme.rawValue
                                }
                            }
                        }

                        Text(L10n.text(.settingsAppearanceOriginal))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)

                        ThemeChoiceCard(
                            theme: .systemOriginal,
                            isSelected: activeTheme == .systemOriginal,
                            languageRevision: languageRevision
                        ) {
                            storedThemeID = NoteThemeID.systemOriginal.rawValue
                        }
                    }
                    .accessibilityLabel(Text(L10n.text(.settingsAppearanceThemesAccessibilityLabel)))
                }

                settingsPanel(title: L10n.text(.settingsStatusBarIconTitle)) {
                    Text(L10n.text(.settingsStatusBarIconDescription))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)

                    HStack(spacing: 12) {
                        ForEach(StatusBarIconID.allCases, id: \.self) { icon in
                            StatusBarIconChoiceCard(
                                icon: icon,
                                isSelected: icon == activeStatusBarIcon,
                                palette: palette,
                                languageRevision: languageRevision
                            ) {
                                storedStatusBarIconID = icon.rawValue
                            }
                        }
                    }
                }

                settingsPanel(title: L10n.text(.settingsAboutTitle)) {
                    AboutCodexNotesView(
                        palette: palette,
                        languageRevision: languageRevision,
                        updateCoordinator: updateCoordinator
                    )
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 660)
        .foregroundStyle(palette.primaryText.color)
        .tint(palette.accent.color)
        .environment(\.colorScheme, palette.colorScheme ?? inheritedColorScheme)
        .background(palette.windowBackground.color)
        .overlay {
            if activeTheme.usesCottonPaperTexture {
                CottonPaperTextureOverlay()
            } else if activeTheme.usesSilverTracingPaperTexture {
                SilverTracingPaperTextureOverlay()
            } else if activeTheme.usesNorthSeaCyanotypeTexture {
                NorthSeaCyanotypeTextureOverlay()
            } else if activeTheme.usesEucalyptusCottonPaperTexture {
                EucalyptusCottonPaperTextureOverlay()
            } else if activeTheme.usesBordeauxCottonPaperTexture {
                BordeauxCottonPaperTextureOverlay()
            }
        }
        .background(
            SettingsWindowActivator(
                appearanceName: palette.appearanceName,
                backgroundColor: palette.windowBackground.nsColor
            )
        )
        .onAppear {
            loginItemService.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            loginItemService.refresh()
        }
    }

    @ViewBuilder
    private var editorFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                editorWindowResizeHint
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 12)

                editorRestoreDefaultsButton
            }

            VStack(alignment: .leading, spacing: 8) {
                editorWindowResizeHint
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    editorRestoreDefaultsButton
                }
            }
        }
    }

    private var editorWindowResizeHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .accessibilityHidden(true)

            Text(L10n.text(.settingsEditorWindowResizeHint))
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryText.color)
        .accessibilityElement(children: .combine)
    }

    private var editorRestoreDefaultsButton: some View {
        Button(L10n.text(.settingsEditorRestoreDefaults)) {
            storedEditorFontSize = EditorFontSizePreference.defaultValue
            storedEditorLineSpacing = EditorLineSpacingPreference.defaultValue
        }
        .disabled(
            EditorFontSizePreference.normalized(storedEditorFontSize)
                == EditorFontSizePreference.defaultValue
                && EditorLineSpacingPreference.normalized(
                    storedEditorLineSpacing
                ) == EditorLineSpacingPreference.defaultValue
        )
        .accessibilityLabel(Text(L10n.text(.settingsEditorRestoreDefaultsAccessibilityLabel)))
        .accessibilityHint(Text(L10n.text(.settingsEditorRestoreDefaultsAccessibilityHint)))
    }

    private var globalHotKeyControls: some View {
        GlobalHotKeyRecorderView(
            shortcutDisplayName: globalHotKeyController.currentShortcut == nil
                ? nil
                : globalHotKeyController.displayName,
            isRecording: globalHotKeyController.isRecording,
            isDefault: globalHotKeyController.isDefault,
            errorMessage: globalHotKeyErrorMessage,
            palette: palette,
            beginRecording: {
                globalHotKeyErrorKey = nil
                globalHotKeyController.beginRecording()
            },
            cancelRecording: {
                globalHotKeyErrorKey = nil
                globalHotKeyController.cancelRecording()
            },
            recordShortcut: { keyCode, modifierFlags in
                let shortcut = GlobalHotKeyShortcut(
                    keyCode: UInt32(keyCode),
                    modifiers: GlobalHotKeyModifiers(
                        nseventFlags: modifierFlags
                    )
                )
                guard shortcut.validationIssue == nil else {
                    globalHotKeyErrorKey = .settingsGlobalHotKeyInvalidShortcut
                    return
                }

                handleGlobalHotKeyUpdateResult(
                    globalHotKeyController.commitRecordedShortcut(shortcut)
                )
            },
            clearShortcut: {
                globalHotKeyErrorKey = nil
                globalHotKeyController.clear()
            },
            restoreDefault: {
                globalHotKeyErrorKey = nil
                handleGlobalHotKeyUpdateResult(globalHotKeyController.restore())
            }
        )
    }

    private var globalHotKeyErrorMessage: String? {
        if let globalHotKeyErrorKey {
            return L10n.text(globalHotKeyErrorKey)
        }
        guard let issue = globalHotKeyController.registrationState.issue else {
            return nil
        }
        return L10n.text(globalHotKeyErrorKey(for: issue))
    }

    private func globalHotKeyErrorKey(
        for issue: GlobalHotKeyRegistrationIssue
    ) -> L10n.Key {
        switch issue {
        case .invalidShortcut:
            return .settingsGlobalHotKeyInvalidShortcut
        case .conflict:
            return .settingsGlobalHotKeyConflict
        case .registrationFailed, .backendFailed:
            return .settingsGlobalHotKeyRegistrationFailed
        }
    }

    private func handleGlobalHotKeyUpdateResult(
        _ result: GlobalHotKeyUpdateResult
    ) {
        switch result {
        case .updated:
            globalHotKeyErrorKey = nil
        case .rejected:
            globalHotKeyErrorKey = .settingsGlobalHotKeyInvalidShortcut
        case .conflict, .failed:
            globalHotKeyErrorKey = nil
        }
    }

    private var launchAtLoginControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(.settingsLaunchAtLoginTitle))
                        .font(.subheadline.weight(.medium))
                    Text(L10n.text(.settingsLaunchAtLoginDescription))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityHidden(true)

                Spacer(minLength: 24)

                Toggle(
                    L10n.text(.settingsLaunchAtLoginTitle),
                    isOn: launchAtLoginPreference
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(loginItemService.isUpdating)
                .accessibilityLabel(Text(L10n.text(.settingsLaunchAtLoginTitle)))
                .accessibilityValue(Text(L10n.text(
                    loginItemService.isRequestedEnabled
                        ? .accessibilityValueOn
                        : .accessibilityValueOff
                )))
                .accessibilityHint(Text(L10n.text(.settingsLaunchAtLoginDescription)))
            }

            if loginItemService.requiresUserApproval {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(palette.warning.color)
                            .accessibilityHidden(true)
                        Text(L10n.text(.settingsLaunchAtLoginRequiresApproval))
                            .font(.caption)
                            .foregroundStyle(palette.warning.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(L10n.text(.settingsLaunchAtLoginOpenSystemSettings)) {
                        loginItemService.openSystemSettingsLoginItems()
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .padding(.leading, 20)
                }
            } else if loginItemService.lastFailure != nil {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(palette.error.color)
                        .accessibilityHidden(true)
                    Text(L10n.text(.settingsLaunchAtLoginError))
                        .font(.caption)
                        .foregroundStyle(palette.error.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func settingsPanel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(
            palette.panelBackground.color,
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(palette.separator.color, lineWidth: 0.7)
        )
    }
}

private struct StatusBarIconChoiceCard: View {
    let icon: StatusBarIconID
    let isSelected: Bool
    let palette: NoteThemePalette
    let languageRevision: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(
                    nsImage: StatusBarIconArtwork.image(for: icon)
                        ?? StatusBarIconArtwork.fallbackImage()
                        ?? NSImage()
                )
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .foregroundStyle(palette.primaryText.color)
                .frame(width: 58, height: 58)
                .background(
                    palette.editorBackground.color,
                    in: RoundedRectangle(cornerRadius: 11)
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(icon.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(icon.summary)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText.color)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 2)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accent.color)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .foregroundStyle(palette.primaryText.color)
            .background(
                palette.windowBackground.color,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        isSelected
                            ? palette.accent.color
                            : palette.secondaryText.color.opacity(0.65),
                        lineWidth: isSelected ? 2 : 0.8
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.text(
            .settingsStatusBarIconChoiceAccessibilityLabel,
            replacements: ["name": icon.displayName]
        )))
        .accessibilityValue(Text(isSelected ? L10n.text(.commonStateSelected) : icon.summary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(icon.summary)
    }
}

private struct ThemeChoiceCard: View {
    let theme: NoteThemeID
    let isSelected: Bool
    let languageRevision: String
    let action: () -> Void

    private var palette: NoteThemePalette {
        theme.palette
    }

    private var unselectedBorderColor: Color {
        if theme == .systemOriginal {
            return palette.secondaryText.color.opacity(0.65)
        }
        return palette.primaryText.color.opacity(0.18)
    }

    private var selectedBorderColor: Color {
        if theme == .midnightIndigo {
            return palette.accent.color.opacity(0.60)
        }
        return palette.accent.color
    }

    private var selectedBorderWidth: CGFloat {
        theme == .midnightIndigo ? 1 : 2
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(palette.accent.color)
                        .frame(width: 9, height: 9)

                    Text(theme.displayName)
                        .font(.subheadline.weight(.semibold))

                    Spacer(minLength: 4)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent.color)
                    }
                }

                Text(theme.summary)
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(palette.editorBackground.color)
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(palette.selectedBackground.color)
                        .frame(width: 34, height: 12)
                    Circle()
                        .fill(palette.success.color)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .foregroundStyle(palette.primaryText.color)
            .background(
                palette.windowBackground.color,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        isSelected
                            ? selectedBorderColor
                            : unselectedBorderColor,
                        lineWidth: isSelected ? selectedBorderWidth : 0.8
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(L10n.text(
            .settingsThemeChoiceAccessibilityLabel,
            replacements: ["name": theme.displayName]
        )))
        .accessibilityValue(Text(isSelected ? L10n.text(.commonStateSelected) : theme.summary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(theme.summary)
    }
}

struct SettingsWindowActivator: NSViewRepresentable {
    let appearanceName: NSAppearance.Name?
    let backgroundColor: NSColor

    final class Coordinator {
        private weak var window: NSWindow?
        private var didBecomeKeyObserver: NSObjectProtocol?
        private var willCloseObserver: NSObjectProtocol?
        private var isVisible = false
        private var isWindowClosing = false
        private var isInvalidated = false

        func attach(
            to window: NSWindow,
            appearanceName: NSAppearance.Name?,
            backgroundColor: NSColor
        ) {
            guard !isInvalidated else { return }
            window.identifier = CodexNotesWindowIdentifier.settings
            applyTheme(
                to: window,
                appearanceName: appearanceName,
                backgroundColor: backgroundColor
            )
            if self.window === window {
                if window.isVisible {
                    isWindowClosing = false
                    setVisible(true)
                }
                return
            }

            detach()
            self.window = window
            isWindowClosing = false
            didBecomeKeyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.isWindowClosing = false
                self?.setVisible(true)
            }
            willCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.isWindowClosing = true
                self?.setVisible(false)
            }

            guard !isWindowClosing else { return }
            setVisible(true)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        private func applyTheme(
            to window: NSWindow,
            appearanceName: NSAppearance.Name?,
            backgroundColor: NSColor
        ) {
            if let appearanceName {
                if window.appearance?.name != appearanceName {
                    window.appearance = NSAppearance(named: appearanceName)
                }
            } else if window.appearance != nil {
                window.appearance = nil
            }
            if !window.backgroundColor.isEqual(backgroundColor) {
                window.backgroundColor = backgroundColor
            }
        }

        func detach() {
            if let didBecomeKeyObserver {
                NotificationCenter.default.removeObserver(didBecomeKeyObserver)
            }
            if let willCloseObserver {
                NotificationCenter.default.removeObserver(willCloseObserver)
            }
            didBecomeKeyObserver = nil
            willCloseObserver = nil
            window = nil
            isWindowClosing = false
            setVisible(false)
        }

        func invalidate() {
            isInvalidated = true
            detach()
        }

        private func setVisible(_ isVisible: Bool) {
            guard self.isVisible != isVisible else { return }
            self.isVisible = isVisible
            SettingsWindowVisibilityNotification.post(isVisible: isVisible)
        }

        deinit {
            detach()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            coordinator.attach(
                to: window,
                appearanceName: appearanceName,
                backgroundColor: backgroundColor
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            coordinator.attach(
                to: window,
                appearanceName: appearanceName,
                backgroundColor: backgroundColor
            )
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.invalidate()
    }
}
