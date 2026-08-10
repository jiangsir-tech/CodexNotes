import Foundation
import XCTest
@testable import CodexNotesCore
@testable import CodexNotesProbe

@MainActor
final class ProbeViewModelNewTaskProjectContextTests: XCTestCase {
    func testNewTaskInsideSelectedProjectCanOpenExistingProjectNote() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = newTaskSelection()
        let context = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let metadata = newTaskMetadata(selection: selection, context: context)
        let store = NoteStore(rootURL: root)
        let projectDocument = try store.projectDocument(selection: selection, metadata: metadata)
        try store.save("- [ ] 项目里的待办", to: projectDocument)
        let model = makeModel(store: store, globalProjectCandidateState: context)

        try await applyAndConfirmSelectedProject(
            model,
            selection: selection,
            expectedPath: "/tmp/project-a"
        )

        XCTAssertTrue(model.canUseProjectNote)
        XCTAssertEqual(model.metadata?.projectName, "Project A")
        XCTAssertEqual(model.metadata?.cwd, "/tmp/project-a")
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 1)
        )

        model.selectScope(.project)

        XCTAssertEqual(model.selectedScope, .project)
        XCTAssertEqual(model.activeDocument?.fileURL, projectDocument.fileURL)
        XCTAssertEqual(model.noteText, "- [ ] 项目里的待办")
        XCTAssertTrue(model.isNewTaskProjectReadOnly)
        XCTAssertFalse(model.canEdit)
        XCTAssertFalse(model.canWriteProjectNote)
    }

    func testConfirmedNewTaskProjectAutosaveAndFlushCannotOverwriteProjectNote() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = newTaskSelection()
        let context = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let metadata = newTaskMetadata(selection: selection, context: context)
        let store = NoteStore(rootURL: root)
        let projectDocument = try store.projectDocument(selection: selection, metadata: metadata)
        try store.save("只读项目原文", to: projectDocument)
        let model = makeModel(store: store, globalProjectCandidateState: context)

        try await applyAndConfirmSelectedProject(
            model,
            selection: selection,
            expectedPath: "/tmp/project-a"
        )
        model.selectScope(.project)

        XCTAssertEqual(model.noteText, "只读项目原文")
        XCTAssertTrue(model.isNewTaskProjectReadOnly)
        XCTAssertFalse(model.canEdit)

        // Bypass the disabled editor to prove both write paths defend themselves.
        model.noteText = "不应写入项目文件"
        XCTAssertTrue(model.flushImmediately())
        try await Task.sleep(for: .milliseconds(550))

        XCTAssertEqual(try store.load(projectDocument), "只读项目原文")
        XCTAssertEqual(model.saveState, .saved)
    }

    func testNewTaskCannotMoveTaskSelectionIntoReadOnlyProjectNote() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = newTaskSelection()
        let context = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let metadata = newTaskMetadata(selection: selection, context: context)
        let store = NoteStore(rootURL: root)
        let projectDocument = try store.projectDocument(selection: selection, metadata: metadata)
        try store.save("项目原文", to: projectDocument)
        let model = makeModel(store: store, globalProjectCandidateState: context)

        try await applyAndConfirmSelectedProject(
            model,
            selection: selection,
            expectedPath: "/tmp/project-a"
        )
        model.noteText = "移动我"
        XCTAssertTrue(model.flushImmediately())
        let taskDocument = try XCTUnwrap(model.activeDocument)
        let sourceText = model.noteText
        let range = (sourceText as NSString).range(of: sourceText)
        let snapshot = EditorSelectionSnapshot(
            document: taskDocument,
            destinationDocument: projectDocument,
            selectionStableKey: selection.stableKey,
            sourceText: sourceText,
            range: range,
            selectedText: sourceText
        )

        XCTAssertNil(
            model.moveSelection(
                snapshot,
                to: .project,
                expectedSelectionStableKey: selection.stableKey
            )
        )

        XCTAssertEqual(
            model.selectionMoveError,
            L10n.text(.selectionMoveErrorProjectReadOnly)
        )
        XCTAssertEqual(model.noteText, "移动我")
        XCTAssertEqual(try store.load(taskDocument), "移动我")
        XCTAssertEqual(try store.load(projectDocument), "项目原文")
        XCTAssertNil(model.selectionMoveNotice)
    }

    func testSelectedProjectChangeSavesOldProjectBeforeLoadingNewProject() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = newTaskSelection()
        let contextA = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let contextB = selectedLocalProject(id: "project-b", path: "/tmp/project-b")
        let provider = MutableGlobalProjectCandidateProvider(contextA)
        let store = NoteStore(rootURL: root)
        let metadataA = newTaskMetadata(selection: selection, context: contextA)
        let projectDocumentA = try store.projectDocument(selection: selection, metadata: metadataA)
        try store.save("项目 A 原有内容", to: projectDocumentA)
        let metadataB = newTaskMetadata(selection: selection, context: contextB)
        let projectDocumentB = try store.projectDocument(selection: selection, metadata: metadataB)
        try store.save("项目 B 原有内容", to: projectDocumentB)
        let model = makeModel(
            store: store,
            globalProjectCandidateProvider: provider
        )

        try await applyAndConfirmSelectedProject(
            model,
            selection: selection,
            expectedPath: "/tmp/project-a"
        )
        model.selectScope(.project)
        XCTAssertEqual(model.noteText, "项目 A 原有内容")

        provider.set(contextB)
        model.apply(selection, recordLatency: true)
        try await waitUntil {
            model.newTaskProjectCandidate?.rootPath == "/tmp/project-b"
                && model.selectedScope == .task
        }

        XCTAssertEqual(
            try store.load(projectDocumentA),
            "项目 A 原有内容"
        )
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)

        XCTAssertTrue(model.confirmNewTaskProject())
        model.selectScope(.project)

        XCTAssertEqual(model.selectedScope, .project)
        XCTAssertEqual(model.activeDocument?.fileURL, projectDocumentB.fileURL)
        XCTAssertEqual(model.noteText, "项目 B 原有内容")
        XCTAssertTrue(model.canUseProjectNote)
    }

    func testLeavingSelectedProjectSavesProjectAndReturnsToTaskDraft() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = newTaskSelection()
        let context = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let provider = MutableGlobalProjectCandidateProvider(context)
        let store = NoteStore(rootURL: root)
        let projectDocument = try store.projectDocument(
            selection: selection,
            metadata: newTaskMetadata(selection: selection, context: context)
        )
        try store.save("离开项目前的只读内容", to: projectDocument)
        let model = makeModel(
            store: store,
            globalProjectCandidateProvider: provider
        )

        try await applyAndConfirmSelectedProject(
            model,
            selection: selection,
            expectedPath: "/tmp/project-a"
        )
        model.noteText = "新任务草稿"
        XCTAssertTrue(model.flushImmediately())
        model.selectScope(.project)
        XCTAssertEqual(model.noteText, "离开项目前的只读内容")

        provider.set(.none)
        model.apply(selection, recordLatency: true)
        try await waitUntil {
            provider.callCount >= 3
                && model.metadata?.projectMembership == CodexProjectMembership.unknown
                && model.selectedScope == .task
        }

        XCTAssertEqual(try store.load(projectDocument), "离开项目前的只读内容")
        XCTAssertEqual(model.noteText, "新任务草稿")
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertNil(model.projectChecklistProgress)
    }

    func testUnknownSelectedProjectDoesNotKeepEditingPreviousProject() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = newTaskSelection()
        let context = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let provider = MutableGlobalProjectCandidateProvider(context)
        let store = NoteStore(rootURL: root)
        let projectDocument = try store.projectDocument(
            selection: selection,
            metadata: newTaskMetadata(selection: selection, context: context)
        )
        try store.save("无法识别时也不应重写", to: projectDocument)
        let model = makeModel(
            store: store,
            globalProjectCandidateProvider: provider
        )

        try await applyAndConfirmSelectedProject(
            model,
            selection: selection,
            expectedPath: "/tmp/project-a"
        )
        model.noteText = "保留的任务草稿"
        XCTAssertTrue(model.flushImmediately())
        model.selectScope(.project)
        XCTAssertEqual(model.noteText, "无法识别时也不应重写")

        provider.set(.unknown)
        model.apply(selection, recordLatency: true)
        try await waitUntil {
            model.metadata?.projectMembership == .unknown
                && model.selectedScope == .task
        }

        XCTAssertEqual(
            try store.load(projectDocument),
            "无法识别时也不应重写"
        )
        XCTAssertEqual(model.noteText, "保留的任务草稿")
        XCTAssertFalse(model.canUseProjectNote)
    }

    func testNewTaskBecomingThreadInSameProjectKeepsProjectNoteAndMigratesTaskDraft() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let draftSelection = newTaskSelection()
        let finalSelection = threadSelection(
            id: "thread-a",
            conversationID: draftSelection.conversationID
        )
        let context = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let finalMetadata = threadMetadata(
            id: "thread-a",
            projectID: "project-a",
            path: "/tmp/project-a"
        )
        let store = NoteStore(rootURL: root)
        let draftProjectDocument = try store.projectDocument(
            selection: draftSelection,
            metadata: newTaskMetadata(selection: draftSelection, context: context)
        )
        try store.save("同一项目笔记不应重载", to: draftProjectDocument)
        let model = makeModel(
            store: store,
            threadMetadata: ["thread-a": finalMetadata],
            globalProjectCandidateState: context
        )

        try await applyAndConfirmSelectedProject(
            model,
            selection: draftSelection,
            expectedPath: "/tmp/project-a"
        )
        model.noteText = "需要迁移的任务草稿"
        XCTAssertTrue(model.flushImmediately())
        model.selectScope(.project)
        XCTAssertEqual(model.noteText, "同一项目笔记不应重载")
        XCTAssertTrue(model.isNewTaskProjectReadOnly)
        XCTAssertFalse(model.canEdit)

        // Defend against any AppKit action that mutates the read-only in-memory
        // buffer: the real task assignment must reload the canonical file.
        model.noteText = "只读阶段不应被带入正式项目"
        XCTAssertEqual(try store.load(draftProjectDocument), "同一项目笔记不应重载")

        model.apply(finalSelection, recordLatency: true)

        XCTAssertEqual(model.metadata, finalMetadata)
        XCTAssertEqual(model.selectedScope, .project)
        XCTAssertEqual(model.activeDocument?.stableKey, draftProjectDocument.stableKey)
        XCTAssertEqual(model.activeDocument?.fileURL, draftProjectDocument.fileURL)
        XCTAssertEqual(model.noteText, "同一项目笔记不应重载")
        XCTAssertEqual(try store.load(draftProjectDocument), "同一项目笔记不应重载")
        XCTAssertFalse(model.isNewTaskProjectReadOnly)
        XCTAssertTrue(model.canEdit)
        XCTAssertTrue(model.canWriteProjectNote)

        model.noteText = "正式任务建立后可编辑"
        XCTAssertTrue(model.flushImmediately())
        XCTAssertEqual(try store.load(draftProjectDocument), "正式任务建立后可编辑")

        let finalTaskDocument = store.taskDocument(
            selection: finalSelection,
            metadata: finalMetadata
        )
        XCTAssertEqual(try store.load(finalTaskDocument), "需要迁移的任务草稿")
    }

    func testFailedFormalProjectReloadNeverFlushesReadOnlyCandidateBuffer() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let draftSelection = newTaskSelection()
        let finalSelection = threadSelection(
            id: "thread-reload-failure",
            conversationID: draftSelection.conversationID
        )
        let context = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let finalMetadata = threadMetadata(
            id: "thread-reload-failure",
            projectID: "project-a",
            path: "/tmp/project-a"
        )
        let baselineStore = NoteStore(rootURL: root)
        let projectDocument = try baselineStore.projectDocument(
            selection: draftSelection,
            metadata: newTaskMetadata(selection: draftSelection, context: context)
        )
        try baselineStore.save("磁盘上的可信项目正文", to: projectDocument)

        let readGate = SelectiveReadFailure()
        let writeRecorder = NoteWriteRecorder()
        let store = NoteStore(
            rootURL: root,
            atomicWrite: { data, url in
                writeRecorder.record(url)
                try data.write(to: url, options: .atomic)
            },
            readUTF8: { url in
                try readGate.read(url)
            }
        )
        let model = makeModel(
            store: store,
            threadMetadata: ["thread-reload-failure": finalMetadata],
            globalProjectCandidateState: context
        )

        try await applyAndConfirmSelectedProject(
            model,
            selection: draftSelection,
            expectedPath: "/tmp/project-a"
        )
        model.selectScope(.project)
        XCTAssertEqual(model.noteText, "磁盘上的可信项目正文")
        model.noteText = "不得写回磁盘的只读缓冲"
        readGate.failReads(of: projectDocument.fileURL)
        writeRecorder.reset()

        model.apply(finalSelection, recordLatency: true)

        XCTAssertTrue(model.isSwitchBlocked)
        XCTAssertNil(model.activeDocument)
        XCTAssertEqual(model.noteText, "")
        XCTAssertFalse(
            writeRecorder.recordedURLs.contains(projectDocument.fileURL.standardizedFileURL)
        )
        XCTAssertEqual(
            try String(contentsOf: projectDocument.fileURL, encoding: .utf8),
            "磁盘上的可信项目正文"
        )
    }

    func testNewTaskBecomingThreadInDifferentProjectSavesOldAndLoadsNewProject() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let draftSelection = newTaskSelection()
        let finalSelection = threadSelection(
            id: "thread-b",
            conversationID: draftSelection.conversationID
        )
        let contextA = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let metadataB = threadMetadata(
            id: "thread-b",
            projectID: "project-b",
            path: "/tmp/project-b"
        )
        let store = NoteStore(rootURL: root)
        let projectDocumentA = try store.projectDocument(
            selection: draftSelection,
            metadata: newTaskMetadata(selection: draftSelection, context: contextA)
        )
        try store.save("项目 A 切换前的只读内容", to: projectDocumentA)
        let projectDocumentB = try store.projectDocument(
            selection: finalSelection,
            metadata: metadataB
        )
        try store.save("项目 B 的笔记", to: projectDocumentB)
        let model = makeModel(
            store: store,
            threadMetadata: ["thread-b": metadataB],
            globalProjectCandidateState: contextA
        )

        try await applyAndConfirmSelectedProject(
            model,
            selection: draftSelection,
            expectedPath: "/tmp/project-a"
        )
        model.noteText = "迁移到正式任务 B 的草稿"
        XCTAssertTrue(model.flushImmediately())
        model.selectScope(.project)
        XCTAssertEqual(model.noteText, "项目 A 切换前的只读内容")

        model.apply(finalSelection, recordLatency: true)

        XCTAssertEqual(try store.load(projectDocumentA), "项目 A 切换前的只读内容")
        XCTAssertEqual(model.metadata, metadataB)
        XCTAssertEqual(model.selectedScope, .project)
        XCTAssertEqual(model.activeDocument?.fileURL, projectDocumentB.fileURL)
        XCTAssertEqual(model.noteText, "项目 B 的笔记")
        XCTAssertEqual(
            try store.load(store.taskDocument(selection: finalSelection, metadata: metadataB)),
            "迁移到正式任务 B 的草稿"
        )
    }

    func testNewTaskBecomingProjectlessThreadSavesProjectAndShowsMigratedTaskDraft() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let draftSelection = newTaskSelection()
        let finalSelection = threadSelection(
            id: "thread-projectless",
            conversationID: draftSelection.conversationID
        )
        let context = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let finalMetadata = CodexThreadMetadata(
            id: "thread-projectless",
            name: "独立任务",
            cwd: "/tmp/projectless",
            projectMembership: .none
        )
        let store = NoteStore(rootURL: root)
        let projectDocument = try store.projectDocument(
            selection: draftSelection,
            metadata: newTaskMetadata(selection: draftSelection, context: context)
        )
        try store.save("离开项目前的只读笔记", to: projectDocument)
        let model = makeModel(
            store: store,
            threadMetadata: ["thread-projectless": finalMetadata],
            globalProjectCandidateState: context
        )

        try await applyAndConfirmSelectedProject(
            model,
            selection: draftSelection,
            expectedPath: "/tmp/project-a"
        )
        model.noteText = "独立任务也要保留的草稿"
        XCTAssertTrue(model.flushImmediately())
        model.selectScope(.project)
        XCTAssertEqual(model.noteText, "离开项目前的只读笔记")

        model.apply(finalSelection, recordLatency: true)

        XCTAssertEqual(try store.load(projectDocument), "离开项目前的只读笔记")
        XCTAssertEqual(model.metadata, finalMetadata)
        XCTAssertEqual(model.selectedScope, .task)
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertEqual(model.noteText, "独立任务也要保留的草稿")
    }

    func testEnteringNewTaskWithNoGlobalCandidateDoesNotInheritPreviousThreadProject() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let previousSelection = threadSelection(id: "thread-a", conversationID: "thread-a")
        let previousMetadata = threadMetadata(
            id: "thread-a",
            projectID: "project-a",
            path: "/tmp/project-a"
        )
        let newSelection = newTaskSelection(conversationID: "client-new-thread:next")
        let store = NoteStore(rootURL: root)
        let candidateProvider = MutableGlobalProjectCandidateProvider(.none)
        let model = makeModel(
            store: store,
            threadMetadata: ["thread-a": previousMetadata],
            globalProjectCandidateProvider: candidateProvider
        )

        model.apply(previousSelection, recordLatency: false)
        model.selectScope(.project)
        model.noteText = "前一个项目必须在切换前保存"
        let previousProjectDocument = try XCTUnwrap(model.activeDocument)

        model.apply(newSelection, recordLatency: true)
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        model.apply(newSelection, recordLatency: true)
        try await waitUntil {
            candidateProvider.callCount >= 1
        }

        XCTAssertEqual(
            try store.load(previousProjectDocument),
            "前一个项目必须在切换前保存"
        )
        XCTAssertEqual(model.metadata?.id, newSelection.stableKey)
        XCTAssertEqual(
            model.metadata?.projectMembership,
            CodexProjectMembership.unknown
        )
        XCTAssertEqual(model.selectedScope, .task)
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertEqual(model.noteText, "")
    }

    func testRemoteSelectedProjectStaysDisabledUntilHostBoundProjectNotesAreSupported() {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let remote = CodexGlobalProjectCandidateState.selected(
            CodexGlobalProjectCandidate(
                kind: "remote",
                id: "remote-project",
                name: "Remote Project",
                rootPath: "C:/Users/alice/project",
                hostID: "host-a"
            )
        )
        let model = makeModel(
            store: NoteStore(rootURL: root),
            globalProjectCandidateState: remote
        )

        model.apply(newTaskSelection(), recordLatency: false)

        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertEqual(model.selectedScope, .task)
    }

    func testAABBProjectSequenceNeverAutomaticallyOpensTheOldProject() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = newTaskSelection()
        let contextA = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let contextB = selectedLocalProject(id: "project-b", path: "/tmp/project-b")
        let provider = SequencedGlobalProjectCandidateProvider([
            contextA,
            contextA,
            contextB,
            contextB,
        ])
        let model = makeModel(
            store: NoteStore(rootURL: root),
            globalProjectCandidateProvider: provider
        )

        model.apply(selection, recordLatency: false)
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        XCTAssertFalse(model.canUseProjectNote)

        model.apply(selection, recordLatency: true)
        try await waitUntil { provider.callCount >= 1 }
        XCTAssertEqual(model.newTaskProjectCandidate?.id, "project-a")
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        XCTAssertFalse(model.canUseProjectNote)

        model.apply(selection, recordLatency: true)
        try await waitUntil { provider.callCount >= 2 }
        XCTAssertEqual(model.newTaskProjectCandidate?.id, "project-a")
        XCTAssertFalse(model.canUseProjectNote)

        model.apply(selection, recordLatency: true)
        try await waitUntil {
            provider.callCount >= 3
                && model.newTaskProjectCandidate?.id == "project-b"
        }
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertEqual(model.selectedScope, .task)

        model.apply(selection, recordLatency: true)
        try await waitUntil { provider.callCount >= 4 }
        XCTAssertEqual(model.newTaskProjectCandidate?.id, "project-b")
        XCTAssertFalse(model.canUseProjectNote)

        XCTAssertTrue(model.confirmNewTaskProject())
        XCTAssertTrue(model.canUseProjectNote)
        XCTAssertEqual(model.metadata?.projectName, "Project B")
    }

    func testConfirmRejectsCandidateThatChangedBeforeTheClick() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = newTaskSelection()
        let contextA = selectedLocalProject(id: "project-a", path: "/tmp/project-a")
        let contextB = selectedLocalProject(id: "project-b", path: "/tmp/project-b")
        let provider = MutableGlobalProjectCandidateProvider(contextA)
        let model = makeModel(
            store: NoteStore(rootURL: root),
            globalProjectCandidateProvider: provider
        )

        model.apply(selection, recordLatency: false)
        model.apply(selection, recordLatency: true)
        try await waitUntil { model.newTaskProjectCandidate?.id == "project-a" }

        provider.set(contextB)

        XCTAssertFalse(model.confirmNewTaskProject())
        XCTAssertEqual(model.newTaskProjectCandidate?.id, "project-b")
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        XCTAssertFalse(model.canUseProjectNote)
    }

    private func makeModel(
        store: NoteStore,
        threadMetadata: [String: CodexThreadMetadata] = [:],
        globalProjectCandidateState: CodexGlobalProjectCandidateState
    ) -> ProbeViewModel {
        makeModel(
            store: store,
            threadMetadata: threadMetadata,
            globalProjectCandidateProvider: MutableGlobalProjectCandidateProvider(
                globalProjectCandidateState
            )
        )
    }

    private func makeModel(
        store: NoteStore,
        threadMetadata: [String: CodexThreadMetadata] = [:],
        globalProjectCandidateProvider: any CodexGlobalProjectCandidateProviding
    ) -> ProbeViewModel {
        ProbeViewModel(
            noteStore: store,
            metadataProvider: DictionaryThreadMetadataProvider(threadMetadata),
            globalProjectCandidateProvider: globalProjectCandidateProvider,
            metadataRefreshInterval: .zero,
            newTaskProjectRefreshInterval: .zero
        )
    }

    private func applyAndConfirmSelectedProject(
        _ model: ProbeViewModel,
        selection: CodexSelection,
        expectedPath: String
    ) async throws {
        model.apply(selection, recordLatency: false)
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        XCTAssertFalse(model.canUseProjectNote)

        model.apply(selection, recordLatency: true)
        try await waitUntil {
            model.newTaskProjectCandidate?.rootPath == expectedPath
        }
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        XCTAssertTrue(model.confirmNewTaskProject())
        XCTAssertEqual(model.metadata?.cwd, expectedPath)
        XCTAssertTrue(model.canUseProjectNote)
    }

    private func selectedLocalProject(
        id: String,
        path: String
    ) -> CodexGlobalProjectCandidateState {
        .selected(
            CodexGlobalProjectCandidate(
                kind: "local",
                id: id,
                name: id == "project-a" ? "Project A" : "Project B",
                rootPath: path,
                hostID: nil
            )
        )
    }

    private func newTaskMetadata(
        selection: CodexSelection,
        context: CodexGlobalProjectCandidateState
    ) -> CodexThreadMetadata {
        guard case let .selected(project) = context else {
            return CodexThreadMetadata(
                id: selection.stableKey,
                name: L10n.text(.taskFallbackNewUncreated),
                cwd: "",
                projectMembership: .unknown
            )
        }
        return CodexThreadMetadata(
            id: selection.stableKey,
            name: L10n.text(.taskFallbackNewUncreated),
            cwd: project.rootPath,
            projectMembership: project.membership
        )
    }

    private func threadMetadata(
        id: String,
        projectID: String,
        path: String
    ) -> CodexThreadMetadata {
        CodexThreadMetadata(
            id: id,
            name: "任务 \(id)",
            cwd: path,
            projectMembership: .assigned(
                kind: "local",
                id: projectID,
                name: projectID == "project-a" ? "Project A" : "Project B"
            )
        )
    }

    private func newTaskSelection(
        conversationID: String = "client-new-thread:draft"
    ) -> CodexSelection {
        CodexSelection(
            timestamp: "2026-08-09T00:00:00.000Z",
            conversationID: conversationID,
            route: "/",
            windowID: "1",
            kind: .newTask,
            threadID: nil,
            hostID: nil,
            stableKey: "new:1:\(conversationID)"
        )
    }

    private func threadSelection(
        id: String,
        conversationID: String
    ) -> CodexSelection {
        CodexSelection(
            timestamp: "2026-08-09T00:00:01.000Z",
            conversationID: conversationID,
            route: "/local/\(id)",
            windowID: "1",
            kind: .local,
            threadID: id,
            hostID: nil,
            stableKey: "local:\(id)"
        )
    }

    private func temporaryNoteRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexNewTaskProject-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("等待新任务项目上下文刷新超时")
    }
}

