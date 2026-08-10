import Foundation

public enum AppLanguagePreference: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case system
    case simplifiedChinese
    case english

    public static let key = "appLanguage"
    public static let defaultValue: AppLanguagePreference = .system

    public var id: String { rawValue }

    public static func normalized(_ rawValue: String) -> AppLanguagePreference {
        AppLanguagePreference(rawValue: rawValue) ?? defaultValue
    }

    public static func load(
        from defaults: UserDefaults = .standard
    ) -> AppLanguagePreference {
        guard let rawValue = defaults.string(forKey: key),
              let preference = AppLanguagePreference(rawValue: rawValue) else {
            if defaults.object(forKey: key) != nil {
                defaults.set(defaultValue.rawValue, forKey: key)
            }
            return defaultValue
        }
        return preference
    }

    public static func save(
        _ preference: AppLanguagePreference,
        to defaults: UserDefaults = .standard
    ) {
        defaults.set(preference.rawValue, forKey: key)
    }
}

public enum ResolvedAppLanguage: String, CaseIterable, Identifiable, Sendable {
    case zhHans = "zh-Hans"
    case en

    public var id: String { rawValue }
    public var locale: Locale { Locale(identifier: rawValue) }

    fileprivate init?(localizationIdentifier: String) {
        let normalized = localizationIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        if normalized == "en" || normalized.hasPrefix("en-") {
            self = .en
        } else if normalized == "zh" || normalized.hasPrefix("zh-") {
            self = .zhHans
        } else {
            return nil
        }
    }
}

public enum L10n {
    public enum Key: String, CaseIterable, Sendable {
        case languageSystem = "language.system"
        case languageSimplifiedChinese = "language.simplified_chinese"
        case languageEnglish = "language.english"
        case settingsGeneralTitle = "settings.general.title"
        case settingsLanguageTitle = "settings.language.title"
        case settingsLanguageAccessibilityHint = "settings.language.accessibility_hint"
        case settingsLaunchAtLoginTitle = "settings.launch_at_login.title"
        case settingsLaunchAtLoginDescription = "settings.launch_at_login.description"
        case settingsLaunchAtLoginRequiresApproval = "settings.launch_at_login.requires_approval"
        case settingsLaunchAtLoginOpenSystemSettings = "settings.launch_at_login.open_system_settings"
        case settingsLaunchAtLoginError = "settings.launch_at_login.error"

        case commonActionOK = "common.action.ok"
        case commonActionRetry = "common.action.retry"
        case commonActionUndo = "common.action.undo"
        case commonActionView = "common.action.view"
        case commonStateSelected = "common.state.selected"
        case accessibilityValueOn = "accessibility.value.on"
        case accessibilityValueOff = "accessibility.value.off"

        case noteScopeTask = "note.scope.task"
        case noteScopeProject = "note.scope.project"
        case taskFallbackLocal = "task.fallback.local"
        case taskFallbackRemote = "task.fallback.remote"
        case taskFallbackWork = "task.fallback.work"
        case taskFallbackNewDraft = "task.fallback.new_draft"
        case taskFallbackNewUncreated = "task.fallback.new_uncreated"
        case taskFallbackUnknown = "task.fallback.unknown"
        case taskFallbackUntitled = "task.fallback.untitled"

        case codexLogErrorDirectoryMissing = "codex_log.error.directory_missing"
        case codexLogErrorMainLogMissing = "codex_log.error.main_log_missing"
        case codexLogErrorUnreadable = "codex_log.error.unreadable"

        case noteStoreErrorProjectUnavailable = "note_store.error.project_unavailable"
        case noteStoreErrorCannotCreateDirectory = "note_store.error.cannot_create_directory"
        case noteStoreErrorCannotRead = "note_store.error.cannot_read"
        case noteStoreErrorCannotSave = "note_store.error.cannot_save"
        case noteStoreErrorMigrationConflict = "note_store.error.migration_conflict"

