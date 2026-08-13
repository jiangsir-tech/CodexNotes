import CodexNotesCore
import Foundation

struct ProbeHistoryItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let stableKey: String
    let timestamp: Date
}

struct SelectionMoveNotice: Identifiable, Equatable {
    let id: UUID
    let destinationScope: NoteScope
    let destinationName: String
    var canUndo: Bool
    var canViewDestination: Bool

    init(
        id: UUID = UUID(),
        destinationScope: NoteScope,
        destinationName: String,
        canUndo: Bool,
        canViewDestination: Bool
    ) {
        self.id = id
        self.destinationScope = destinationScope
        self.destinationName = destinationName
        self.canUndo = canUndo
        self.canViewDestination = canViewDestination
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.destinationScope == rhs.destinationScope
            && lhs.destinationName == rhs.destinationName
            && lhs.canUndo == rhs.canUndo
            && lhs.canViewDestination == rhs.canViewDestination
    }
}

private enum SelectionMoveCoordinationError: LocalizedError {
    case editorUnavailable
    case staleSelection
    case emptySelection
    case sameScope
    case projectUnavailable
    case projectReadOnly
    case nothingToUndo
    case undoContextChanged
    case reloadRequiredBeforeWrite

    var errorDescription: String? {
        switch self {
        case .editorUnavailable:
            return L10n.text(.selectionMoveErrorEditorUnavailable)
        case .staleSelection:
            return L10n.text(.selectionMoveErrorStaleSelection)
        case .emptySelection:
            return L10n.text(.selectionMoveErrorEmptySelection)
        case .sameScope:
            return L10n.text(.selectionMoveErrorSameScope)
        case .projectUnavailable:
            return L10n.text(.selectionMoveErrorProjectUnavailable)
        case .projectReadOnly:
            return L10n.text(.selectionMoveErrorProjectReadOnly)
        case .nothingToUndo:
            return L10n.text(.selectionMoveErrorNothingToUndo)
        case .undoContextChanged:
            return L10n.text(.selectionMoveErrorUndoContextChanged)
        case .reloadRequiredBeforeWrite:
            return L10n.text(.selectionMoveErrorReloadRequired)
        }
    }
}

struct CodexRightPanelObservation: Equatable, Sendable {
    let selectionStableKey: String?
    let state: CodexRightPanelState

    static let unknown = CodexRightPanelObservation(
        selectionStableKey: nil,
        state: .unknown
    )
}

@MainActor
final class ProbeViewModel: ObservableObject {
    typealias SelectionMoveNoticeScheduledAction = @MainActor () -> Void
    typealias SelectionMoveNoticeDismissalCancellation = @MainActor () -> Void
    typealias SelectionMoveNoticeScheduler = @MainActor (
        _ delay: Duration,
        _ action: @escaping SelectionMoveNoticeScheduledAction
    ) -> SelectionMoveNoticeDismissalCancellation

    enum State: Equatable {
        case starting
        case detected
        case newTask
        case unavailable(String)
    }

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    @Published private(set) var state: State = .starting
    @Published private(set) var selection: CodexSelection?
    @Published private(set) var rightPanelObservation =
        CodexRightPanelObservation.unknown
    private(set) var isRightPanelAvoidanceEnabled =
        RightPanelAvoidancePreference.defaultValue
    @Published private(set) var metadata: CodexThreadMetadata?
    @Published private(set) var history: [ProbeHistoryItem] = []
    @Published private(set) var lastLatencyMilliseconds: Int?
    @Published private(set) var selectedScope: NoteScope = .task
    @Published private(set) var activeDocument: NoteDocument?
    @Published private(set) var saveState: SaveState = .idle
    @Published private(set) var isSwitchBlocked = false
    @Published private(set) var selectionMoveNotice: SelectionMoveNotice?
    @Published private(set) var selectionMoveError: String?
    @Published private(set) var imageImportError: String?
    @Published private(set) var newTaskProjectCandidate: CodexGlobalProjectCandidate?

    // nil means the current identity has no available/readable document for that scope.
    // A non-nil 0/0 value means the document was read successfully but contains no todos.
    @Published private(set) var taskChecklistProgress: MarkdownChecklistProgress?
    @Published private(set) var projectChecklistProgress: MarkdownChecklistProgress?

    @Published var noteText = "" {
        didSet {
            guard !isLoadingDocument else { return }
            if noteText != oldValue {
                invalidateSelectionMoveUndoAfterEdit()
            }
            updateChecklistProgress(for: selectedScope, text: noteText)
            guard !isSwitchBlocked else { return }
            scheduleAutosave()
        }
    }

    let noteStore: NoteStore
    let noteImageStore: NoteImageStore

    private let monitor = CodexLogMonitor()
    private let rightPanelStateReader = CodexRightPanelStateReader()
    private let accessibilityRightPanelReader =
        CodexAccessibilityRightPanelReader()
    private let metadataProvider: any CodexThreadMetadataProviding
    private let globalProjectCandidateProvider: any CodexGlobalProjectCandidateProviding
    private let metadataClock = ContinuousClock()
    private let metadataRefreshInterval: Duration
    private let newTaskProjectRefreshInterval: Duration
    private let selectionMoveNoticeDuration: Duration
    private let selectionMoveNoticeScheduler: SelectionMoveNoticeScheduler
    private var monitoringTask: Task<Void, Never>?
    private var metadataRefreshTask: Task<Void, Never>?
    private var metadataRefreshRequestID: UUID?
    private var nextMetadataRefresh: ContinuousClock.Instant?
    private var autosaveTask: Task<Void, Never>?
    private var selectionMoveNoticeDismissalCancellation:
        SelectionMoveNoticeDismissalCancellation?
    private var selectionMoveNoticeDismissalRequestID: UUID?
    private var selectionMoveNoticeIsHovered = false
    private var isLoadingDocument = false
    private var editRevision = 0
    private var pendingSelectionMove: PendingSelectionMove?
    private var confirmedNewTaskProject: CodexGlobalProjectCandidate?
    private var requiresReloadBeforeWrite = false
    private var shouldResumeMonitoringAfterSafetyReload = false
    private var rightPanelDebouncer = CodexRightPanelDebouncer(
        requiredConsecutive: 2
    )
    private var rightPanelAccessibilityPermission:
        CodexAccessibilityPermissionState?
    private var rightPanelAvoidanceGeneration: UInt = 0