private final class DictionaryThreadMetadataProvider:
    CodexThreadMetadataProviding,
    @unchecked Sendable
{
    private let values: [String: CodexThreadMetadata]

    init(_ values: [String: CodexThreadMetadata]) {
        self.values = values
    }

    func metadata(for threadID: String) -> CodexThreadMetadata? {
        values[threadID]
    }
}

private final class MutableGlobalProjectCandidateProvider:
    CodexGlobalProjectCandidateProviding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var context: CodexGlobalProjectCandidateState
    private var contextCallCount = 0

    init(_ context: CodexGlobalProjectCandidateState) {
        self.context = context
    }

    func set(_ context: CodexGlobalProjectCandidateState) {
        lock.lock()
        self.context = context
        lock.unlock()
    }

    func globalProjectCandidate() -> CodexGlobalProjectCandidateState {
        lock.lock()
        defer { lock.unlock() }
        contextCallCount += 1
        return context
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return contextCallCount
    }
}

private final class SequencedGlobalProjectCandidateProvider:
    CodexGlobalProjectCandidateProviding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var contexts: [CodexGlobalProjectCandidateState]
    private var contextCallCount = 0

    init(_ contexts: [CodexGlobalProjectCandidateState]) {
        precondition(!contexts.isEmpty)
        self.contexts = contexts
    }

    func globalProjectCandidate() -> CodexGlobalProjectCandidateState {
        lock.lock()
        defer { lock.unlock() }
        let index = min(contextCallCount, contexts.count - 1)
        contextCallCount += 1
        return contexts[index]
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return contextCallCount
    }
}

private final class SelectiveReadFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var failedURL: URL?

    func failReads(of url: URL) {
        lock.lock()
        failedURL = url.standardizedFileURL
        lock.unlock()
    }

    func read(_ url: URL) throws -> String {
        lock.lock()
        let shouldFail = failedURL == url.standardizedFileURL
        lock.unlock()
        if shouldFail {
            throw NoteStoreError.cannotRead(url.path)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private final class NoteWriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    func record(_ url: URL) {
        lock.lock()
        urls.append(url.standardizedFileURL)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        urls.removeAll()
        lock.unlock()
    }

    var recordedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urls
    }
}