        case imageMarkdownAltText = "editor.image.markdown_alt_text"
        case imageStoreErrorInvalidSource = "image_store.error.invalid_source"
        case imageStoreErrorNotRegularFile = "image_store.error.not_regular_file"
        case imageStoreErrorUnsupportedFormat = "image_store.error.unsupported_format"
        case imageStoreErrorAnimatedUnsupported = "image_store.error.animated_unsupported"
        case imageStoreErrorEncodedTooLarge = "image_store.error.encoded_too_large"
        case imageStoreErrorConvertedTooLarge = "image_store.error.converted_too_large"
        case imageStoreErrorInvalidDimensions = "image_store.error.invalid_dimensions"
        case imageStoreErrorDimensionsTooLarge = "image_store.error.dimensions_too_large"
        case imageStoreErrorCannotDecode = "image_store.error.cannot_decode"
        case imageStoreErrorCannotEncode = "image_store.error.cannot_encode"
        case imageStoreErrorCannotCreateDirectory = "image_store.error.cannot_create_directory"
        case imageStoreErrorUnsafeDirectory = "image_store.error.unsafe_directory"
        case imageStoreErrorInvalidAsset = "image_store.error.invalid_asset"
        case imageStoreErrorAssetConflict = "image_store.error.asset_conflict"
        case imageStoreErrorCannotSave = "image_store.error.cannot_save"

        case selectionMoveErrorEditorUnavailable = "selection_move.error.editor_unavailable"
        case selectionMoveErrorStaleSelection = "selection_move.error.stale_selection"
        case selectionMoveErrorEmptySelection = "selection_move.error.empty_selection"
        case selectionMoveErrorSameScope = "selection_move.error.same_scope"
        case selectionMoveErrorSameDocument = "selection_move.error.same_document"
        case selectionMoveErrorProjectUnavailable = "selection_move.error.project_unavailable"
        case selectionMoveErrorProjectReadOnly = "selection_move.error.project_read_only"
        case selectionMoveErrorNothingToUndo = "selection_move.error.nothing_to_undo"
        case selectionMoveErrorUndoContextChanged = "selection_move.error.undo_context_changed"
        case selectionMoveErrorReloadRequired = "selection_move.error.reload_required"
        case selectionMoveErrorSelectionOutOfBounds = "selection_move.error.selection_out_of_bounds"
        case selectionMoveErrorStaleMoveSource = "selection_move.error.stale_move_source"
        case selectionMoveErrorStaleUndoSource = "selection_move.error.stale_undo_source"
        case selectionMoveErrorStaleUndoDestination = "selection_move.error.stale_undo_destination"
        case selectionMoveErrorWriteStateUnknown = "selection_move.error.write_state_unknown"
        case selectionMoveErrorRollbackFailed = "selection_move.error.rollback_failed"
        case selectionMoveOperationMoveToDestination = "selection_move.operation.move_to_destination"
        case selectionMoveOperationRemoveFromSource = "selection_move.operation.remove_from_source"
        case selectionMoveOperationMoveSelection = "selection_move.operation.move_selection"
        case selectionMoveOperationRollbackDestination = "selection_move.operation.rollback_destination"
        case selectionMoveOperationRestoreSourceDuringUndo = "selection_move.operation.restore_source_during_undo"
        case selectionMoveOperationRestoreDestinationDuringUndo = "selection_move.operation.restore_destination_during_undo"
        case selectionMoveOperationUndoMove = "selection_move.operation.undo_move"
        case selectionMoveOperationRollbackSource = "selection_move.operation.rollback_source"
        case selectionMoveVerificationContentMismatch = "selection_move.verification.content_mismatch"
        case selectionMoveVerificationReadbackFailed = "selection_move.verification.readback_failed"

        case connectionErrorNoTaskSwitchEvent = "connection.error.no_task_switch_event"
        case connectionErrorUnsupportedTaskType = "connection.error.unsupported_task_type"
        case noteSwitchErrorPreviousSaveFailed = "note_switch.error.previous_save_failed"
        case draftMigrationErrorFailed = "draft_migration.error.failed"
        case projectNoteErrorMetadataSwitchFailed = "project_note.error.metadata_switch_failed"
        case projectNoteErrorPostCreationReloadFailed = "project_note.error.post_creation_reload_failed"
        case noteSafetyErrorDiskChanged = "note_safety.error.disk_changed"
        case noteSafetyErrorReloadFailed = "note_safety.error.reload_failed"
        case noteSaveErrorDraftPreserved = "note_save.error.draft_preserved"