    private static let primaryRightPanelIdentity = "codex-primary-window"

    private struct PendingSelectionMove {
        let result: NoteSelectionMoveResult
        let selectionStableKey: String
    }

    private enum MetadataRefreshResult: Sendable {
        case thread(CodexThreadMetadata)
        case newTask(CodexGlobalProjectCandidateState)
    }

    init(
        noteStore: NoteStore = NoteStore(),
        noteImageStore: NoteImageStore? = nil,
        metadataProvider: any CodexThreadMetadataProviding = CodexThreadStore(),
        globalProjectCandidateProvider: any CodexGlobalProjectCandidateProviding = CodexProjectStore(),
        metadataRefreshInterval: Duration = .seconds(1),
        newTaskProjectRefreshInterval: Duration = .milliseconds(250),
        selectionMoveNoticeDuration: Duration = .seconds(8),
        selectionMoveNoticeScheduler: SelectionMoveNoticeScheduler? = nil
    ) {
        self.noteStore = noteStore
        self.noteImageStore = noteImageStore ?? NoteImageStore(rootURL: noteStore.rootURL)
        self.metadataProvider = metadataProvider
        self.globalProjectCandidateProvider = globalProjectCandidateProvider
        self.metadataRefreshInterval = metadataRefreshInterval
        self.newTaskProjectRefreshInterval = newTaskProjectRefreshInterval
        self.selectionMoveNoticeDuration = selectionMoveNoticeDuration
        self.selectionMoveNoticeScheduler = selectionMoveNoticeScheduler
            ?? Self.mainQueueSelectionMoveNoticeScheduler
    }

    deinit {
        monitoringTask?.cancel()
        metadataRefreshTask?.cancel()
        autosaveTask?.cancel()
        MainActor.assumeIsolated {
            selectionMoveNoticeDismissalCancellation?()
        }
    }

    var canEdit: Bool {
        activeDocument != nil && !isSwitchBlocked && !isNewTaskProjectReadOnly
    }

    var canUseProjectNote: Bool {
        projectNoteIsAvailable(in: metadata) && !isSwitchBlocked
    }

    var canWriteProjectNote: Bool {
        canUseProjectNote && selection?.kind != .newTask
    }

    var isNewTaskProjectReadOnly: Bool {
        selection?.kind == .newTask
            && selectedScope == .project
            && activeDocument?.scope == .project
    }

    var canConfirmNewTaskProject: Bool {
        selection?.kind == .newTask
            && newTaskProjectCandidate != nil
            && !isSwitchBlocked
    }

    var checklistProgress: MarkdownChecklistProgress {
        MarkdownChecklist.progress(in: noteText)
    }

    func checklistProgress(for scope: NoteScope) -> MarkdownChecklistProgress? {
        switch scope {
        case .task:
            return taskChecklistProgress
        case .project:
            return projectChecklistProgress
        }
    }

    func start() {
        guard !requiresReloadBeforeWrite,
              monitoringTask == nil
        else { return }
        monitoringTask = Task { [weak self] in
            guard let self else { return }
            await self.runMonitor()
        }
    }

    /// Controls the detector as well as the window response. Every preference
    /// edge publishes unknown so a pre-disable sample cannot be treated as
    /// current when the feature is enabled later.
    func setRightPanelAvoidanceEnabled(_ isEnabled: Bool) {
        guard isRightPanelAvoidanceEnabled != isEnabled else { return }
        isRightPanelAvoidanceEnabled = isEnabled
        rightPanelAvoidanceGeneration &+= 1
        rightPanelDebouncer.reset()
        rightPanelAccessibilityPermission = nil
        // Every preference generation begins from unknown. This prevents a
        // pre-disable `.open` sample from being replayed after off -> on, and
        // makes the controller wait for a fresh detector result.
        publishUnknownRightPanelObservation()
    }

    func retry() {
        cancelMetadataRefresh()
        if requiresReloadBeforeWrite {
            reloadCurrentDocumentAfterSelectionMoveSafetyPause()
            return
        }
        do {
            try flushCurrentDocument()
            isSwitchBlocked = false
        } catch {
            pauseForSaveFailure(error)
            return
        }

        monitoringTask?.cancel()
        monitoringTask = nil
        state = .starting
        start()
    }

    func selectScope(_ scope: NoteScope) {
        guard scope != selectedScope, !isSwitchBlocked else { return }
        if scope == .project, !canUseProjectNote { return }

        let previousScope = selectedScope
        do {
            try flushCurrentDocument()
        } catch {
            pauseForSaveFailure(error)
            return
        }

        selectedScope = scope
        do {
            try activateDocumentForCurrentScope(preservingIfSame: false)
        } catch {
            selectedScope = previousScope
            suspendEditing(message: error.localizedDescription)
        }
    }

    @discardableResult
    func confirmNewTaskProject() -> Bool {
        guard !isSwitchBlocked,
              let currentSelection = selection,
              currentSelection.kind == .newTask,
              let candidate = newTaskProjectCandidate
        else { return false }

        // Re-read on the user's click. This cannot prove that Codex has finished
        // updating its global state, but it prevents confirming a candidate that
        // has already changed since it was shown.
        let currentCandidateState = globalProjectCandidateProvider.globalProjectCandidate()
        guard case let .selected(currentProject) = currentCandidateState,
              currentProject == candidate,
              Self.supportsNewTaskProject(currentProject)
        else {
            applyNewTaskProjectCandidateState(
                currentCandidateState,
                expectedStableKey: currentSelection.stableKey
            )
            return false
        }

        confirmedNewTaskProject = candidate
        newTaskProjectCandidate = nil
        let confirmedMetadata = Self.newTaskMetadata(
            for: currentSelection,
            context: .selected(candidate)
        )
        applyRefreshedMetadata(
            confirmedMetadata,
            expectedStableKey: currentSelection.stableKey
        )
        return canUseProjectNote
    }

