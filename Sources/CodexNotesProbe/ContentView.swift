import AppKit
import CodexNotesCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: ProbeViewModel
    @ObservedObject var updateCoordinator: UpdateCheckCoordinator
    @ObservedObject var globalHotKeyController: GlobalHotKeyController
    let languagePreference: AppLanguagePreference
    @StateObject private var editorController = MarkdownEditorController()
    @Environment(\.colorScheme) private var inheritedColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(EditorFontSizePreference.key)
    private var storedEditorFontSize = EditorFontSizePreference.defaultValue
    @AppStorage(EditorLineSpacingPreference.key)
    private var storedEditorLineSpacing = EditorLineSpacingPreference.defaultValue
    @AppStorage(NoteThemePreference.key)
    private var storedThemeID = NoteThemePreference.defaultValue.rawValue
    @State private var isShortcutReferencePresented = false

    private var activeTheme: NoteThemeID {
        NoteThemePreference.normalized(storedThemeID)
    }

    private var palette: NoteThemePalette {
        activeTheme.palette
    }

    private var resolvedLanguage: ResolvedAppLanguage {
        AppLocalization.resolve(languagePreference)
    }

    private var languageRevision: String {
        "\(languagePreference.rawValue):\(resolvedLanguage.rawValue)"
    }

    private var globalHotKeyDisplayName: String? {
        guard globalHotKeyController.currentShortcut != nil else { return nil }
        return globalHotKeyController.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                scopeSelector
                if let update = updateCoordinator.bannerUpdate {
                    appUpdateBanner(update)
                }
                if case let .unavailable(message) = model.state {
                    connectionIssueBanner(message)
                }
                if let message = model.imageImportError {
                    imageImportIssueBanner(message)
                }
                editor
            }
            .frame(maxHeight: .infinity)

            bottomBar
                .padding(.top, BottomBarActionMetrics.editorSpacing)
        }
        .padding(.horizontal, BottomBarActionMetrics.horizontalContentInset)
        .padding(.top, BottomBarActionMetrics.topContentInset)
        .padding(.bottom, BottomBarActionMetrics.bottomPadding)
        .frame(
            minWidth: BottomBarActionMetrics.minimumWindowWidth,
            idealWidth: 400,
            minHeight: 520,
            idealHeight: 660
        )
        .foregroundStyle(palette.primaryText.color)
        .tint(palette.accent.color)
        .environment(\.locale, resolvedLanguage.locale)
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
            WindowConfigurator(
                appearanceName: palette.appearanceName,
                backgroundColor: palette.windowBackground.nsColor,
                languageRevision: languageRevision
            )
        )
        .background(
            ShortcutReferenceEscapeMonitorView(
                isPresented: isShortcutReferencePresented
            ) {
                isShortcutReferencePresented = false
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
        .onAppear { model.start() }
        .alert(
            L10n.text(.moveSelectionAlertTitle),
            isPresented: Binding(
                get: { model.selectionMoveError != nil },
                set: { isPresented in
                    if !isPresented {
                        model.dismissSelectionMoveError()
                    }
                }
            )
        ) {
            Button(L10n.text(.commonActionOK), role: .cancel) {
                model.dismissSelectionMoveError()
            }
        } message: {
            Text(model.selectionMoveError ?? L10n.text(.moveSelectionAlertRetryMessage))
        }
    }

    private var connectionStatusText: String {
        switch model.state {
        case .starting: L10n.text(.connectionStatusDetecting)
        case .detected: L10n.text(.connectionStatusFollowing)
        case .newTask: L10n.text(.connectionStatusNewTask)
        case .unavailable: L10n.text(.connectionStatusPaused)
        }
    }

    private func connectionIssueBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L10n.text(.commonActionRetry)) { model.retry() }
                .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(palette.warning.color)
    }

    private func imageImportIssueBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "photo.badge.exclamationmark")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                model.dismissImageImportError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(L10n.text(.imageImportDismissAccessibilityLabel)))
        }
        .font(.caption)
        .foregroundStyle(palette.warning.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.panelBackground.color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func appUpdateBanner(_ update: AvailableAppUpdate) -> some View {
        let presentation = AppUpdateBannerPresentation(update)

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                appUpdateBannerTitle(presentation)
                Spacer(minLength: 4)
                appUpdateBannerActions(update, presentation: presentation)
            }

            VStack(alignment: .leading, spacing: 8) {
                appUpdateBannerTitle(presentation)
                appUpdateBannerActions(update, presentation: presentation)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            palette.panelBackground.color.opacity(0.97),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(palette.accent.color.opacity(0.45), lineWidth: 0.8)
        )
        .accessibilityElement(children: .contain)
    }

    private func appUpdateBannerTitle(
        _ presentation: AppUpdateBannerPresentation
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(palette.accent.color)
                .accessibilityHidden(true)
            Text(presentation.title)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func appUpdateBannerActions(
        _ update: AvailableAppUpdate,
        presentation: AppUpdateBannerPresentation
    ) -> some View {
        HStack(spacing: 10) {
            Button(presentation.viewTitle) {
                updateCoordinator.dismissBanner()
                NSWorkspace.shared.open(update.url)
            }
            .buttonStyle(.link)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityHint(Text(presentation.viewAccessibilityHint))

            Button(presentation.laterTitle) {
                updateCoordinator.dismissBanner()
            }
            .buttonStyle(.link)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var scopeSelector: some View {
        let usesIndependentCards = activeTheme.usesIndependentScopeCards

        return HStack(spacing: usesIndependentCards ? 8 : 4) {
            scopeButton(.task)
            scopeButton(.project)
        }
        .padding(usesIndependentCards ? 0 : 3)
        .background(
            usesIndependentCards ? Color.clear : palette.panelBackground.color,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    usesIndependentCards ? Color.clear : palette.separator.color,
                    lineWidth: usesIndependentCards ? 0 : 0.7
                )
        )
    }

    private func scopeButton(_ scope: NoteScope) -> some View {
        let selected = model.selectedScope == scope
        let canConfirmCandidate = scope == .project && model.canConfirmNewTaskProject
        let enabled = scope == .task
            ? !model.isSwitchBlocked
            : model.canUseProjectNote || canConfirmCandidate
        let progress = scope == .task
            ? model.taskChecklistProgress
            : model.projectChecklistProgress
        let usesIndependentCards = activeTheme.usesIndependentScopeCards
        let cardCornerRadius: CGFloat = usesIndependentCards ? 11 : 7
        let selectedCardBackground = activeTheme == .warmPaper || activeTheme == .mistPaper
            ? palette.selectedBackground.color
            : palette.editorBackground.color
        let cardBackground = usesIndependentCards
            ? (selected ? selectedCardBackground : palette.panelBackground.color)
            : (selected ? palette.selectedBackground.color : Color.clear)
        let selectedBorder = activeTheme == .midnightIndigo
            ? palette.accent.color.opacity(0.64)
            : palette.accent.color
        let cardBorder = usesIndependentCards
            ? (selected ? selectedBorder : palette.separator.color)
            : Color.clear
        let cardBorderWidth: CGFloat = usesIndependentCards ? 1 : 0

        return Button {
            if canConfirmCandidate {
                if model.confirmNewTaskProject() {
                    model.selectScope(.project)
                }
            } else {
                model.selectScope(scope)
            }
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: scopeIconName(scope))
                        .foregroundStyle(
                            selected && activeTheme.usesIndependentScopeCards
                                ? palette.accent.color
                                : palette.primaryText.color
                        )
                        .accessibilityHidden(true)
                    Text(scope.displayName)
                }
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .lineLimit(1)

                HStack(alignment: .center, spacing: 5) {
                    Group {
                        if let progress, progress.total > 0 {
                            ChecklistProgressRing(
                                progress: progress,
                                trackColor: palette.secondaryText.color,
                                progressColor: palette.secondaryText.color,
                                successColor: palette.success.color,
                                checkmarkColor: palette.editorBackground.color,
                                reduceMotion: reduceMotion
                            )
                            .id(scopeProgressIdentity(scope))
                            .opacity(selected ? 1 : 0.62)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)

                    Text(scopeContextName(scope))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }
                .font(.body)
                .foregroundStyle(palette.secondaryText.color)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                cardBackground,
                in: RoundedRectangle(cornerRadius: cardCornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius)
                    .stroke(cardBorder, lineWidth: cardBorderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.58)
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(palette.accent.color)
                .frame(
                    width: ScopeSelectionIndicatorMetrics.diameter,
                    height: ScopeSelectionIndicatorMetrics.diameter
                )
                .padding(.top, ScopeSelectionIndicatorMetrics.edgeInset)
                .padding(.trailing, ScopeSelectionIndicatorMetrics.edgeInset)
                .opacity(selected ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .help(scopeHelp(scope, progress: progress, enabled: enabled))
        .accessibilityLabel(
            Text(
                L10n.text(
                    .scopeAccessibilityLabel,
                    replacements: [
                        "scope": scope.displayName,
                        "context": scopeContextName(scope),
                    ]
                )
            )
        )
        .accessibilityValue(Text(scopeAccessibilityValue(scope, progress: progress)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .keyboardShortcut(shortcut(for: scope).shortcut)
    }

    private func scopeIconName(_ scope: NoteScope) -> String {
        switch scope {
        case .task: return "checklist"
        case .project:
            return model.canConfirmNewTaskProject ? "folder.badge.questionmark" : "folder"
        }
    }

    private func scopeHelp(
        _ scope: NoteScope,
        progress: MarkdownChecklistProgress?,
        enabled: Bool
    ) -> String {
        if model.isSwitchBlocked {
            var replacements = [
                "scope": scope.displayName,
                "context": scopeContextName(scope),
            ]
            if scope == .task {
                replacements["status"] = connectionStatusText
                return L10n.text(
                    .scopeHelpSwitchUnavailableWithStatus,
                    replacements: replacements
                )
            }
            return L10n.text(
                .scopeHelpSwitchUnavailable,
                replacements: replacements
            )
        }
        if scope == .project, let candidateProjectName {
            return L10n.text(
                .scopeHelpProjectConfirmCandidate,
                replacements: ["name": candidateProjectName]
            )
        }
        if scope == .project, newTaskProjectIsConfirmedReadOnly {
            return L10n.text(
                .scopeHelpProjectNewTaskReadOnly,
                replacements: ["name": currentProjectName]
            )
        }
        if scope == .project {
            switch currentProjectMembership {
            case .none:
                return L10n.text(.scopeHelpProjectNotInProject)
            case .unknown:
                return L10n.text(.scopeHelpProjectInfoUnavailable)
            case .assigned where !hasProjectPath:
                return L10n.text(
                    .scopeHelpProjectNoWorkingDirectory,
                    replacements: ["name": currentProjectName]
                )
            case .assigned:
                break
            }
        }
        if !enabled {
            return L10n.text(
                .scopeHelpSwitchUnavailable,
                replacements: [
                    "scope": scope.displayName,
                    "context": scopeContextName(scope),
                ]
            )
        }
        var replacements = [
            "scope": scope.displayName,
            "context": scopeContextName(scope),
            "progress": scopeProgressDescription(progress),
        ]
        if scope == .task {
            replacements["status"] = connectionStatusText
            return L10n.text(.scopeHelpStandardWithStatus, replacements: replacements)
        }
        return L10n.text(.scopeHelpStandard, replacements: replacements)
    }

    private func scopeProgressDescription(_ progress: MarkdownChecklistProgress?) -> String {
        guard let progress else { return L10n.text(.scopeProgressUnavailable) }
        guard progress.total > 0 else { return L10n.text(.scopeProgressEmpty) }
        if progress.completed >= progress.total {
            return L10n.text(
                .scopeProgressAllComplete,
                replacements: ["total": String(progress.total)]
            )
        }
        return L10n.text(
            .scopeProgressCompleted,
            replacements: [
                "completed": String(progress.completed),
                "total": String(progress.total),
            ]
        )
    }

    private func scopeAccessibilityValue(
        _ scope: NoteScope,
        progress: MarkdownChecklistProgress?
    ) -> String {
        if model.isSwitchBlocked {
            if scope == .task {
                return L10n.text(
                    .scopeAccessibilitySwitchUnavailableWithStatus,
                    replacements: ["status": connectionStatusText]
                )
            }
            return L10n.text(.scopeAccessibilitySwitchUnavailable)
        }
        if scope == .project, let candidateProjectName {
            return L10n.text(
                .scopeAccessibilityProjectConfirmCandidate,
                replacements: ["name": candidateProjectName]
            )
        }
        if scope == .project, newTaskProjectIsConfirmedReadOnly {
            return L10n.text(
                .scopeAccessibilityProjectConfirmedReadOnly,
                replacements: ["name": currentProjectName]
            )
        }
        if scope == .project {
            switch currentProjectMembership {
            case .none:
                return L10n.text(.scopeAccessibilityProjectNotInProject)
            case .unknown:
                return L10n.text(.scopeAccessibilityProjectInfoUnavailable)
            case .assigned where !hasProjectPath:
                return L10n.text(.scopeAccessibilityProjectNoWorkingDirectory)
            case .assigned:
                break
            }
        }
        if scope == .task {
            return L10n.text(
                .scopeAccessibilityStatusAndProgress,
                replacements: [
                    "status": connectionStatusText,
                    "progress": scopeProgressDescription(progress),
                ]
            )
        }
        return scopeProgressDescription(progress)
    }

    private func scopeContextName(_ scope: NoteScope) -> String {
        switch scope {
        case .task:
            return currentTaskName
        case .project:
            return currentProjectName
        }
    }

    private var currentProjectName: String {
        if let candidateProjectName {
            return L10n.text(
                .projectNameConfirmCandidate,
                replacements: ["name": candidateProjectName]
            )
        }
        switch currentProjectMembership {
        case let .assigned(_, _, name):
            if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                return name
            }
            return L10n.text(.projectNameUntitled)
        case .none:
            return L10n.text(.projectNameNotInProject)
        case .unknown:
            return L10n.text(.projectNameInfoUnavailable)
        }
    }

    private var candidateProjectName: String? {
        guard let candidate = model.newTaskProjectCandidate else { return nil }
        if let name = candidate.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        let folderName = URL(fileURLWithPath: candidate.rootPath).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folderName.isEmpty ? L10n.text(.projectNameUntitled) : folderName
    }

    private var newTaskProjectIsConfirmedReadOnly: Bool {
        model.selection?.kind == .newTask && model.canUseProjectNote
    }

    private var currentProjectMembership: CodexProjectMembership {
        model.metadata?.projectMembership ?? .unknown
    }

    private var hasProjectPath: Bool {
        guard let cwd = model.metadata?.cwd.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !cwd.isEmpty
    }

    private func scopeProgressIdentity(_ scope: NoteScope) -> String {
        let selectionKey = model.selection?.stableKey ?? "unbound"
        if scope == .project {
            return "\(selectionKey):project:\(model.metadata?.cwd ?? "unavailable")"
        }
        return "\(selectionKey):task"
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if model.isNewTaskProjectReadOnly {
                HStack(spacing: 7) {
                    Image(systemName: "eye")
                        .accessibilityHidden(true)
                    Text(L10n.text(.editorNewTaskProjectReadOnlyBanner))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(palette.secondaryText.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(palette.panelBackground.color)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(palette.separator.color)
                        .frame(height: 0.7)
                }
                .accessibilityLabel(
                    Text(L10n.text(.editorNewTaskProjectReadOnlyAccessibilityLabel))
                )
                .accessibilityValue(
                    Text(L10n.text(.editorNewTaskProjectReadOnlyAccessibilityValue))
                )
            }

            ZStack(alignment: .topLeading) {
                PlainMarkdownTextView(
                    controller: editorController,
                    text: Binding(
                        get: { model.noteText },
                        set: { model.noteText = $0 }
                    ),
                    documentIdentity: model.activeDocument.map(
                        MarkdownEditorDocumentIdentity.init(document:)
                    ),
                    isEditable: model.canEdit,
                    fontSize: CGFloat(
                        EditorFontSizePreference.normalized(storedEditorFontSize)
                    ),
                    lineSpacing: CGFloat(
                        EditorLineSpacingPreference.normalized(storedEditorLineSpacing)
                    ),
                    appearanceID: activeTheme.rawValue,
                    backgroundColor: palette.editorBackground.nsColor,
                    textColor: palette.primaryText.nsColor,
                    disabledTextColor: palette.secondaryText.nsColor,
                    insertionPointColor: palette.accent.nsColor,
                    selectionBackgroundColor: palette.textSelection.nsColor,
                    selectionTextColor: palette.selectionText.nsColor,
                    selectionToolbarBackgroundColor: palette.panelBackground.nsColor,
                    selectionToolbarForegroundColor: palette.primaryText.nsColor,
                    selectionToolbarAccentColor: palette.accent.nsColor,
                    selectionToolbarHoverColor: palette.selectedBackground.nsColor,
                    selectionToolbarSelectionColor: palette.textSelection.nsColor,
                    selectionToolbarBorderColor: palette.separator.nsColor,
                    successColor: palette.success.nsColor,
                    checkboxCheckmarkColor: palette.editorBackground.nsColor,
                    checkboxHoverBackgroundColor: palette.selectedBackground.nsColor,
                    selectionMoveConfiguration: selectionMoveConfiguration,
                    imageConfiguration: model.activeDocument.map { document in
                        EditorImageConfiguration(
                            documentIdentity: MarkdownEditorDocumentIdentity(
                                document: document
                            ),
                            store: model.noteImageStore,
                            isEnabled: model.canEdit,
                            reportError: { message in
                                model.presentImageImportError(message)
                            }
                        )
                    },
                    languageRevision: languageRevision
                )

                if model.noteText.isEmpty, model.canEdit {
                    let prompt = EmptyNotePromptPresentation(model.selectedScope)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(prompt.title)
                        Text(prompt.shortcutHint)
                            .font(.caption.monospaced())
                    }
                    .foregroundStyle(palette.tertiaryText.color)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .allowsHitTesting(false)
                }

                if !model.canEdit, !model.isNewTaskProjectReadOnly {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.trianglebadge.exclamationmark")
                            .font(.title2)
                        Text(L10n.text(.editorUnboundTitle))
                            .font(.subheadline.weight(.semibold))
                        Text(L10n.text(.editorUnboundMessage))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText.color)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.editorBackground.color.opacity(0.94))
                }

                if let notice = model.selectionMoveNotice {
                    selectionMoveNoticeView(notice)
                        .id(notice.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.18),
            value: model.selectionMoveNotice
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.editorBackground.color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.separator.color, lineWidth: 0.7)
        )
    }

    private var bottomBar: some View {
        HStack(spacing: BottomBarActionMetrics.barSpacing) {
            todoProgressStatus
                .layoutPriority(1)

            Spacer(minLength: 6)

            bottomBarActionGroup

            statusGroup
                .layoutPriority(statusGroupRequiresText ? 3 : 1)
        }
        .frame(maxWidth: .infinity)
        .font(.caption)
    }

    private var bottomBarActionGroup: some View {
        HStack(spacing: BottomBarActionMetrics.interItemSpacing) {
            notesFolderButton
            shortcutReferenceButton
            settingsButton
        }
        .padding(.horizontal, BottomBarActionMetrics.groupHorizontalPadding)
        .padding(.vertical, BottomBarActionMetrics.groupVerticalPadding)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var notesFolderButton: some View {
        let presentation = BottomBarActionPresentation.files

        return Button {
            do {
                try model.noteStore.ensureRootDirectory()
                NSWorkspace.shared.open(model.noteStore.rootURL)
            } catch {
                NSSound.beep()
            }
        } label: {
            BottomBarActionLabel(presentation: presentation)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.secondaryText.color)
        .modifier(
            BottomBarActionHoverModifier(
                backgroundColor: palette.selectedBackground.color
            )
        )
        .help(presentation.helpText)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private var settingsButton: some View {
        let availableVersion = updateCoordinator.availableUpdate?.version
        let presentation = BottomBarActionPresentation.settings(
            updateVersion: availableVersion
        )

        return SettingsLink {
            ZStack(alignment: .topTrailing) {
                BottomBarActionLabel(presentation: presentation)
                if availableVersion != nil {
                    Circle()
                        .fill(palette.accent.color)
                        .frame(width: 6, height: 6)
                        .padding(4)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(palette.secondaryText.color)
        .modifier(
            BottomBarActionHoverModifier(
                backgroundColor: palette.selectedBackground.color
            )
        )
        .help(presentation.helpText)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private var todoProgressStatus: some View {
        let presentation = TodoStatusPresentation(model.checklistProgress)

        return ViewThatFits(in: .horizontal) {
            todoProgressBadge(
                title: presentation.wideTitle,
                systemImage: presentation.systemImage,
                isComplete: presentation.isComplete
            )
            todoProgressBadge(
                title: presentation.compactTitle,
                systemImage: presentation.systemImage,
                isComplete: presentation.isComplete
            )
            todoProgressBadge(
                title: presentation.minimalTitle,
                systemImage: presentation.systemImage,
                isComplete: presentation.isComplete
            )
        }
        .help(
            L10n.text(
                .todoHelp,
                replacements: [
                    "scope": model.selectedScope.displayName,
                    "value": presentation.accessibilityValue,
                ]
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                L10n.text(
                    .todoAccessibilityLabel,
                    replacements: ["scope": model.selectedScope.displayName]
                )
            )
        )
        .accessibilityValue(Text(presentation.accessibilityValue))
    }

    private func todoProgressBadge(
        title: String,
        systemImage: String,
        isComplete: Bool
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14, height: 14)
                .foregroundStyle(
                    isComplete ? palette.success.color : palette.secondaryText.color
                )
                .accessibilityHidden(true)

            Text(title)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(palette.secondaryText.color)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var shortcutReferenceButton: some View {
        let presentation = BottomBarActionPresentation.shortcuts

        return Button {
            isShortcutReferencePresented.toggle()
        } label: {
            BottomBarActionLabel(presentation: presentation)
        }
        .buttonStyle(.borderless)
        .frame(
            minWidth: BottomBarActionMetrics.minimumHitSize,
            minHeight: BottomBarActionMetrics.minimumHitSize
        )
        .contentShape(Rectangle())
        .tint(palette.secondaryText.color)
        .foregroundStyle(palette.secondaryText.color)
        .modifier(
            BottomBarActionHoverModifier(
                backgroundColor: palette.selectedBackground.color
            )
        )
        .help(presentation.helpText)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
        .popover(
            isPresented: $isShortcutReferencePresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            ShortcutReferencePanel(
                presentation: .standard(
                    globalHotKeyDisplayName: globalHotKeyDisplayName
                ),
                palette: palette,
                languageRevision: languageRevision
            )
            .focusable(false)
            .presentationBackground(palette.windowBackground.color)
        }
    }

    private var selectionMoveDestinationScope: NoteScope {
        model.selectedScope == .task ? .project : .task
    }

    private var selectionMoveDestinationName: String {
        switch selectionMoveDestinationScope {
        case .task:
            return currentTaskName
        case .project:
            return currentProjectName
        }
    }

    private var selectionMoveMenuTitle: String {
        if selectionMoveDestinationScope == .project,
           model.selection?.kind == .newTask,
           (model.newTaskProjectCandidate != nil || model.canUseProjectNote) {
            return L10n.text(.moveSelectionDisabledProjectReadOnly)
        }
        if selectionMoveDestinationScope == .project, !model.canUseProjectNote {
            return L10n.text(.moveSelectionDisabledNoProjectNote)
        }
        return L10n.text(
            .moveSelectionActionToEnd,
            replacements: [
                "scope": selectionMoveDestinationScope.displayName,
                "name": selectionMoveDestinationName,
            ]
        )
    }

    private var selectionMovePillTitle: String {
        L10n.text(
            .moveSelectionActionToScope,
            replacements: ["scope": selectionMoveDestinationScope.displayName]
        )
    }

    private var selectionMoveConfiguration: EditorSelectionMoveConfiguration? {
        guard let sourceDocument = model.activeDocument,
              sourceDocument.scope == model.selectedScope,
              let currentSelection = model.selection
        else { return nil }

        let destinationScope = selectionMoveDestinationScope
        let destinationDocument: NoteDocument
        switch destinationScope {
        case .task:
            destinationDocument = model.noteStore.taskDocument(
                selection: currentSelection,
                metadata: model.metadata
            )
        case .project:
            guard let projectDocument = try? model.noteStore.projectDocument(
                selection: currentSelection,
                metadata: model.metadata
            ) else { return nil }
            destinationDocument = projectDocument
        }

        let expectedSelectionStableKey = currentSelection.stableKey
        let isEnabled = model.canEdit
            && (destinationScope != .project || model.canWriteProjectNote)
        return EditorSelectionMoveConfiguration(
            sourceDocument: sourceDocument,
            destinationDocument: destinationDocument,
            selectionStableKey: expectedSelectionStableKey,
            title: selectionMovePillTitle,
            isEnabled: isEnabled,
            disabledReason: isEnabled ? nil : selectionMoveMenuTitle
        ) { snapshot in
            guard let result = model.moveSelection(
                snapshot,
                to: destinationScope,
                expectedSelectionStableKey: expectedSelectionStableKey
            ) else {
                return
            }
            editorController.setPendingSelectionAfterExternalTextUpdate(
                result.sourceCaretRange,
                scrollToVisible: true
            )
        }
    }

    private func selectionMoveNoticeView(_ notice: SelectionMoveNotice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(palette.success.color)
                .accessibilityHidden(true)

            Text(
                L10n.text(
                    .moveSelectionNoticeMoved,
                    replacements: [
                        "scope": notice.destinationScope.displayName,
                        "name": notice.destinationName,
                    ]
                )
            )
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(palette.primaryText.color)

            Spacer(minLength: 4)

            if notice.canUndo {
                Button(L10n.text(.commonActionUndo)) {
                    undoSelectionMove()
                }
                .buttonStyle(.link)
            }

            if notice.canViewDestination {
                Button(L10n.text(.commonActionView)) {
                    viewSelectionMoveDestination()
                }
                .buttonStyle(.link)
            }

            Button {
                model.dismissSelectionMoveNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(palette.secondaryText.color)
            .help(L10n.text(.moveSelectionNoticeDismissHelp))
            .accessibilityLabel(
                Text(L10n.text(.moveSelectionNoticeDismissAccessibilityLabel))
            )
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            palette.panelBackground.color.opacity(0.97),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(palette.separator.color, lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .accessibilityElement(children: .contain)
        .onHover { isHovered in
            model.setSelectionMoveNoticeHovered(isHovered, for: notice.id)
        }
        .onDisappear {
            model.setSelectionMoveNoticeHovered(false, for: notice.id)
        }
    }

    private func undoSelectionMove() {
        guard let result = model.undoLastSelectionMove() else { return }
        if model.selectedScope == result.sourceDocument.scope {
            editorController.setPendingSelectionAfterExternalTextUpdate(
                NSRange(
                    location: result.sourceCaretRange.location,
                    length: (result.movedText as NSString).length
                ),
                scrollToVisible: true
            )
        } else {
            editorController.setPendingCaretAfterExternalTextUpdate(
                atUTF16Offset: result.destinationInsertedRange.location,
                scrollToVisible: true
            )
        }
    }

    private func viewSelectionMoveDestination() {
        guard let insertedRange = model.viewSelectionMoveDestination() else { return }
        editorController.setPendingCaretAfterExternalTextUpdate(
            atUTF16Offset: NSMaxRange(insertedRange),
            scrollToVisible: true
        )
    }

    private func shortcut(for scope: NoteScope) -> CodexNotesShortcutSpec {
        switch scope {
        case .task:
            return CodexNotesShortcut.taskNote
        case .project:
            return CodexNotesShortcut.projectNote
        }
    }

    @ViewBuilder
    private var statusGroup: some View {
        if connectionStatusRequiresText && saveBadgePresentation.requiresText {
            fullStatusGroup
        } else if connectionStatusRequiresText {
            connectionTextStatusGroup
        } else if saveBadgePresentation.requiresText {
            compactConnectionStatusGroup
        } else {
            ViewThatFits(in: .horizontal) {
                fullStatusGroup
                compactConnectionStatusGroup
                iconOnlyStatusGroup
            }
        }
    }

    private var fullStatusGroup: some View {
        HStack(spacing: 8) {
            accessibleConnectionBadge(connectionBadgeWithText)
            statusSeparator
            accessibleSaveBadge(saveBadgeWithText)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var connectionTextStatusGroup: some View {
        HStack(spacing: 8) {
            accessibleConnectionBadge(connectionBadgeWithText)
            statusSeparator
            accessibleSaveBadge(saveStatusIcon)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var compactConnectionStatusGroup: some View {
        HStack(spacing: 8) {
            accessibleConnectionBadge(connectionStatusIcon)
            statusSeparator
            accessibleSaveBadge(saveBadgeWithText)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var iconOnlyStatusGroup: some View {
        HStack(spacing: 8) {
            accessibleConnectionBadge(connectionStatusIcon)
            statusSeparator
            accessibleSaveBadge(saveStatusIcon)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var statusSeparator: some View {
        Rectangle()
            .fill(palette.separator.color.opacity(0.72))
            .frame(width: 1, height: 12)
            .accessibilityHidden(true)
    }

    private var statusGroupRequiresText: Bool {
        connectionStatusRequiresText || saveBadgePresentation.requiresText
    }

    private func accessibleConnectionBadge<Badge: View>(_ badge: Badge) -> some View {
        badge
            .help(connectionStatusHelp)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.text(.connectionAccessibilityLabel)))
            .accessibilityValue(Text(connectionStatusAccessibilityValue))
            .layoutPriority(connectionStatusRequiresText ? 2 : 0)
    }

    private var connectionBadgeWithText: some View {
        HStack(spacing: 4) {
            connectionStatusIcon
            Text(connectionStatusText)
                .lineLimit(1)
                .foregroundStyle(connectionStatusTextColor)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var connectionStatusIcon: some View {
        Group {
            switch model.state {
            case .starting:
                ProgressView()
                    .controlSize(.mini)
            case .detected:
                Image(systemName: "circle.fill")
                    .font(.system(size: 8, weight: .semibold))
            case .newTask:
                Image(systemName: "circle.fill")
                    .font(.system(size: 8, weight: .semibold))
            case .unavailable:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .frame(width: 12, height: 12)
        .foregroundStyle(connectionStatusColor)
        .tint(connectionStatusColor)
        .accessibilityHidden(true)
    }

    private var connectionStatusColor: Color {
        switch model.state {
        case .starting:
            palette.secondaryText.color
        case .detected:
            palette.success.color
        case .newTask, .unavailable:
            palette.warning.color
        }
    }

    private var connectionStatusTextColor: Color {
        if case .unavailable = model.state {
            return palette.warning.color
        }
        return palette.secondaryText.color
    }

    private var connectionStatusRequiresText: Bool {
        if case .unavailable = model.state {
            return true
        }
        return false
    }

    private var connectionStatusHelp: String {
        switch model.state {
        case .starting:
            return L10n.text(.connectionHelpDetecting)
        case .detected:
            return L10n.text(
                .connectionHelpFollowing,
                replacements: ["task": currentTaskName]
            )
        case .newTask:
            return L10n.text(.connectionHelpNewTask)
        case let .unavailable(message):
            return L10n.text(
                .connectionHelpPaused,
                replacements: ["message": message]
            )
        }
    }

    private var connectionStatusAccessibilityValue: String {
        switch model.state {
        case .starting:
            return L10n.text(.connectionStatusDetecting)
        case .detected:
            return L10n.text(
                .connectionAccessibilityFollowing,
                replacements: ["task": currentTaskName]
            )
        case .newTask:
            return L10n.text(.connectionAccessibilityNewTask)
        case let .unavailable(message):
            return L10n.text(
                .connectionAccessibilityPaused,
                replacements: ["message": message]
            )
        }
    }

    private var saveBadgePresentation: SaveBadgePresentation {
        SaveBadgePresentation(model.saveState)
    }

    private var saveBadgeWithText: some View {
        HStack(spacing: 4) {
            saveStatusIcon
            Text(saveBadgePresentation.title)
                .lineLimit(1)
                .foregroundStyle(saveStatusTextColor)
                .frame(minWidth: 44, alignment: .leading)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var saveStatusIcon: some View {
        Image(systemName: saveBadgePresentation.systemImage)
            .font(.system(size: saveBadgePresentation.iconSize, weight: .semibold))
            .frame(width: 12, height: 12)
            .foregroundStyle(saveStatusIconColor)
            .accessibilityHidden(true)
    }

    private var saveStatusIconColor: Color {
        statusColor(for: saveBadgePresentation.iconTone)
    }

    private var saveStatusTextColor: Color {
        statusColor(for: saveBadgePresentation.textTone)
    }

    private func statusColor(for tone: SaveBadgePresentation.Tone) -> Color {
        switch tone {
        case .neutral:
            return palette.secondaryText.color
        case .success:
            return palette.success.color
        case .failure:
            return palette.error.color
        }
    }

    private func accessibleSaveBadge<Badge: View>(_ badge: Badge) -> some View {
        badge
            .help(saveBadgePresentation.helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.text(.saveAccessibilityLabel)))
            .accessibilityValue(Text(saveBadgePresentation.accessibilityValue))
            .layoutPriority(saveBadgePresentation.requiresText ? 2 : 0)
    }

    private var currentTaskName: String {
        if case .newTask = model.state {
            return L10n.text(.taskNameNewTask)
        }
        if let name = model.metadata?.name { return name }
        switch model.state {
        case .starting: return L10n.text(.taskNameDetecting)
        case .newTask: return L10n.text(.taskNameNewTask)
        case .detected:
            return model.selection?.hostID == nil
                ? L10n.text(.taskNameCurrent)
                : L10n.text(.taskNameRemote)
        case .unavailable: return L10n.text(.taskNameUnavailable)
        }
    }

}

struct EmptyNotePromptPresentation: Equatable {
    let title: String
    let shortcutHint: String

    init(_ scope: NoteScope) {
        switch scope {
        case .task:
            title = L10n.text(.emptyNoteTaskPrompt)
            shortcutHint = L10n.text(.emptyNoteTaskShortcutHint)
        case .project:
            title = L10n.text(.emptyNoteProjectPrompt)
            shortcutHint = L10n.text(.emptyNoteProjectTodoExample)
        }
    }
}

struct TodoStatusPresentation: Equatable {
    let wideTitle: String
    let compactTitle: String
    let minimalTitle: String
    let systemImage: String
    let accessibilityValue: String
    let isComplete: Bool

    init(_ progress: MarkdownChecklistProgress) {
        isComplete = progress.total > 0 && progress.completed >= progress.total

        if progress.total == 0 {
            wideTitle = L10n.text(.todoBadgeEmpty)
            compactTitle = L10n.text(.todoBadgeEmpty)
            minimalTitle = L10n.text(.todoBadgeMinimal)
            systemImage = "checklist"
            accessibilityValue = L10n.text(.todoBadgeEmpty)
        } else {
            let replacements = [
                "completed": String(progress.completed),
                "total": String(progress.total),
            ]
            wideTitle = L10n.text(.todoBadgeProgressWide, replacements: replacements)
            compactTitle = L10n.text(.todoBadgeProgressCompact, replacements: replacements)
            minimalTitle = "\(progress.completed)/\(progress.total)"
            systemImage = isComplete ? "checkmark.circle.fill" : "checklist"
            accessibilityValue = L10n.text(
                .todoAccessibilityProgress,
                replacements: replacements
            )
        }
    }
}

struct SaveBadgePresentation: Equatable {
    enum Tone: Equatable {
        case neutral
        case success
        case failure
    }

    let title: String
    let systemImage: String
    let iconSize: CGFloat
    let iconTone: Tone
    let textTone: Tone
    let helpText: String
    let accessibilityValue: String
    let requiresText: Bool

    init(_ state: ProbeViewModel.SaveState) {
        switch state {
        case .idle:
            title = L10n.text(.saveStatusIdleTitle)
            systemImage = "circle"
            iconSize = 8
            iconTone = .neutral
            textTone = .neutral
            helpText = L10n.text(.saveStatusIdleHelp)
            accessibilityValue = L10n.text(.saveStatusIdleTitle)
            requiresText = false
        case .saving:
            title = L10n.text(.saveStatusSavingTitle)
            systemImage = "arrow.clockwise"
            iconSize = 10
            iconTone = .neutral
            textTone = .neutral
            helpText = L10n.text(.saveStatusSavingHelp)
            accessibilityValue = L10n.text(.saveStatusSavingTitle)
            requiresText = false
        case .saved:
            title = L10n.text(.saveStatusSavedTitle)
            systemImage = "checkmark"
            iconSize = 10
            iconTone = .success
            textTone = .neutral
            helpText = L10n.text(.saveStatusSavedHelp)
            accessibilityValue = L10n.text(.saveStatusSavedTitle)
            requiresText = false
        case let .failed(message):
            title = L10n.text(.saveStatusFailedTitle)
            systemImage = "exclamationmark.circle.fill"
            iconSize = 11
            iconTone = .failure
            textTone = .failure
            helpText = L10n.text(
                .saveStatusFailedHelp,
                replacements: ["message": message]
            )
            accessibilityValue = L10n.text(
                .saveStatusFailedAccessibilityValue,
                replacements: ["message": message]
            )
            requiresText = true
        }
    }
}

struct BottomBarActionPresentation: Equatable {
    let systemImage: String
    let helpText: String
    let accessibilityLabel: String

    static var files: BottomBarActionPresentation {
        let label = L10n.text(.bottomBarFilesHelp)
        return BottomBarActionPresentation(
            systemImage: "folder",
            helpText: label,
            accessibilityLabel: label
        )
    }

    static var shortcuts: BottomBarActionPresentation {
        let label = L10n.text(.bottomBarShortcutsHelp)
        return BottomBarActionPresentation(
            systemImage: "keyboard",
            helpText: label,
            accessibilityLabel: label
        )
    }

    static var settings: BottomBarActionPresentation {
        settings(updateVersion: nil)
    }

    static func settings(updateVersion: String?) -> BottomBarActionPresentation {
        let label: String
        if let updateVersion {
            label = L10n.text(
                .bottomBarSettingsUpdateAvailableHelp,
                replacements: ["version": updateVersion]
            )
        } else {
            label = L10n.text(.bottomBarSettingsHelp)
        }
        return BottomBarActionPresentation(
            systemImage: "gearshape",
            helpText: label,
            accessibilityLabel: label
        )
    }
}

struct AppUpdateBannerPresentation: Equatable {
    let title: String
    let viewTitle: String
    let laterTitle: String
    let viewAccessibilityHint: String

    init(_ update: AvailableAppUpdate) {
        title = L10n.text(
            .appUpdateBannerAvailable,
            replacements: ["version": update.version]
        )
        viewTitle = L10n.text(.settingsAboutViewUpdate)
        laterTitle = L10n.text(.appUpdateBannerLater)
        viewAccessibilityHint = L10n.text(.settingsAboutViewUpdateAccessibilityHint)
    }
}

struct ShortcutReferenceItem: Equatable, Identifiable {
    enum ID: String {
        case toggleCodexNotes
        case cycleTodo
        case taskNote
        case projectNote
        case bold
        case highlight
    }

    let id: ID
    let title: String
    let shortcut: String
}

struct ShortcutReferenceSection: Equatable, Identifiable {
    let title: String
    let items: [ShortcutReferenceItem]
    var note: String? = nil

    var id: String { title }
}

struct ShortcutReferencePresentation: Equatable {
    let title: String
    let sections: [ShortcutReferenceSection]

    var items: [ShortcutReferenceItem] {
        sections.flatMap(\.items)
    }

    var isInteractive: Bool { false }

    static var standard: ShortcutReferencePresentation {
        standard(globalHotKeyDisplayName: nil)
    }

    static func standard(
        globalHotKeyDisplayName: String?
    ) -> ShortcutReferencePresentation {
        let normalizedGlobalHotKeyDisplayName = globalHotKeyDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayedGlobalHotKey = normalizedGlobalHotKeyDisplayName.flatMap {
            $0.isEmpty ? nil : $0
        } ?? L10n.text(.globalHotKeyNotSet)

        return ShortcutReferencePresentation(
            title: L10n.text(.shortcutsTitle),
            sections: [
                ShortcutReferenceSection(
                    title: L10n.text(.shortcutsSectionGlobal),
                    items: [
                        ShortcutReferenceItem(
                            id: .toggleCodexNotes,
                            title: L10n.text(.shortcutsItemToggleCodexNotes),
                            shortcut: displayedGlobalHotKey
                        )
                    ],
                    note: L10n.text(.shortcutsGlobalAvailabilityNote)
                ),
                ShortcutReferenceSection(
                    title: L10n.text(.shortcutsSectionTodos),
                    items: [
                        ShortcutReferenceItem(
                            id: .cycleTodo,
                            title: L10n.text(.shortcutsItemToggleCurrentLineTodo),
                            shortcut: CodexNotesShortcut.cycleTodo.displayName
                        )
                    ]
                ),
                ShortcutReferenceSection(
                    title: L10n.text(.shortcutsSectionNotes),
                    items: [
                        ShortcutReferenceItem(
                            id: .taskNote,
                            title: L10n.text(.shortcutsItemTaskNote),
                            shortcut: CodexNotesShortcut.taskNote.displayName
                        ),
                        ShortcutReferenceItem(
                            id: .projectNote,
                            title: L10n.text(.shortcutsItemProjectNote),
                            shortcut: CodexNotesShortcut.projectNote.displayName
                        )
                    ]
                ),
                ShortcutReferenceSection(
                    title: L10n.text(.shortcutsSectionFormatting),
                    items: [
                        ShortcutReferenceItem(
                            id: .bold,
                            title: L10n.text(.shortcutsItemBoldSelection),
                            shortcut: "⌘B"
                        ),
                        ShortcutReferenceItem(
                            id: .highlight,
                            title: L10n.text(.shortcutsItemHighlightSelection),
                            shortcut: "⌘⇧H"
                        )
                    ]
                )
            ]
        )
    }
}

enum ShortcutReferencePanelMetrics {
    static let width: CGFloat = 260
    static let rowHeight: CGFloat = 28
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12
}

enum ShortcutReferenceEscapeKeyPolicy {
    static let escapeKeyCode: UInt16 = 53

    static func shouldDismiss(for event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.keyCode == escapeKeyCode
        else { return false }
        let disallowedModifiers: NSEvent.ModifierFlags = [
            .command,
            .control,
            .option,
            .shift,
        ]
        return event.modifierFlags.intersection(disallowedModifiers).isEmpty
    }
}

@MainActor
final class ShortcutReferenceEscapeMonitorController {
    private var eventMonitor: Any?
    private var isPresented = false
    private var dismiss: () -> Void = {}

    func update(isPresented: Bool, dismiss: @escaping () -> Void) {
        self.isPresented = isPresented
        self.dismiss = dismiss
        if isPresented {
            installIfNeeded()
        } else {
            removeMonitor()
        }
    }

    func invalidate() {
        isPresented = false
        removeMonitor()
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard isPresented,
              ShortcutReferenceEscapeKeyPolicy.shouldDismiss(for: event)
        else { return event }

        // Flip the controller state before updating SwiftUI so a second Escape
        // received during the dismissal render can never reopen or redismiss it.
        isPresented = false
        dismiss()
        return nil
    }

    private func installIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handle(event) ?? event
        }
    }

    private func removeMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}

struct ShortcutReferenceEscapeMonitorView: NSViewRepresentable {
    let isPresented: Bool
    let dismiss: () -> Void

    func makeCoordinator() -> ShortcutReferenceEscapeMonitorController {
        ShortcutReferenceEscapeMonitorController()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(
            isPresented: isPresented,
            dismiss: dismiss
        )
    }

    static func dismantleNSView(
        _ nsView: NSView,
        coordinator: ShortcutReferenceEscapeMonitorController
    ) {
        coordinator.invalidate()
    }
}

struct ShortcutReferencePanel: View {
    let presentation: ShortcutReferencePresentation
    let palette: NoteThemePalette
    var languageRevision: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(presentation.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.primaryText.color)
                .padding(.bottom, 9)

            Divider()
                .overlay(palette.separator.color)

            ForEach(Array(presentation.sections.enumerated()), id: \.element.id) {
                sectionIndex,
                section in
                if sectionIndex > 0 {
                    Divider()
                        .overlay(palette.separator.color)
                        .padding(.top, 5)
                }

                Text(section.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.tertiaryText.color)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)

                ForEach(section.items) { item in
                    HStack(spacing: 12) {
                        Text(item.title)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.primaryText.color)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(item.shortcut)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.secondaryText.color)
                            .lineLimit(1)
                    }
                    .frame(height: ShortcutReferencePanelMetrics.rowHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        Text(
                            L10n.text(
                                .shortcutsItemAccessibilityLabel,
                                replacements: [
                                    "title": item.title,
                                    "shortcut": item.shortcut,
                                ]
                            )
                        )
                    )
                }

                if let note = section.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.tertiaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                }
            }

            Text(L10n.text(.shortcutsFormattingRequiresSelection))
                .font(.system(size: 10))
                .foregroundStyle(palette.tertiaryText.color)
                .padding(.top, 7)
        }
        .padding(.horizontal, ShortcutReferencePanelMetrics.horizontalPadding)
        .padding(.vertical, ShortcutReferencePanelMetrics.verticalPadding)
        .frame(width: ShortcutReferencePanelMetrics.width)
        .background {
            ZStack {
                palette.windowBackground.color
                palette.panelBackground.color
            }
        }
        .accessibilityElement(children: .contain)
    }
}

enum ScopeSelectionIndicatorMetrics {
    static let diameter: CGFloat = 6
    static let edgeInset: CGFloat = 8
}

enum BottomBarActionMetrics {
    static let minimumWindowWidth: CGFloat = 340
    static let horizontalContentInset: CGFloat = 16
    static let topContentInset: CGFloat = 16
    static let minimumHitSize: CGFloat = 28
    static let interItemSpacing: CGFloat = 2
    static let groupHorizontalPadding: CGFloat = 2
    static let groupVerticalPadding: CGFloat = 0
    static let editorSpacing: CGFloat = 8
    static let bottomPadding: CGFloat = 12
    static let hoverCornerRadius: CGFloat = 6
    static let hoverBackgroundOpacity = 0.72
    static let barSpacing: CGFloat = 8

    static var baselineVerticalFootprint: CGFloat {
        editorSpacing
            + minimumHitSize
            + 2 * groupVerticalPadding
            + bottomPadding
    }

    static var minimumInnerWidth: CGFloat {
        minimumWindowWidth - 2 * horizontalContentInset
    }

    static var actionGroupMinimumWidth: CGFloat {
        3 * minimumHitSize
            + 2 * interItemSpacing
            + 2 * groupHorizontalPadding
    }
}

private struct BottomBarActionLabel: View {
    let presentation: BottomBarActionPresentation

    var body: some View {
        ZStack {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        }
        .frame(
            minWidth: BottomBarActionMetrics.minimumHitSize,
            minHeight: BottomBarActionMetrics.minimumHitSize
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }
}

private struct BottomBarActionHoverModifier: ViewModifier {
    let backgroundColor: Color

    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(
                    cornerRadius: BottomBarActionMetrics.hoverCornerRadius,
                    style: .continuous
                )
                .fill(backgroundColor)
                .opacity(isHovered ? BottomBarActionMetrics.hoverBackgroundOpacity : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onHover { hovering in
                isHovered = hovering
            }
            .onDisappear {
                isHovered = false
            }
    }
}

private struct ChecklistProgressRing: View {
    let progress: MarkdownChecklistProgress
    let trackColor: Color
    let progressColor: Color
    let successColor: Color
    let checkmarkColor: Color
    let reduceMotion: Bool

    private var isComplete: Bool {
        progress.total > 0 && progress.completed >= progress.total
    }

    private var fraction: Double {
        guard progress.total > 0 else { return 0 }
        return min(max(Double(progress.completed) / Double(progress.total), 0), 1)
    }

    var body: some View {
        ZStack {
            if isComplete {
                Circle()
                    .fill(successColor)

                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(checkmarkColor)
            } else {
                ProgressPieSlice(fraction: fraction)
                    .fill(progressColor)
                    .padding(2.5)

                Circle()
                    .strokeBorder(trackColor, lineWidth: 1.5)
            }
        }
        .frame(width: 13, height: 13)
        .fixedSize()
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.2),
            value: progress
        )
        .accessibilityHidden(true)
    }
}

private struct ProgressPieSlice: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let normalizedFraction = min(max(fraction, 0), 1)
        guard normalizedFraction > 0 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * normalizedFraction),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

struct WindowConfigurator: NSViewRepresentable {
    let appearanceName: NSAppearance.Name?
    let backgroundColor: NSColor
    let languageRevision: String

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var window: NSWindow?
        private var activationObserver: NSObjectProtocol?
        private var toggleWindowObserver: NSObjectProtocol?
        private var showWindowObserver: NSObjectProtocol?
        private var restoreDefaultSizeObserver: NSObjectProtocol?
        private var framePersistenceObservers: [NSObjectProtocol] = []
        private weak var originalWindowDelegate: NSWindowDelegate?
        private var visibilityState = MainWindowVisibilityState()
        private var codexActivationTimeoutWorkItem: DispatchWorkItem?
        private let codexAvailabilityMonitor: CodexApplicationAvailabilityObserving
        private let closeButtonHoverHintController = CloseButtonHoverHintController()
        private var appliedLanguageRevision: String?
        private var isInvalidated = false

        init(
            codexAvailabilityMonitor: CodexApplicationAvailabilityObserving? = nil
        ) {
            self.codexAvailabilityMonitor = codexAvailabilityMonitor
                ?? CodexApplicationAvailabilityMonitor()
            super.init()
        }

        func attach(to window: NSWindow, languageRevision: String) {
            guard !isInvalidated,
                  window.identifier == CodexNotesWindowIdentifier.main else { return }
            if self.window === window {
                refreshLocalizationIfNeeded(
                    for: window,
                    languageRevision: languageRevision
                )
                refreshCloseButtonHoverHint(for: window)
                return
            }
            if self.window != nil {
                detach()
            }
            self.window = window
            originalWindowDelegate = window.delegate
            window.delegate = self
            codexAvailabilityMonitor.start { [weak self] isAvailable in
                self?.codexAvailabilityDidChange(isAvailable)
            }
            if activationObserver == nil {
                activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                    MainActor.assumeIsolated {
                        self?.applicationDidActivate(application)
                    }
                }
            }
            if toggleWindowObserver == nil {
                toggleWindowObserver = NotificationCenter.default.addObserver(
                    forName: MainWindowCommandNotification.toggle,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.toggleFromStatusItem()
                    }
                }
            }
            if showWindowObserver == nil {
                showWindowObserver = NotificationCenter.default.addObserver(
                    forName: MainWindowCommandNotification.show,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.showFromCommand()
                    }
                }
            }
            if restoreDefaultSizeObserver == nil {
                restoreDefaultSizeObserver = NotificationCenter.default.addObserver(
                    forName: MainWindowCommandNotification.restoreDefaultSize,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.restoreDefaultWindowSize()
                    }
                }
            }
            installFramePersistenceObservers(for: window)
            appliedLanguageRevision = languageRevision
            refreshCloseButtonHoverHint(for: window)
            updateVisibility(frontmostApplication: NSWorkspace.shared.frontmostApplication)
        }

        func invalidate() {
            guard !isInvalidated else { return }
            isInvalidated = true
            detach()
        }

        func detach() {
            closeButtonHoverHintController.detach()
            cancelCodexActivationTimeout()
            codexAvailabilityMonitor.stop()
            if let activationObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            }
            activationObserver = nil
            if let toggleWindowObserver {
                NotificationCenter.default.removeObserver(toggleWindowObserver)
            }
            toggleWindowObserver = nil
            if let showWindowObserver {
                NotificationCenter.default.removeObserver(showWindowObserver)
            }
            showWindowObserver = nil
            if let restoreDefaultSizeObserver {
                NotificationCenter.default.removeObserver(
                    restoreDefaultSizeObserver
                )
            }
            restoreDefaultSizeObserver = nil
            if let window {
                MainWindowFramePersistence.persistIfVisible(window: window)
            }
            framePersistenceObservers.forEach(
                NotificationCenter.default.removeObserver
            )
            framePersistenceObservers.removeAll()
            if window?.delegate === self {
                window?.delegate = originalWindowDelegate
            }
            originalWindowDelegate = nil
            window = nil
            appliedLanguageRevision = nil
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            hideMainWindow(sender)
            NotificationCenter.default.post(
                name: MainWindowCommandNotification.hiddenUsingCloseButton,
                object: sender
            )
            return false
        }

        func refreshCloseButtonHoverHint(for window: NSWindow) {
            guard !isInvalidated, self.window === window else { return }
            guard window.identifier == CodexNotesWindowIdentifier.main,
                  let closeButton = window.standardWindowButton(.closeButton) else {
                closeButtonHoverHintController.detach()
                return
            }
            closeButtonHoverHintController.attach(to: closeButton, in: window)
        }

        func refreshLocalizationIfNeeded(
            for window: NSWindow,
            languageRevision: String
        ) {
            guard !isInvalidated,
                  self.window === window,
                  appliedLanguageRevision != languageRevision else { return }
            appliedLanguageRevision = languageRevision
            closeButtonHoverHintController.cancelAndDismiss()
        }

        func windowShouldZoom(
            _ window: NSWindow,
            toFrame newFrame: NSRect
        ) -> Bool {
            MainWindowChromePolicy.allowsZoom
        }

        private func toggleFromStatusItem() {
            guard let window else { return }
            let action = MainWindowTogglePolicy.action(
                isApplicationHidden: NSApp.isHidden,
                isWindowVisible: window.isVisible,
                isWindowMiniaturized: window.isMiniaturized
            )
            switch action {
            case .show:
                presentMainWindow(window)
            case .hide:
                hideMainWindow(window)
            }
        }

        private func showFromCommand() {
            guard let window else { return }
            presentMainWindow(window)
        }

        private func restoreDefaultWindowSize() {
            guard let window,
                  MainWindowFramePersistence.restoreDefaultSize(
                      window: window
                  ) else { return }
            NotificationCenter.default.post(
                name: MainWindowCommandNotification.didRestoreDefaultSize,
                object: window
            )
        }

        private func presentMainWindow(_ window: NSWindow) {
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            let frontmostBundleIdentifier = frontmostApplication?.bundleIdentifier
            let companionBundleIdentifier = Bundle.main.bundleIdentifier
            if codexAvailabilityMonitor.isCodexAvailable,
               (
                   frontmostBundleIdentifier
                       == CompanionVisibilityPolicy.codexBundleIdentifier
                       || frontmostBundleIdentifier == companionBundleIdentifier
               ) {
                cancelCodexActivationTimeout()
                visibilityState.recordManualShow()
                updateVisibility(frontmostApplication: frontmostApplication)
                return
            }

            guard !visibilityState.isAwaitingCodexActivation else { return }
            let requestID = visibilityState.beginCodexActivation()
            orderOutMainWindow(window)
            scheduleCodexActivationTimeout(for: requestID)
            CodexApplicationController.activateOrLaunch { [weak self] accepted in
                guard let self else { return }
                self.codexActivationRequestDidReturn(
                    requestID: requestID,
                    accepted: accepted
                )
                if accepted {
                    DispatchQueue.main.async { [weak self] in
                        self?.completeCodexActivationIfFrontmost(
                            requestID: requestID
                        )
                    }
                }
            }
        }

        private func hideMainWindow(_ window: NSWindow) {
            cancelCodexActivationTimeout()
            visibilityState.recordManualHide()
            MainWindowFramePersistence.persist(window: window)
            orderOutMainWindow(window)
        }

        private func orderOutMainWindow(_ window: NSWindow) {
            closeButtonHoverHintController.cancelAndDismiss()
            window.orderOut(nil)
        }

        private func installFramePersistenceObservers(for window: NSWindow) {
            framePersistenceObservers.forEach(
                NotificationCenter.default.removeObserver
            )
            let center = NotificationCenter.default
            let frameNotifications: [Notification.Name] = [
                NSWindow.didMoveNotification,
                NSWindow.didResizeNotification,
                NSApplication.willTerminateNotification,
            ]
            framePersistenceObservers = frameNotifications.map { name in
                center.addObserver(
                    forName: name,
                    object: name == NSApplication.willTerminateNotification
                        ? NSApp
                        : window,
                    queue: .main
                ) { [weak window] _ in
                    guard let window else { return }
                    MainActor.assumeIsolated {
                        MainWindowFramePersistence.persistIfVisible(
                            window: window
                        )
                    }
                }
            }
        }

        private func codexActivationRequestDidReturn(
            requestID: UUID,
            accepted: Bool
        ) {
            guard visibilityState.isCurrentCodexActivationRequest(requestID) else {
                return
            }
            if completeCodexActivationIfFrontmost(requestID: requestID) {
                return
            }
            if !accepted {
                cancelCodexActivationTimeout()
                _ = visibilityState.completeCodexActivation(requestID: requestID)
                if let window {
                    orderOutMainWindow(window)
                }
            }
        }

        @discardableResult
        private func completeCodexActivationIfFrontmost(
            requestID: UUID
        ) -> Bool {
            guard visibilityState.isCurrentCodexActivationRequest(requestID),
                  let frontmostApplication = NSWorkspace.shared.frontmostApplication,
                  frontmostApplication.bundleIdentifier
                    == CompanionVisibilityPolicy.codexBundleIdentifier else {
                return false
            }
            cancelCodexActivationTimeout()
            _ = visibilityState.completeCodexActivation(requestID: requestID)
            updateVisibility(frontmostApplication: frontmostApplication)
            return true
        }

        private func scheduleCodexActivationTimeout(for requestID: UUID) {
            cancelCodexActivationTimeout()
            let workItem = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self,
                          self.visibilityState.completeCodexActivation(
                            requestID: requestID
                          ) else {
                        return
                    }
                    self.codexActivationTimeoutWorkItem = nil
                    let frontmostApplication = NSWorkspace.shared.frontmostApplication
                    if frontmostApplication?.bundleIdentifier
                        == CompanionVisibilityPolicy.codexBundleIdentifier {
                        self.updateVisibility(
                            frontmostApplication: frontmostApplication
                        )
                    } else {
                        if let window = self.window {
                            self.orderOutMainWindow(window)
                        }
                    }
                }
            }
            codexActivationTimeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + CodexApplicationActivationPolicy.timeoutInterval,
                execute: workItem
            )
        }

        private func cancelCodexActivationTimeout() {
            codexActivationTimeoutWorkItem?.cancel()
            codexActivationTimeoutWorkItem = nil
        }

        private func applicationDidActivate(
            _ application: NSRunningApplication?
        ) {
            if visibilityState.isAwaitingCodexActivation {
                guard application?.bundleIdentifier
                    == CompanionVisibilityPolicy.codexBundleIdentifier else {
                    if let window {
                        orderOutMainWindow(window)
                    }
                    return
                }
                cancelCodexActivationTimeout()
                _ = visibilityState.completeCodexActivation()
            }
            updateVisibility(frontmostApplication: application)
        }

        private func codexAvailabilityDidChange(_ isAvailable: Bool) {
            if !isAvailable, visibilityState.isAwaitingCodexActivation {
                cancelCodexActivationTimeout()
                _ = visibilityState.completeCodexActivation()
            }
            updateVisibility(
                frontmostApplication: NSWorkspace.shared.frontmostApplication
            )
        }

        private func updateVisibility(frontmostApplication: NSRunningApplication?) {
            guard let window else { return }
            let frontmostBundleIdentifier = frontmostApplication?.bundleIdentifier
            let companionBundleIdentifier = Bundle.main.bundleIdentifier
            let automaticVisibilityAllowed = CompanionVisibilityPolicy.shouldShow(
                frontmostBundleIdentifier: frontmostBundleIdentifier,
                companionBundleIdentifier: companionBundleIdentifier,
                isCodexAvailable: codexAvailabilityMonitor.isCodexAvailable
            )
            let shouldShow = visibilityState.shouldShow(
                automaticVisibilityAllowed: automaticVisibilityAllowed
            )
            let action = MainWindowAutomaticPresentationPolicy.action(
                shouldShow: shouldShow,
                isApplicationHidden: NSApp.isHidden,
                isWindowVisible: window.isVisible,
                isWindowMiniaturized: window.isMiniaturized
            )
            switch action {
            case .show:
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
                if NSApp.isHidden {
                    NSApp.unhideWithoutActivation()
                }
                MainWindowFramePersistence.showPreservingFrame(window: window)
            case .hide:
                orderOutMainWindow(window)
            case .none:
                break
            }
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector)
                || originalWindowDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if originalWindowDelegate?.responds(to: aSelector) == true {
                return originalWindowDelegate
            }
            return super.forwardingTarget(for: aSelector)
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
            applyTheme(to: window)
            MainWindowChromePolicy.apply(to: window)
            window.level = .floating
            window.hidesOnDeactivate = false
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.identifier = CodexNotesWindowIdentifier.main
            window.title = "CodexNotes"
            window.isReleasedWhenClosed = false
            MainWindowFramePersistence.configure(window: window) {
                placeBesideCodex(window: window)
            }
            coordinator.attach(
                to: window,
                languageRevision: languageRevision
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            applyTheme(to: window)
            MainWindowChromePolicy.apply(to: window)
            context.coordinator.refreshLocalizationIfNeeded(
                for: window,
                languageRevision: languageRevision
            )
            context.coordinator.refreshCloseButtonHoverHint(for: window)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    private func applyTheme(to window: NSWindow) {
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

    private func placeBesideCodex(window: NSWindow) {
        let displays = NSScreen.screens.compactMap(displayGeometry(for:))
        let quartzBounds = frontmostCodexWindowBounds()
        let codexDisplay = quartzBounds.flatMap {
            MainWindowInitialPlacementPolicy.display(
                containingQuartzBounds: $0,
                among: displays
            )
        }
        let targetDisplay = codexDisplay
            ?? window.screen.flatMap(displayGeometry(for:))
            ?? NSScreen.main.flatMap(displayGeometry(for:))
            ?? displays.first
        guard let targetDisplay else { return }

        let codexFrame: NSRect? = quartzBounds.flatMap { bounds -> NSRect? in
            guard codexDisplay == targetDisplay else { return nil }
            return MainWindowInitialPlacementPolicy.appKitFrame(
                forQuartzBounds: bounds,
                on: targetDisplay
            )
        }
        window.setFrame(
            MainWindowInitialPlacementPolicy.initialFrame(
                in: targetDisplay.visibleFrame,
                codexFrame: codexFrame
            ),
            display: false
        )
    }

    private func frontmostCodexWindowBounds() -> CGRect? {
        let codexProcessIdentifiers = Set(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: CompanionVisibilityPolicy.codexBundleIdentifier
            ).map(\.processIdentifier)
        )
        guard !codexProcessIdentifiers.isEmpty else { return nil }
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }
        return info.lazy.compactMap { item -> CGRect? in
            guard let ownerPID = item[kCGWindowOwnerPID as String] as? NSNumber,
                  codexProcessIdentifiers.contains(ownerPID.int32Value),
                  let layer = item[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let dictionary = item[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: dictionary)
        }.first
    }

    private func displayGeometry(for screen: NSScreen) -> MainWindowDisplayGeometry? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[screenNumberKey]
            as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        return MainWindowDisplayGeometry(
            appKitFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            quartzFrame: CGDisplayBounds(displayID)
        )
    }
}