        case moveSelectionAlertTitle = "move_selection.alert.title"
        case moveSelectionAlertRetryMessage = "move_selection.alert.retry_message"
        case connectionStatusDetecting = "connection.status.detecting"
        case connectionStatusFollowing = "connection.status.following"
        case connectionStatusNewTask = "connection.status.new_task"
        case connectionStatusPaused = "connection.status.paused"
        case imageImportDismissAccessibilityLabel = "image_import.dismiss.accessibility_label"

        case scopeAccessibilityLabel = "scope.accessibility.label"
        case scopeHelpSwitchUnavailable = "scope.help.switch_unavailable"
        case scopeHelpSwitchUnavailableWithStatus = "scope.help.switch_unavailable_with_status"
        case scopeHelpStandard = "scope.help.standard"
        case scopeHelpStandardWithStatus = "scope.help.standard_with_status"
        case scopeHelpProjectConfirmCandidate = "scope.help.project.confirm_candidate"
        case scopeHelpProjectNewTaskReadOnly = "scope.help.project.new_task_read_only"
        case scopeHelpProjectNotInProject = "scope.help.project.not_in_project"
        case scopeHelpProjectInfoUnavailable = "scope.help.project.info_unavailable"
        case scopeHelpProjectNoWorkingDirectory = "scope.help.project.no_working_directory"
        case scopeProgressUnavailable = "scope.progress.unavailable"
        case scopeProgressEmpty = "scope.progress.empty"
        case scopeProgressAllComplete = "scope.progress.all_complete"
        case scopeProgressCompleted = "scope.progress.completed"
        case scopeAccessibilitySwitchUnavailable = "scope.accessibility.switch_unavailable"
        case scopeAccessibilitySwitchUnavailableWithStatus = "scope.accessibility.switch_unavailable_with_status"
        case scopeAccessibilityProjectConfirmCandidate = "scope.accessibility.project.confirm_candidate"
        case scopeAccessibilityProjectConfirmedReadOnly = "scope.accessibility.project.confirmed_read_only"
        case scopeAccessibilityProjectNotInProject = "scope.accessibility.project.not_in_project"
        case scopeAccessibilityProjectInfoUnavailable = "scope.accessibility.project.info_unavailable"
        case scopeAccessibilityProjectNoWorkingDirectory = "scope.accessibility.project.no_working_directory"
        case scopeAccessibilityStatusAndProgress = "scope.accessibility.status_and_progress"
        case projectNameConfirmCandidate = "project.name.confirm_candidate"
        case projectNameUntitled = "project.name.untitled"
        case projectNameNotInProject = "project.name.not_in_project"
        case projectNameInfoUnavailable = "project.name.info_unavailable"

        case editorNewTaskProjectReadOnlyBanner = "editor.new_task_project_read_only.banner"
        case editorNewTaskProjectReadOnlyAccessibilityLabel = "editor.new_task_project_read_only.accessibility_label"
        case editorNewTaskProjectReadOnlyAccessibilityValue = "editor.new_task_project_read_only.accessibility_value"
        case editorUnboundTitle = "editor.unbound.title"
        case editorUnboundMessage = "editor.unbound.message"
        case todoHelp = "todo.help"
        case todoAccessibilityLabel = "todo.accessibility.label"
        case moveSelectionDisabledProjectReadOnly = "move_selection.disabled.project_read_only"
        case moveSelectionDisabledNoProjectNote = "move_selection.disabled.no_project_note"
        case moveSelectionActionToEnd = "move_selection.action.to_end"
        case moveSelectionActionToScope = "move_selection.action.to_scope"
        case moveSelectionNoticeMoved = "move_selection.notice.moved"
        case moveSelectionNoticeDismissHelp = "move_selection.notice.dismiss.help"
        case moveSelectionNoticeDismissAccessibilityLabel = "move_selection.notice.dismiss.accessibility_label"