    @discardableResult
    func moveSelection(
        _ snapshot: EditorSelectionSnapshot,
        to destinationScope: NoteScope,
        expectedSelectionStableKey: String
    ) -> NoteSelectionMoveResult? {
        selectionMoveError = nil

        guard canEdit,
              let currentSelection = selection,
              let sourceDocument = activeDocument
        else {
            reportSelectionMoveError(SelectionMoveCoordinationError.editorUnavailable)
            return nil
        }
        guard snapshot.selectionStableKey == expectedSelectionStableKey,
              currentSelection.stableKey == expectedSelectionStableKey,
              sourceDocument.scope == selectedScope,
              sameDocument(snapshot.document, sourceDocument),
              snapshot.sourceText == noteText,
              selectedText(in: snapshot.sourceText, range: snapshot.range)
                == snapshot.selectedText
        else {
            reportSelectionMoveError(SelectionMoveCoordinationError.staleSelection)
            return nil
        }
        guard snapshot.range.length > 0, !snapshot.selectedText.isEmpty else {
            reportSelectionMoveError(SelectionMoveCoordinationError.emptySelection)
            return nil
        }
        guard destinationScope != sourceDocument.scope else {
            reportSelectionMoveError(SelectionMoveCoordinationError.sameScope)
            return nil
        }
        if destinationScope == .project {
            guard projectNoteIsAvailable(in: metadata) else {
                reportSelectionMoveError(SelectionMoveCoordinationError.projectUnavailable)
                return nil
            }
            guard canWriteProjectNote else {
                reportSelectionMoveError(SelectionMoveCoordinationError.projectReadOnly)
                return nil
            }
        }

        let destinationDocument: NoteDocument
        do {
            destinationDocument = try document(
                for: destinationScope,
                selection: currentSelection,
                metadata: metadata
            )
        } catch {
            reportSelectionMoveError(error)
            return nil
        }
        guard sameDocument(snapshot.destinationDocument, destinationDocument) else {
            reportSelectionMoveError(SelectionMoveCoordinationError.staleSelection)
            return nil
        }

        do {
            autosaveTask?.cancel()
            try flushCurrentDocument()
        } catch {
            reportSelectionMoveError(error)
            pauseForSaveFailure(error)
            return nil
        }

        do {
            let result = try noteStore.moveSelection(
                in: snapshot.range,
                sourceText: snapshot.sourceText,
                from: sourceDocument,
                to: destinationDocument
            )
            applySuccessfulSelectionMove(result, selectionStableKey: currentSelection.stableKey)
            return result
        } catch {
            if requiresSelectionMoveSafetyPause(error) {
                pauseForSelectionMoveSafety(error)
                return nil
            }
            reportSelectionMoveError(error)
            return nil
        }
    }

    @discardableResult
    func undoLastSelectionMove() -> NoteSelectionMoveResult? {
        selectionMoveError = nil
        guard !isSwitchBlocked,
              let pendingSelectionMove,
              selectionMoveNotice?.canUndo == true
        else {
            reportSelectionMoveError(SelectionMoveCoordinationError.nothingToUndo)
            return nil
        }
        guard selection?.stableKey == pendingSelectionMove.selectionStableKey,
              currentEditorMatchesMovedResult(pendingSelectionMove.result)
        else {
            invalidateSelectionMoveUndoAfterEdit()
            reportSelectionMoveError(SelectionMoveCoordinationError.undoContextChanged)
            return nil
        }

        autosaveTask?.cancel()
        do {
            try noteStore.undoSelectionMove(pendingSelectionMove.result)
            applySuccessfulSelectionMoveUndo(pendingSelectionMove.result)
            return pendingSelectionMove.result
        } catch {
            if requiresSelectionMoveSafetyPause(error) {
                pauseForSelectionMoveSafety(error)
                return nil
            }
            if isStaleSelectionMoveUndoError(error) {
                invalidateSelectionMoveUndoAfterEdit()
            }
            reportSelectionMoveError(error)
            return nil
        }
    }

    @discardableResult
    func viewSelectionMoveDestination() -> NSRange? {
        guard let notice = selectionMoveNotice,
              notice.canViewDestination,
              let pendingSelectionMove,
              pendingSelectionMove.selectionStableKey == selection?.stableKey
        else { return nil }
        selectScope(notice.destinationScope)
        if selectedScope == notice.destinationScope {
            selectionMoveNotice?.canViewDestination = false
            restartSelectionMoveNoticeDismissal()
            return pendingSelectionMove.result.destinationInsertedRange
        }
        return nil
    }

    func dismissSelectionMoveNotice() {
        clearSelectionMoveNotice()
    }

    func setSelectionMoveNoticeHovered(_ isHovered: Bool, for noticeID: UUID) {
        guard selectionMoveNotice?.id == noticeID else { return }
        guard selectionMoveNoticeIsHovered != isHovered else { return }
        selectionMoveNoticeIsHovered = isHovered
        if isHovered {
            cancelSelectionMoveNoticeDismissal()
        } else {
            restartSelectionMoveNoticeDismissal()
        }
    }

    func dismissSelectionMoveError() {
        selectionMoveError = nil
    }

    func presentImageImportError(_ message: String) {
        imageImportError = message
    }

    func dismissImageImportError() {
        imageImportError = nil
    }

    @discardableResult
    func flushImmediately() -> Bool {
        guard !requiresReloadBeforeWrite else { return false }
        do {
            try flushCurrentDocument()
            return true
        } catch {
            pauseForSaveFailure(error)
            return false
        }
    }