        case connectionAccessibilityLabel = "connection.accessibility.label"
        case connectionHelpDetecting = "connection.help.detecting"
        case connectionHelpFollowing = "connection.help.following"
        case connectionHelpNewTask = "connection.help.new_task"
        case connectionHelpPaused = "connection.help.paused"
        case connectionAccessibilityFollowing = "connection.accessibility.following"
        case connectionAccessibilityNewTask = "connection.accessibility.new_task"
        case connectionAccessibilityPaused = "connection.accessibility.paused"
        case saveAccessibilityLabel = "save.accessibility.label"
        case taskNameDetecting = "task.name.detecting"
        case taskNameNewTask = "task.name.new_task"
        case taskNameCurrent = "task.name.current"
        case taskNameRemote = "task.name.remote"
        case taskNameUnavailable = "task.name.unavailable"

        case emptyNoteTaskPrompt = "empty_note.task.prompt"
        case emptyNoteTaskShortcutHint = "empty_note.task.shortcut_hint"
        case emptyNoteProjectPrompt = "empty_note.project.prompt"
        case emptyNoteProjectTodoExample = "empty_note.project.todo_example"
        case todoBadgeEmpty = "todo.badge.empty"
        case todoBadgeMinimal = "todo.badge.minimal"
        case todoBadgeProgressWide = "todo.badge.progress_wide"
        case todoBadgeProgressCompact = "todo.badge.progress_compact"
        case todoAccessibilityProgress = "todo.accessibility.progress"
        case saveStatusIdleTitle = "save.status.idle.title"
        case saveStatusIdleHelp = "save.status.idle.help"
        case saveStatusSavingTitle = "save.status.saving.title"
        case saveStatusSavingHelp = "save.status.saving.help"
        case saveStatusSavedTitle = "save.status.saved.title"
        case saveStatusSavedHelp = "save.status.saved.help"
        case saveStatusFailedTitle = "save.status.failed.title"
        case saveStatusFailedHelp = "save.status.failed.help"
        case saveStatusFailedAccessibilityValue = "save.status.failed.accessibility_value"

        case bottomBarFilesHelp = "bottom_bar.files.help"
        case bottomBarShortcutsHelp = "bottom_bar.shortcuts.help"
        case bottomBarSettingsHelp = "bottom_bar.settings.help"
        case shortcutsTitle = "shortcuts.title"
        case shortcutsSectionTodos = "shortcuts.section.todos"
        case shortcutsSectionNotes = "shortcuts.section.notes"
        case shortcutsSectionFormatting = "shortcuts.section.formatting"
        case shortcutsItemToggleCurrentLineTodo = "shortcuts.item.toggle_current_line_todo"
        case shortcutsItemTaskNote = "shortcuts.item.task_note"
        case shortcutsItemProjectNote = "shortcuts.item.project_note"
        case shortcutsItemBoldSelection = "shortcuts.item.bold_selection"
        case shortcutsItemHighlightSelection = "shortcuts.item.highlight_selection"
        case shortcutsItemAccessibilityLabel = "shortcuts.item.accessibility_label"
        case shortcutsFormattingRequiresSelection = "shortcuts.formatting.requires_selection"

        case settingsStatusBarIconTitle = "settings.status_bar_icon.title"
        case settingsStatusBarIconDescription = "settings.status_bar_icon.description"
        case settingsAppearanceTitle = "settings.appearance.title"
        case settingsAppearanceDescription = "settings.appearance.description"
        case settingsAppearanceOriginal = "settings.appearance.original"
        case settingsAppearanceThemesAccessibilityLabel = "settings.appearance.themes.accessibility_label"
        case settingsEditorTitle = "settings.editor.title"
        case settingsEditorFontSize = "settings.editor.font_size"
        case settingsEditorFontSizeAccessibilityHint = "settings.editor.font_size.accessibility_hint"
        case settingsEditorLineSpacing = "settings.editor.line_spacing"
        case settingsEditorLineSpacingAccessibilityHint = "settings.editor.line_spacing.accessibility_hint"
        case settingsEditorPreviewText = "settings.editor.preview_text"
        case settingsEditorPreviewAccessibilityLabel = "settings.editor.preview.accessibility_label"
        case settingsEditorRestoreDefaults = "settings.editor.restore_defaults"
        case settingsEditorRestoreDefaultsAccessibilityLabel = "settings.editor.restore_defaults.accessibility_label"
        case settingsEditorRestoreDefaultsAccessibilityHint = "settings.editor.restore_defaults.accessibility_hint"
        case settingsStatusBarIconChoiceAccessibilityLabel = "settings.status_bar_icon.choice.accessibility_label"
        case settingsThemeChoiceAccessibilityLabel = "settings.theme.choice.accessibility_label"