    private func runMonitor() async {
        do {
            let initial = try await monitor.bootstrap()
            apply(initial, recordLatency: false)
            await refreshRightPanelState()
        } catch {
            suspendEditing(message: error.localizedDescription)
            publishUnknownRightPanelObservation()
        }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let latest = try await monitor.poll()
                apply(latest, recordLatency: true)
                await refreshRightPanelState()
            } catch is CancellationError {
                return
            } catch {
                suspendEditing(message: error.localizedDescription)
                publishUnknownRightPanelObservation()
            }
        }
    }

    private func refreshRightPanelState() async {
        guard isRightPanelAvoidanceEnabled else { return }
        let avoidanceGeneration = rightPanelAvoidanceGeneration
        let observedSelection = selection
        let accessibilitySample = await accessibilityRightPanelReader.sample()
        guard isRightPanelAvoidanceEnabled,
              rightPanelAvoidanceGeneration == avoidanceGeneration,
              selection?.stableKey == observedSelection?.stableKey else { return }

        if rightPanelAccessibilityPermission != accessibilitySample.permission {
            rightPanelAccessibilityPermission = accessibilitySample.permission
            rightPanelDebouncer.reset()
        }

        let sampledState: CodexRightPanelState
        switch accessibilitySample.permission {
        case .authorized:
            sampledState = accessibilitySample.state
        case .denied:
            guard let threadID = observedSelection?.threadID else {
                publishUnknownRightPanelObservation()
                return
            }
            sampledState = await rightPanelStateReader.state(for: threadID)
            guard isRightPanelAvoidanceEnabled,
                  rightPanelAvoidanceGeneration == avoidanceGeneration,
                  selection?.stableKey == observedSelection?.stableKey else {
                return
            }
        }

        if sampledState == .unknown {
            // Publishing unknown starts the controller's bounded fail-open
            // timer. Reset the edge debouncer as well so the same definite
            // state can be published again after Accessibility recovers.
            rightPanelDebouncer.reset()
            publishUnknownRightPanelObservation()
            return
        }

        guard let observedState = rightPanelDebouncer.observe(sampledState) else {
            return
        }
        let observation = CodexRightPanelObservation(
            selectionStableKey: Self.primaryRightPanelIdentity,
            state: observedState
        )
        if rightPanelObservation != observation {
            rightPanelObservation = observation
        }
    }

    private func publishUnknownRightPanelObservation() {
        let observation = CodexRightPanelObservation(
            selectionStableKey: Self.primaryRightPanelIdentity,
            state: .unknown
        )
        if rightPanelObservation != observation {
            rightPanelObservation = observation
        }
    }

    func apply(_ latest: CodexSelection?, recordLatency: Bool) {
        guard !requiresReloadBeforeWrite else { return }
        guard let latest else {
            if selection == nil {
                suspendEditing(message: L10n.text(.connectionErrorNoTaskSwitchEvent))
            }
            return
        }

        guard latest.kind != .unknown else {
            suspendEditing(message: L10n.text(.connectionErrorUnsupportedTaskType))
            return
        }

        let previousSelection = selection
        let previousMetadata = metadata
        let identityChanged = latest.stableKey != previousSelection?.stableKey

        if identityChanged {
            let mustReloadAfterReadOnlyProject = previousSelection?.kind == .newTask
                && selectedScope == .project
                && activeDocument?.scope == .project
            cancelMetadataRefresh()
            do {
                try flushCurrentDocument()
            } catch {
                clearSelectionMoveNotice()
                isSwitchBlocked = true
                state = .unavailable(
                    L10n.text(
                        .noteSwitchErrorPreviousSaveFailed,
                        replacements: ["error": error.localizedDescription]
                    )
                )
                saveState = .failed(error.localizedDescription)
                return
            }

            invalidateSelectionMoveForIdentityChange()
            resetNewTaskProjectBinding()

            let previousTaskDocument = previousSelection.map {
                noteStore.taskDocument(selection: $0, metadata: previousMetadata)
            }
            let nextMetadata = resolveMetadata(for: latest)
            scheduleNextMetadataRefresh(for: latest)

            if let previousSelection,
               previousSelection.kind == .newTask,
               latest.kind != .newTask,
               previousSelection.conversationID == latest.conversationID,
               let previousTaskDocument {
                let destination = noteStore.taskDocument(selection: latest, metadata: nextMetadata)
                do {
                    _ = try noteStore.mergeDraftIfNeeded(
                        from: previousTaskDocument,
                        into: destination
                    )
                } catch {
                    state = .unavailable(
                        L10n.text(
                            .draftMigrationErrorFailed,
                            replacements: ["error": error.localizedDescription]
                        )
                    )
                    isSwitchBlocked = true
                    saveState = .failed(error.localizedDescription)
                    return
                }
            }

            selection = latest
            metadata = nextMetadata
            isSwitchBlocked = false
            updateConnectionState(for: latest)

            if selectedScope == .project, !projectNoteIsAvailable(in: nextMetadata) {
                selectedScope = .task
            }

            do {
                try activateDocumentForCurrentScope(
                    preservingIfSame: !mustReloadAfterReadOnlyProject
                )
            } catch {
                if mustReloadAfterReadOnlyProject {
                    blockAfterReadOnlyProjectReloadFailure(error)
                } else {
                    suspendEditing(message: error.localizedDescription)
                }
                return
            }

            lastLatencyMilliseconds = recordLatency ? latency(from: latest.timestamp) : nil
            let displayName = metadata?.name ?? fallbackName(for: latest)
            history.insert(
                ProbeHistoryItem(
                    name: displayName,
                    stableKey: latest.stableKey,
                    timestamp: Date()
                ),
                at: 0
            )
            history = Array(history.prefix(5))
            return
        }

        selection = latest
        guard !isSwitchBlocked else { return }
        refreshMetadataIfNeeded(for: latest)
        updateConnectionState(for: latest)

        if activeDocument == nil {
            do {
                try activateDocumentForCurrentScope(preservingIfSame: false)
            } catch {
                suspendEditing(message: error.localizedDescription)
            }
        }
    }

    private func resolveMetadata(for selection: CodexSelection) -> CodexThreadMetadata? {
        if let threadID = selection.threadID {
            return metadataProvider.metadata(for: threadID)
        }
        guard selection.kind == .newTask else { return nil }
        // The route change and Codex's selected-project write are not atomic and
        // have no shared generation. Start unbound; a detected project is exposed
        // as a user-confirmed candidate by refreshMetadataIfNeeded.
        return Self.newTaskMetadata(
            for: selection,
            context: .unknown
        )
    }

    private func refreshMetadataIfNeeded(for selection: CodexSelection) {
        guard metadataRefreshTask == nil,
              selection.threadID != nil || selection.kind == .newTask
        else { return }

        let now = metadataClock.now
        if let nextMetadataRefresh, now < nextMetadataRefresh {
            return
        }
        nextMetadataRefresh = now.advanced(by: refreshInterval(for: selection))

        let provider = metadataProvider
        let projectCandidateProvider = globalProjectCandidateProvider
        let expectedStableKey = selection.stableKey
        let requestID = UUID()
        metadataRefreshRequestID = requestID
        metadataRefreshTask = Task { [weak self] in
            let refreshed = await Task.detached(priority: .utility) {
                if let threadID = selection.threadID {
                    return provider.metadata(for: threadID).map {
                        MetadataRefreshResult.thread($0)
                    }
                }
                guard selection.kind == .newTask else { return nil }
                return MetadataRefreshResult.newTask(
                    projectCandidateProvider.globalProjectCandidate()
                )
            }.value

            guard let self,
                  !Task.isCancelled,
                  self.metadataRefreshRequestID == requestID
            else { return }

            self.metadataRefreshTask = nil
            self.metadataRefreshRequestID = nil

            guard let refreshed else { return }
            switch refreshed {
            case let .thread(metadata):
                self.applyRefreshedMetadata(
                    metadata,
                    expectedStableKey: expectedStableKey
                )
            case let .newTask(context):
                self.applyNewTaskProjectCandidateState(
                    context,
                    expectedStableKey: expectedStableKey
                )
            }
        }
    }

    private func applyNewTaskProjectCandidateState(
        _ context: CodexGlobalProjectCandidateState,
        expectedStableKey: String
    ) {
        guard !isSwitchBlocked,
              let currentSelection = selection,
              currentSelection.kind == .newTask,
              currentSelection.stableKey == expectedStableKey
        else { return }

        switch context {
        case let .selected(project) where Self.supportsNewTaskProject(project):
            if confirmedNewTaskProject == project {
                newTaskProjectCandidate = nil
                applyRefreshedMetadata(
                    Self.newTaskMetadata(
                        for: currentSelection,
                        context: .selected(project)
                    ),
                    expectedStableKey: expectedStableKey
                )
                return
            }

            // A selected-project value is global state and carries no generation
            // that can be correlated with this new-task route. Treat it only as a
            // candidate until the user confirms the visible project name.
            confirmedNewTaskProject = nil
            applyRefreshedMetadata(
                Self.newTaskMetadata(for: currentSelection, context: .unknown),
                expectedStableKey: expectedStableKey
            )
            guard !isSwitchBlocked else {
                newTaskProjectCandidate = nil
                return
            }
            newTaskProjectCandidate = project

        case .none:
            resetNewTaskProjectBinding()
            applyRefreshedMetadata(
                // A process-wide null candidate does not prove that this
                // particular new-task route is projectless.
                Self.newTaskMetadata(for: currentSelection, context: .unknown),
                expectedStableKey: expectedStableKey
            )

        case .unknown, .selected:
            resetNewTaskProjectBinding()
            applyRefreshedMetadata(
                Self.newTaskMetadata(for: currentSelection, context: .unknown),
                expectedStableKey: expectedStableKey
            )
        }
    }

    private func resetNewTaskProjectBinding() {
        confirmedNewTaskProject = nil
        newTaskProjectCandidate = nil
    }

    private func applyRefreshedMetadata(
        _ refreshed: CodexThreadMetadata,
        expectedStableKey: String
    ) {
        guard !isSwitchBlocked,
              let currentSelection = selection,
              currentSelection.stableKey == expectedStableKey,
              metadata(refreshed, belongsTo: currentSelection)
        else { return }

        let refreshed = currentSelection.kind == .newTask
            ? refreshed
            : preservingKnownProjectMembership(in: refreshed, previous: metadata)
        guard metadata != refreshed else { return }
        invalidateSelectionMoveIfDocumentsChanged(
            selection: currentSelection,
            metadata: refreshed
        )

        if selectedScope == .project, !projectNoteIsAvailable(in: refreshed) {
            switchFromUnavailableProjectToTask(
                metadata: refreshed,
                selection: currentSelection
            )
            return
        }

        if selectedScope == .project,
           let currentDocument = activeDocument,
           currentDocument.scope == .project {
            let nextDocument: NoteDocument
            do {
                nextDocument = try noteStore.projectDocument(
                    selection: currentSelection,
                    metadata: refreshed
                )
            } catch NoteStoreError.projectUnavailable {
                switchFromUnavailableProjectToTask(
                    metadata: refreshed,
                    selection: currentSelection
                )
                return
            } catch {
                blockForProjectMetadataFailure(error)
                return
            }

            if nextDocument.stableKey != currentDocument.stableKey
                || nextDocument.fileURL != currentDocument.fileURL {
                switchActiveProjectDocument(to: nextDocument, metadata: refreshed)
                return
            }

            metadata = refreshed
            activeDocument = nextDocument
            refreshChecklistProgresses()
            return
        }

        metadata = refreshed
        if let currentDocument = activeDocument,
           currentDocument.scope == .task {
            activeDocument = noteStore.taskDocument(
                selection: currentSelection,
                metadata: refreshed
            )
        }
        refreshChecklistProgresses()
    }

    private func metadata(
        _ metadata: CodexThreadMetadata,
        belongsTo selection: CodexSelection
    ) -> Bool {
        if let threadID = selection.threadID {
            return metadata.id == threadID
        }
        return selection.kind == .newTask && metadata.id == selection.stableKey
    }

    nonisolated private static func newTaskMetadata(
        for selection: CodexSelection,
        context: CodexGlobalProjectCandidateState
    ) -> CodexThreadMetadata {
        let name = L10n.text(.taskFallbackNewUncreated)
        switch context {
        case .none, .unknown:
            return CodexThreadMetadata(
                id: selection.stableKey,
                name: name,
                cwd: "",
                projectMembership: .unknown
            )
        case let .selected(project):
            // NoteStore currently keys remote project notes with selection.hostID.
            // A new-task route has no host ID, so enabling a remote project here
            // would create a second, incorrectly bound project note.
            guard supportsNewTaskProject(project) else {
                return CodexThreadMetadata(
                    id: selection.stableKey,
                    name: name,
                    cwd: "",
                    projectMembership: .unknown
                )
            }
            return CodexThreadMetadata(
                id: selection.stableKey,
                name: name,
                cwd: project.rootPath,
                projectMembership: project.membership
            )
        }
    }

    nonisolated private static func supportsNewTaskProject(
        _ project: CodexGlobalProjectCandidate
    ) -> Bool {
        project.kind == "local" && project.hostID == nil
    }

    private func switchActiveProjectDocument(
        to nextDocument: NoteDocument,
        metadata refreshed: CodexThreadMetadata
    ) {
        switchActiveDocument(
            to: nextDocument,
            scope: .project,
            metadata: refreshed
        )
    }

    private func switchFromUnavailableProjectToTask(
        metadata refreshed: CodexThreadMetadata,
        selection: CodexSelection
    ) {
        let taskDocument = noteStore.taskDocument(selection: selection, metadata: refreshed)
        switchActiveDocument(to: taskDocument, scope: .task, metadata: refreshed)
    }

    private func switchActiveDocument(
        to nextDocument: NoteDocument,
        scope: NoteScope,
        metadata refreshed: CodexThreadMetadata
    ) {
        do {
            try flushCurrentDocument()
        } catch {
            pauseForSaveFailure(error)
            return
        }

        let loaded: String
        do {
            loaded = try noteStore.load(nextDocument)
        } catch {
            blockForProjectMetadataFailure(error)
            return
        }

        autosaveTask?.cancel()
        isLoadingDocument = true
        metadata = refreshed
        selectedScope = scope
        activeDocument = nextDocument
        noteText = loaded
        isLoadingDocument = false
        updateChecklistProgress(for: scope, text: loaded)
        refreshInactiveChecklistProgress()
        editRevision += 1
        saveState = .saved
    }

    private func blockForProjectMetadataFailure(_ error: Error) {
        autosaveTask?.cancel()
        state = .unavailable(
            L10n.text(
                .projectNoteErrorMetadataSwitchFailed,
                replacements: ["error": error.localizedDescription]
            )
        )
        saveState = .failed(error.localizedDescription)
        isSwitchBlocked = true
    }

    private func blockAfterReadOnlyProjectReloadFailure(_ error: Error) {
        // The selection already belongs to the newly established task, while
        // the editor still contains an untrusted read-only candidate buffer.
        // Never let generic failure handling flush that buffer under the new
        // writable identity.
        autosaveTask?.cancel()
        clearEditor()
        state = .unavailable(
            L10n.text(
                .projectNoteErrorPostCreationReloadFailed,
                replacements: ["error": error.localizedDescription]
            )
        )
        saveState = .failed(error.localizedDescription)
        isSwitchBlocked = true
    }

    private func refreshInterval(for selection: CodexSelection) -> Duration {
        selection.kind == .newTask
            ? newTaskProjectRefreshInterval
            : metadataRefreshInterval
    }

    private func scheduleNextMetadataRefresh(for selection: CodexSelection) {
        let interval: Duration = selection.kind == .newTask ? .zero : metadataRefreshInterval
        nextMetadataRefresh = metadataClock.now.advanced(by: interval)
    }

    private func cancelMetadataRefresh() {
        metadataRefreshTask?.cancel()
        metadataRefreshTask = nil
        metadataRefreshRequestID = nil
        nextMetadataRefresh = nil
    }

    private func updateConnectionState(for selection: CodexSelection) {
        state = selection.kind == .newTask ? .newTask : .detected
    }

    private func activateDocumentForCurrentScope(preservingIfSame: Bool) throws {
        guard let selection else {
            clearEditor()
            return
        }

        let document: NoteDocument
        switch selectedScope {
        case .task:
            document = noteStore.taskDocument(selection: selection, metadata: metadata)
        case .project:
            document = try noteStore.projectDocument(selection: selection, metadata: metadata)
        }

        if preservingIfSame,
           let activeDocument,
           activeDocument.scope == document.scope,
           activeDocument.stableKey == document.stableKey {
            self.activeDocument = document
            refreshChecklistProgresses()
            return
        }

        let loaded = try noteStore.load(document)
        autosaveTask?.cancel()
        isLoadingDocument = true
        activeDocument = document
        noteText = loaded
        isLoadingDocument = false
        updateChecklistProgress(for: document.scope, text: loaded)
        refreshInactiveChecklistProgress()
        editRevision += 1
        saveState = .saved
    }

    private func refreshChecklistProgresses() {
        guard activeDocument != nil else {
            taskChecklistProgress = nil
            projectChecklistProgress = nil
            return
        }

        updateChecklistProgress(for: selectedScope, text: noteText)
        refreshInactiveChecklistProgress()
    }

    private func refreshInactiveChecklistProgress() {
        guard let selection else {
            taskChecklistProgress = nil
            projectChecklistProgress = nil
            return
        }

        let inactiveScope: NoteScope = selectedScope == .task ? .project : .task
        if inactiveScope == .project, !projectNoteIsAvailable(in: metadata) {
            projectChecklistProgress = nil
            return
        }

        let document: NoteDocument
        do {
            switch inactiveScope {
            case .task:
                document = noteStore.taskDocument(selection: selection, metadata: metadata)
            case .project:
                document = try noteStore.projectDocument(selection: selection, metadata: metadata)
            }
        } catch {
            updateChecklistProgress(for: inactiveScope, progress: nil)
            return
        }

        do {
            let text = try noteStore.load(document)
            updateChecklistProgress(for: inactiveScope, text: text)
        } catch {
            // An inactive note is supplementary status. A read failure must not block
            // editing the active note; switching to it will still surface the real error.
            updateChecklistProgress(for: inactiveScope, progress: nil)
        }
    }

    private func updateChecklistProgress(for scope: NoteScope, text: String) {
        updateChecklistProgress(for: scope, progress: MarkdownChecklist.progress(in: text))
    }

    private func updateChecklistProgress(
        for scope: NoteScope,
        progress: MarkdownChecklistProgress?
    ) {
        switch scope {
        case .task:
            taskChecklistProgress = progress
        case .project:
            projectChecklistProgress = progress
        }
    }

    private func document(
        for scope: NoteScope,
        selection: CodexSelection,
        metadata: CodexThreadMetadata?
    ) throws -> NoteDocument {
        switch scope {
        case .task:
            return noteStore.taskDocument(selection: selection, metadata: metadata)
        case .project:
            return try noteStore.projectDocument(selection: selection, metadata: metadata)
        }
    }

    private func applySuccessfulSelectionMove(
        _ result: NoteSelectionMoveResult,
        selectionStableKey: String
    ) {
        autosaveTask?.cancel()
        isLoadingDocument = true
        noteText = result.sourceTextAfter
        isLoadingDocument = false
        updateProgresses(
            for: result,
            sourceText: result.sourceTextAfter,
            destinationText: result.destinationTextAfter
        )
        editRevision += 1
        saveState = .saved
        pendingSelectionMove = PendingSelectionMove(
            result: result,
            selectionStableKey: selectionStableKey
        )
        selectionMoveNoticeIsHovered = false
        selectionMoveNotice = SelectionMoveNotice(
            destinationScope: result.destinationDocument.scope,
            destinationName: selectionMoveDestinationName(
                scope: result.destinationDocument.scope,
                fallback: result.destinationDocument.displayName
            ),
            canUndo: true,
            canViewDestination: true
        )
        restartSelectionMoveNoticeDismissal()
        selectionMoveError = nil
    }

    private func applySuccessfulSelectionMoveUndo(_ result: NoteSelectionMoveResult) {
        isLoadingDocument = true
        if let activeDocument, sameDocument(activeDocument, result.sourceDocument) {
            noteText = result.sourceTextBefore
        } else if let activeDocument,
                  sameDocument(activeDocument, result.destinationDocument) {
            noteText = result.destinationTextBefore
        }
        isLoadingDocument = false
        updateProgresses(
            for: result,
            sourceText: result.sourceTextBefore,
            destinationText: result.destinationTextBefore
        )
        editRevision += 1
        saveState = .saved
        clearSelectionMoveNotice()
        selectionMoveError = nil
    }

    private func updateProgresses(
        for result: NoteSelectionMoveResult,
        sourceText: String,
        destinationText: String
    ) {
        updateChecklistProgress(for: result.sourceDocument.scope, text: sourceText)
        updateChecklistProgress(for: result.destinationDocument.scope, text: destinationText)
    }

    private func currentEditorMatchesMovedResult(_ result: NoteSelectionMoveResult) -> Bool {
        guard let activeDocument else { return false }
        if sameDocument(activeDocument, result.sourceDocument) {
            return noteText == result.sourceTextAfter
        }
        if sameDocument(activeDocument, result.destinationDocument) {
            return noteText == result.destinationTextAfter
        }
        return false
    }

    private func sameDocument(_ first: NoteDocument, _ second: NoteDocument) -> Bool {
        first.scope == second.scope
            && first.stableKey == second.stableKey
            && first.fileURL.standardizedFileURL == second.fileURL.standardizedFileURL
    }

    private func selectedText(in sourceText: String, range: NSRange) -> String? {
        let source = sourceText as NSString
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0,
              range.location <= source.length,
              range.length <= source.length - range.location
        else { return nil }
        return source.substring(with: range)
    }

    private func reportSelectionMoveError(_ error: Error) {
        selectionMoveError = error.localizedDescription
    }

    private func invalidateSelectionMoveUndoAfterEdit() {
        guard pendingSelectionMove != nil else { return }
        selectionMoveNotice?.canUndo = false
    }

    private func invalidateSelectionMoveForIdentityChange() {
        clearSelectionMoveNotice()
        selectionMoveError = nil
    }

    private func restartSelectionMoveNoticeDismissal() {
        cancelSelectionMoveNoticeDismissal()
        guard selectionMoveNotice != nil,
              pendingSelectionMove != nil,
              !selectionMoveNoticeIsHovered
        else { return }

        let requestID = UUID()
        let duration = selectionMoveNoticeDuration
        selectionMoveNoticeDismissalRequestID = requestID
        selectionMoveNoticeDismissalCancellation = selectionMoveNoticeScheduler(
            duration
        ) { [weak self] in
            self?.expireSelectionMoveNotice(requestID: requestID)
        }
    }

    private func cancelSelectionMoveNoticeDismissal() {
        selectionMoveNoticeDismissalRequestID = nil
        selectionMoveNoticeDismissalCancellation?()
        selectionMoveNoticeDismissalCancellation = nil
    }

    private func expireSelectionMoveNotice(requestID: UUID) {
        guard selectionMoveNoticeDismissalRequestID == requestID,
              !selectionMoveNoticeIsHovered
        else { return }
        selectionMoveNoticeDismissalRequestID = nil
        selectionMoveNoticeDismissalCancellation = nil
        selectionMoveNotice = nil
        pendingSelectionMove = nil
    }

    private static let mainQueueSelectionMoveNoticeScheduler:
        SelectionMoveNoticeScheduler = { duration, action in
            let task = Task { @MainActor in
                do {
                    try await Task.sleep(for: duration)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                action()
            }
            return {
                task.cancel()
            }
        }

    private func clearSelectionMoveNotice() {
        cancelSelectionMoveNoticeDismissal()
        selectionMoveNoticeIsHovered = false
        selectionMoveNotice = nil
        pendingSelectionMove = nil
    }

    private func invalidateSelectionMoveIfDocumentsChanged(
        selection: CodexSelection,
        metadata: CodexThreadMetadata
    ) {
        guard let pendingSelectionMove else { return }

        let expectedTask = noteStore.taskDocument(selection: selection, metadata: metadata)
        guard let expectedProject = try? noteStore.projectDocument(
            selection: selection,
            metadata: metadata
        ) else {
            invalidateSelectionMoveForIdentityChange()
            return
        }

        let result = pendingSelectionMove.result
        let expectedSource = result.sourceDocument.scope == .task
            ? expectedTask
            : expectedProject
        let expectedDestination = result.destinationDocument.scope == .task
            ? expectedTask
            : expectedProject
        guard sameDocument(result.sourceDocument, expectedSource),
              sameDocument(result.destinationDocument, expectedDestination)
        else {
            invalidateSelectionMoveForIdentityChange()
            return
        }
    }

    private func selectionMoveDestinationName(
        scope: NoteScope,
        fallback: String
    ) -> String {
        let preferred: String?
        switch scope {
        case .task:
            preferred = metadata?.name
        case .project:
            preferred = metadata?.projectName
        }
        guard let preferred = preferred?.trimmingCharacters(in: .whitespacesAndNewlines),
              !preferred.isEmpty
        else { return fallback }
        return preferred
    }

    private func isStaleSelectionMoveUndoError(_ error: Error) -> Bool {
        guard let error = error as? NoteSelectionMoveError else { return false }
        switch error {
        case .staleUndoSource, .staleUndoDestination:
            return true
        default:
            return false
        }
    }

    private func requiresSelectionMoveSafetyPause(_ error: Error) -> Bool {
        guard let error = error as? NoteSelectionMoveError else { return false }
        switch error {
        case .staleMoveSource, .writeStateUnknown, .rollbackFailed:
            return true
        default:
            return false
        }
    }

    private func projectNoteIsAvailable(in metadata: CodexThreadMetadata?) -> Bool {
        guard metadata?.projectMembership.isAssigned == true,
              let cwd = metadata?.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return false }
        return !cwd.isEmpty
    }

    private func preservingKnownProjectMembership(
        in incoming: CodexThreadMetadata,
        previous: CodexThreadMetadata?
    ) -> CodexThreadMetadata {
        guard case .unknown = incoming.projectMembership,
              let previous,
              previous.id == incoming.id
        else { return incoming }

        guard case .unknown = previous.projectMembership else {
            return CodexThreadMetadata(
                id: incoming.id,
                name: incoming.name,
                cwd: incoming.cwd,
                projectMembership: previous.projectMembership
            )
        }
        return incoming
    }

    private func scheduleAutosave() {
        guard !requiresReloadBeforeWrite,
              !isNewTaskProjectReadOnly,
              let document = activeDocument
        else { return }
        autosaveTask?.cancel()
        editRevision += 1
        let revision = editRevision
        let textSnapshot = noteText
        saveState = .saving

        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                try self?.noteStore.save(textSnapshot, to: document)
                guard let self,
                      self.activeDocument?.stableKey == document.stableKey,
                      self.activeDocument?.scope == document.scope,
                      self.editRevision == revision
                else { return }
                self.saveState = .saved
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.activeDocument?.stableKey == document.stableKey,
                      self.activeDocument?.scope == document.scope,
                      self.editRevision == revision
                else { return }
                self.pauseForSaveFailure(error)
            }
        }
    }

    private func flushCurrentDocument() throws {
        autosaveTask?.cancel()
        guard !requiresReloadBeforeWrite else {
            throw SelectionMoveCoordinationError.reloadRequiredBeforeWrite
        }
        guard let activeDocument else { return }
        guard !isNewTaskProjectReadOnly else {
            editRevision += 1
            saveState = .saved
            return
        }
        try noteStore.save(noteText, to: activeDocument)
        editRevision += 1
        saveState = .saved
    }

    private func suspendEditing(message: String) {
        guard !requiresReloadBeforeWrite else { return }
        var preservedUnsavedText = false
        do {
            try flushCurrentDocument()
        } catch {
            saveState = .failed(error.localizedDescription)
            preservedUnsavedText = true
        }
        state = .unavailable(message)
        isSwitchBlocked = true
        clearSelectionMoveNotice()
        if !preservedUnsavedText {
            clearEditor()
        }
    }

    func pauseForSelectionMoveSafety(_ error: Error) {
        shouldResumeMonitoringAfterSafetyReload =
            shouldResumeMonitoringAfterSafetyReload || monitoringTask != nil
        monitoringTask?.cancel()
        monitoringTask = nil
        cancelMetadataRefresh()
        autosaveTask?.cancel()
        requiresReloadBeforeWrite = true
        clearSelectionMoveNotice()
        selectionMoveError = error.localizedDescription
        saveState = .failed(error.localizedDescription)
        state = .unavailable(
            L10n.text(
                .noteSafetyErrorDiskChanged,
                replacements: ["error": error.localizedDescription]
            )
        )
        isSwitchBlocked = true
    }

    private func reloadCurrentDocumentAfterSelectionMoveSafetyPause() {
        guard requiresReloadBeforeWrite,
              let activeDocument,
              let selection
        else {
            let error = SelectionMoveCoordinationError.editorUnavailable
            selectionMoveError = error.localizedDescription
            saveState = .failed(error.localizedDescription)
            isSwitchBlocked = true
            return
        }

        guard FileManager.default.fileExists(atPath: activeDocument.fileURL.path) else {
            keepSelectionMoveSafetyPauseAfterReloadFailure(
                NoteStoreError.cannotRead(activeDocument.fileURL.path)
            )
            return
        }

        let loaded: String
        do {
            loaded = try noteStore.load(activeDocument)
        } catch {
            keepSelectionMoveSafetyPauseAfterReloadFailure(error)
            return
        }

        autosaveTask?.cancel()
        isLoadingDocument = true
        noteText = loaded
        isLoadingDocument = false
        updateChecklistProgress(for: activeDocument.scope, text: loaded)
        refreshInactiveChecklistProgress()
        editRevision += 1
        requiresReloadBeforeWrite = false
        isSwitchBlocked = false
        saveState = .saved
        selectionMoveError = nil
        updateConnectionState(for: selection)

        let shouldResumeMonitoring = shouldResumeMonitoringAfterSafetyReload
        shouldResumeMonitoringAfterSafetyReload = false
        if shouldResumeMonitoring {
            start()
        }
    }

    private func keepSelectionMoveSafetyPauseAfterReloadFailure(_ error: Error) {
        selectionMoveError = error.localizedDescription
        saveState = .failed(error.localizedDescription)
        state = .unavailable(
            L10n.text(
                .noteSafetyErrorReloadFailed,
                replacements: ["error": error.localizedDescription]
            )
        )
        isSwitchBlocked = true
    }

    private func pauseForSaveFailure(_ error: Error) {
        autosaveTask?.cancel()
        clearSelectionMoveNotice()
        saveState = .failed(error.localizedDescription)
        state = .unavailable(
            L10n.text(
                .noteSaveErrorDraftPreserved,
                replacements: ["error": error.localizedDescription]
            )
        )
        isSwitchBlocked = true
    }

    private func clearEditor() {
        autosaveTask?.cancel()
        invalidateSelectionMoveForIdentityChange()
        isLoadingDocument = true
        activeDocument = nil
        noteText = ""
        isLoadingDocument = false
        taskChecklistProgress = nil
        projectChecklistProgress = nil
        editRevision += 1
    }

    private func fallbackName(for selection: CodexSelection) -> String {
        switch selection.kind {
        case .local:
            return selection.hostID == nil
                ? L10n.text(.taskFallbackLocal)
                : L10n.text(.taskFallbackRemote)
        case .work:
            return L10n.text(.taskFallbackWork)
        case .newTask:
            return L10n.text(.taskFallbackNewUncreated)
        case .unknown:
            return L10n.text(.taskFallbackUnknown)
        }
    }

    private func latency(from timestamp: String) -> Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let eventDate = formatter.date(from: timestamp) else { return nil }
        return max(0, Int(Date().timeIntervalSince(eventDate) * 1_000))
    }
}