        case settingsThemeSystemOriginalName = "settings.theme.system_original.name"
        case settingsThemeMistPaperName = "settings.theme.mist_paper.name"
        case settingsThemeWarmPaperName = "settings.theme.warm_paper.name"
        case settingsThemeSeaSaltName = "settings.theme.sea_salt.name"
        case settingsThemeSageMistName = "settings.theme.sage_mist.name"
        case settingsThemeMidnightIndigoName = "settings.theme.midnight_indigo.name"
        case settingsThemePlumNightName = "settings.theme.plum_night.name"
        case settingsThemeSystemOriginalSummary = "settings.theme.system_original.summary"
        case settingsThemeMistPaperSummary = "settings.theme.mist_paper.summary"
        case settingsThemeWarmPaperSummary = "settings.theme.warm_paper.summary"
        case settingsThemeSeaSaltSummary = "settings.theme.sea_salt.summary"
        case settingsThemeSageMistSummary = "settings.theme.sage_mist.summary"
        case settingsThemeMidnightIndigoSummary = "settings.theme.midnight_indigo.summary"
        case settingsThemePlumNightSummary = "settings.theme.plum_night.summary"

        case settingsStatusIconCodexPencilName = "settings.status_icon.codex_pencil.name"
        case settingsStatusIconChatGPTPencilName = "settings.status_icon.chatgpt_pencil.name"
        case settingsStatusIconCodexPencilSummary = "settings.status_icon.codex_pencil.summary"
        case settingsStatusIconChatGPTPencilSummary = "settings.status_icon.chatgpt_pencil.summary"
        case statusIconAccessibilityDescription = "status_icon.accessibility_description"

        case statusItemEducationTitle = "status_item.education.title"
        case statusItemEducationMessage = "status_item.education.message"
        case statusItemTooltip = "status_item.tooltip"
        case statusItemAccessibilityHelp = "status_item.accessibility.help"
        case statusItemQuit = "status_item.quit"
        case mainWindowCloseAccessibilityLabel = "main_window.close.accessibility_label"
        case mainWindowCloseAccessibilityHelp = "main_window.close.accessibility_help"
        case windowCloseHoverHint = "window.close.hover_hint"
        case appCommandSaveNow = "app.command.save_now"

        case editorImageImportErrorTooManyImages = "editor.image_import.error.too_many_images"
        case editorImageImportErrorBatchTooLarge = "editor.image_import.error.batch_too_large"
        case editorSelectionToolbarBoldTooltip = "editor.selection_toolbar.bold.tooltip"
        case editorSelectionToolbarBoldLabel = "editor.selection_toolbar.bold.label"
        case editorSelectionToolbarHighlightTooltip = "editor.selection_toolbar.highlight.tooltip"
        case editorSelectionToolbarHighlightLabel = "editor.selection_toolbar.highlight.label"
        case editorSelectionToolbarLabel = "editor.selection_toolbar.label"
        case editorSelectionToolbarMoveLabel = "editor.selection_toolbar.move.label"
        case editorSelectionToolbarBoldHelpEnabled = "editor.selection_toolbar.bold.help_enabled"
        case editorSelectionToolbarBoldHelpDisabled = "editor.selection_toolbar.bold.help_disabled"
        case editorSelectionToolbarHighlightHelpEnabled = "editor.selection_toolbar.highlight.help_enabled"
        case editorSelectionToolbarHighlightHelpDisabled = "editor.selection_toolbar.highlight.help_disabled"
        case editorImageImportErrorReadBatch = "editor.image_import.error.read_batch"
        case editorImageImportErrorInvalidInsertionPoint = "editor.image_import.error.invalid_insertion_point"
        case editorImageImportErrorProcessBatch = "editor.image_import.error.process_batch"
        case editorImageImportErrorSaveBatch = "editor.image_import.error.save_batch"

        case probeCheckErrorNoTask = "probe_check.error.no_task"
    }

    public static func text(
        _ key: Key,
        replacements: [String: String] = [:],
        preference: AppLanguagePreference? = nil
    ) -> String {
        AppLocalization(
            preference: preference ?? AppLanguagePreference.load()
        ).text(key, replacements: replacements)
    }
}

public struct AppLocalization {
    public static let fallbackLanguage: ResolvedAppLanguage = .zhHans
    static let defaultResourceBundle = Bundle.module

    public let preference: AppLanguagePreference
    public let resolvedLanguage: ResolvedAppLanguage

    private let localizedBundle: Bundle
    private let fallbackBundle: Bundle

    public init(
        preference: AppLanguagePreference = .system,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.init(
            preference: preference,
            resourceBundle: Self.defaultResourceBundle,
            preferredLanguages: preferredLanguages
        )
    }

    init(
        preference: AppLanguagePreference,
        resourceBundle: Bundle,
        preferredLanguages: [String]
    ) {
        self.preference = preference
        resolvedLanguage = Self.resolve(
            preference,
            preferredLanguages: preferredLanguages
        )
        localizedBundle = Self.languageBundle(
            for: resolvedLanguage,
            in: resourceBundle
        ) ?? resourceBundle
        fallbackBundle = Self.languageBundle(
            for: Self.fallbackLanguage,
            in: resourceBundle
        ) ?? resourceBundle
    }

    public static func resolve(
        _ preference: AppLanguagePreference,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> ResolvedAppLanguage {
        switch preference {
        case .simplifiedChinese:
            return .zhHans
        case .english:
            return .en
        case .system:
            return preferredLanguages
                .compactMap(ResolvedAppLanguage.init(localizationIdentifier:))
                .first ?? fallbackLanguage
        }
    }

    public func text(
        _ key: L10n.Key,
        replacements: [String: String] = [:]
    ) -> String {
        let template = localizedTemplate(for: key)
        return Self.replacingNamedTokens(in: template, with: replacements)
    }

    private func localizedTemplate(for key: L10n.Key) -> String {
        let localized = localizedBundle.localizedString(
            forKey: key.rawValue,
            value: nil,
            table: "Localizable"
        )
        if localized != key.rawValue || resolvedLanguage == Self.fallbackLanguage {
            return localized
        }
        return fallbackBundle.localizedString(
            forKey: key.rawValue,
            value: key.rawValue,
            table: "Localizable"
        )
    }

    private static func languageBundle(
        for language: ResolvedAppLanguage,
        in resourceBundle: Bundle
    ) -> Bundle? {
        guard let resourceURL = resourceBundle.resourceURL else { return nil }
        let languageURL = resourceURL.appendingPathComponent(
            "\(language.rawValue).lproj",
            isDirectory: true
        )
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: languageURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else { return nil }
        return Bundle(url: languageURL)
    }

    private static func replacingNamedTokens(
        in template: String,
        with replacements: [String: String]
    ) -> String {
        guard !replacements.isEmpty else { return template }

        var result = ""
        var cursor = template.startIndex
        while let openingBrace = template[cursor...].firstIndex(of: "{") {
            result.append(contentsOf: template[cursor..<openingBrace])
            guard let closingBrace = template[openingBrace...].firstIndex(of: "}") else {
                result.append(contentsOf: template[openingBrace...])
                return result
            }

            let tokenStart = template.index(after: openingBrace)
            let token = String(template[tokenStart..<closingBrace])
            if let replacement = replacements[token] {
                result.append(replacement)
            } else {
                result.append(contentsOf: template[openingBrace...closingBrace])
            }
            cursor = template.index(after: closingBrace)
        }
        result.append(contentsOf: template[cursor...])
        return result
    }
}
