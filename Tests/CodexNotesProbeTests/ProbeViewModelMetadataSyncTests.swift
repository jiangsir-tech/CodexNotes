import Foundation
import XCTest
@testable import CodexNotesCore
@testable import CodexNotesProbe

@MainActor
final class ProbeViewModelMetadataSyncTests: XCTestCase {
    func testTaskRenameUpdatesMetadataWithoutReloadingNote() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = MutableMetadataProvider(
            CodexThreadMetadata(
                id: "thread-a",
                name: "旧任务名称",
                cwd: "/tmp/project",
                projectName: "Project A"
            )
        )
        let model = ProbeViewModel(
            noteStore: NoteStore(rootURL: root),
            metadataProvider: provider,
            metadataRefreshInterval: .zero
        )
        let selection = makeSelection()
        model.apply(selection, recordLatency: false)
        model.noteText = "正在编辑且尚未重新加载的正文"

        let originalDocument = try XCTUnwrap(model.activeDocument)
        provider.set(
            CodexThreadMetadata(
                id: "thread-a",
                name: "新任务名称",
                cwd: "/tmp/project",
                projectName: "Project A"
            )
        )

        model.apply(selection, recordLatency: true)
        try await waitUntil { model.metadata?.name == "新任务名称" }

        XCTAssertEqual(model.noteText, "正在编辑且尚未重新加载的正文")
        XCTAssertEqual(model.activeDocument?.stableKey, originalDocument.stableKey)
        XCTAssertEqual(model.activeDocument?.fileURL, originalDocument.fileURL)
    }

    func testProjectRenameUpdatesHeaderWithoutSwitchingProjectNote() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = MutableMetadataProvider(
            CodexThreadMetadata(
                id: "thread-a",
                name: "任务",
                cwd: "/tmp/project",
                projectName: "旧 Project 名称"
            )
        )
        let model = ProbeViewModel(
            noteStore: NoteStore(rootURL: root),
            metadataProvider: provider,
            metadataRefreshInterval: .zero
        )
        let selection = makeSelection()
        model.apply(selection, recordLatency: false)
        model.selectScope(.project)
        model.noteText = "Project 正文保持不动"

        let originalDocument = try XCTUnwrap(model.activeDocument)
        provider.set(
            CodexThreadMetadata(
                id: "thread-a",
                name: "任务",
                cwd: "/tmp/project",
                projectName: "新 Project 名称"
            )
        )

        model.apply(selection, recordLatency: true)
        try await waitUntil { model.metadata?.projectName == "新 Project 名称" }

        XCTAssertEqual(model.noteText, "Project 正文保持不动")
        XCTAssertEqual(model.activeDocument?.stableKey, originalDocument.stableKey)
        XCTAssertEqual(model.activeDocument?.fileURL, originalDocument.fileURL)
    }

    func testTemporaryMetadataReadFailureKeepsExistingNames() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = MutableMetadataProvider(
            CodexThreadMetadata(
                id: "thread-a",
                name: "保留的任务名称",
                cwd: "/tmp/project",
                projectName: "保留的 Project 名称"
            )
        )
        let model = ProbeViewModel(
            noteStore: NoteStore(rootURL: root),
            metadataProvider: provider,
            metadataRefreshInterval: .zero
        )
        let selection = makeSelection()
        model.apply(selection, recordLatency: false)
        provider.set(nil)
        let callsBeforeRefresh = provider.callCount

        model.apply(selection, recordLatency: true)
        try await waitUntil { provider.callCount > callsBeforeRefresh }

        XCTAssertEqual(model.metadata?.name, "保留的任务名称")
        XCTAssertEqual(model.metadata?.projectName, "保留的 Project 名称")
        XCTAssertFalse(model.isSwitchBlocked)
    }

    func testInitialNoneAndUnknownMembershipDisableProjectNote() {
        for (membership, cwd) in [
            (CodexProjectMembership.none, "/tmp/project"),
            (CodexProjectMembership.unknown, "/tmp/project"),
            (
                CodexProjectMembership.assigned(
                    kind: "local",
                    id: "project-a",
                    name: "Project A"
                ),
                "   "
            ),
        ] {
            let root = temporaryNoteRoot()
            defer { try? FileManager.default.removeItem(at: root) }

            let metadata = CodexThreadMetadata(
                id: "thread-a",
                name: "任务",
                cwd: cwd,
                projectMembership: membership
            )
            let model = ProbeViewModel(
                noteStore: NoteStore(rootURL: root),
                metadataProvider: MutableMetadataProvider(metadata)
            )

            model.apply(makeSelection(), recordLatency: false)

            XCTAssertFalse(model.canUseProjectNote)
            XCTAssertEqual(model.selectedScope, .task)
            XCTAssertNil(model.projectChecklistProgress)

            model.selectScope(.project)
            XCTAssertEqual(model.selectedScope, .task)
        }
    }

    func testUnknownRefreshPreservesSameThreadLastKnownMembership() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let assigned = CodexProjectMembership.assigned(
            kind: "local",
            id: "project-a",
            name: "Project A"
        )
        let provider = MutableMetadataProvider(
            CodexThreadMetadata(
                id: "thread-a",
                name: "任务",
                cwd: "/tmp/project",
                projectMembership: assigned
            )
        )
        let model = ProbeViewModel(
            noteStore: NoteStore(rootURL: root),
            metadataProvider: provider,
            metadataRefreshInterval: .zero
        )
        let selection = makeSelection()
        model.apply(selection, recordLatency: false)
        XCTAssertTrue(model.canUseProjectNote)
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 0)
        )
        model.selectScope(.project)
        model.noteText = "unknown 刷新时必须保留的未保存正文"
        let originalProjectDocument = try XCTUnwrap(model.activeDocument)

        provider.set(
            CodexThreadMetadata(
                id: "thread-a",
                name: "unknown 时更新了任务名",
                cwd: "/tmp/project",
                projectMembership: .unknown
            )
        )
        model.apply(selection, recordLatency: true)
        try await waitUntil { model.metadata?.name == "unknown 时更新了任务名" }

        XCTAssertEqual(model.metadata?.projectMembership, assigned)
        XCTAssertTrue(model.canUseProjectNote)
        XCTAssertEqual(model.selectedScope, .project)
        XCTAssertEqual(model.activeDocument?.stableKey, originalProjectDocument.stableKey)
        XCTAssertEqual(model.activeDocument?.fileURL, originalProjectDocument.fileURL)
        XCTAssertEqual(model.noteText, "unknown 刷新时必须保留的未保存正文")

        provider.set(
            CodexThreadMetadata(
                id: "thread-a",
                name: "明确移出项目",
                cwd: "/tmp/project",
                projectMembership: .none
            )
        )
        model.apply(selection, recordLatency: true)
        try await waitUntil { model.metadata?.name == "明确移出项目" }

        XCTAssertEqual(model.metadata?.projectMembership, CodexProjectMembership.none)
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertEqual(model.selectedScope, .task)
        XCTAssertEqual(
            try model.noteStore.load(originalProjectDocument),
            "unknown 刷新时必须保留的未保存正文"
        )
        XCTAssertNil(model.projectChecklistProgress)

        provider.set(
            CodexThreadMetadata(
                id: "thread-a",
                name: "none 后暂时 unknown",
                cwd: "/tmp/project",
                projectMembership: .unknown
            )
        )
        model.apply(selection, recordLatency: true)
        try await waitUntil { model.metadata?.name == "none 后暂时 unknown" }

        XCTAssertEqual(model.metadata?.projectMembership, CodexProjectMembership.none)
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertNil(model.projectChecklistProgress)
    }

    func testUnknownMembershipFromNewThreadDoesNotInheritPreviousAssignment() throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let metadataA = CodexThreadMetadata(
            id: "thread-a",
            name: "任务 A",
            cwd: "/tmp/project-a",
            projectMembership: .assigned(
                kind: "local",
                id: "project-a",
                name: "Project A"
            )
        )
        let metadataB = CodexThreadMetadata(
            id: "thread-b",
            name: "任务 B",
            cwd: "/tmp/project-b",
            projectMembership: .unknown
        )
        let provider = BlockingMetadataProvider(values: [
            "thread-a": metadataA,
            "thread-b": metadataB,
        ])
        let store = NoteStore(rootURL: root)
        let model = ProbeViewModel(
            noteStore: store,
            metadataProvider: provider
        )

        model.apply(makeSelection(id: "thread-a"), recordLatency: false)
        XCTAssertTrue(model.canUseProjectNote)
        model.selectScope(.project)
        model.noteText = "切换新任务前必须保存"
        let oldProjectDocument = try XCTUnwrap(model.activeDocument)

        model.apply(makeSelection(id: "thread-b"), recordLatency: true)

        XCTAssertEqual(try store.load(oldProjectDocument), "切换新任务前必须保存")
        XCTAssertEqual(model.metadata?.id, "thread-b")
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertEqual(model.selectedScope, .task)
        XCTAssertNil(model.projectChecklistProgress)
    }

    func testSameThreadIDDifferentStableIdentityDoesNotInheritMembership() throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let assignedMetadata = CodexThreadMetadata(
            id: "thread-a",
            name: "本地任务 A",
            cwd: "/tmp/project-a",
            projectMembership: .assigned(
                kind: "local",
                id: "project-a",
                name: "Project A"
            )
        )
        let unknownMetadata = CodexThreadMetadata(
            id: "thread-a",
            name: "另一 host 上的任务 A",
            cwd: "/tmp/project-a",
            projectMembership: .unknown
        )
        let provider = MutableMetadataProvider(assignedMetadata)
        let store = NoteStore(rootURL: root)
        let model = ProbeViewModel(noteStore: store, metadataProvider: provider)
        let localSelection = makeSelection(id: "thread-a")
        let remoteSelection = CodexSelection(
            timestamp: "2026-08-08T00:00:01.000Z",
            conversationID: "thread-a",
            route: "/local/thread-a?hostId=host-b",
            windowID: "2",
            kind: .local,
            threadID: "thread-a",
            hostID: "host-b",
            stableKey: "host-b:thread-a"
        )

        model.apply(localSelection, recordLatency: false)
        model.selectScope(.project)
        model.noteText = "身份切换前必须保存"
        let oldProjectDocument = try XCTUnwrap(model.activeDocument)
        provider.set(unknownMetadata)

        model.apply(remoteSelection, recordLatency: true)

        XCTAssertEqual(try store.load(oldProjectDocument), "身份切换前必须保存")
        XCTAssertEqual(model.selection?.stableKey, remoteSelection.stableKey)
        XCTAssertEqual(model.metadata, unknownMetadata)
        XCTAssertEqual(model.metadata?.projectMembership, .unknown)
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertEqual(model.selectedScope, .task)
        XCTAssertEqual(model.activeDocument?.stableKey, remoteSelection.stableKey)
        XCTAssertNil(model.projectChecklistProgress)
    }

    func testSwitchingFromProjectNoteToNewProjectlessTaskSavesThenLoadsTaskNote() throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let metadataA = CodexThreadMetadata(
            id: "thread-a",
            name: "任务 A",
            cwd: "/tmp/project-a",
            projectMembership: .assigned(
                kind: "local",
                id: "project-a",
                name: "Project A"
            )
        )
        let metadataB = CodexThreadMetadata(
            id: "thread-b",
            name: "无项目任务 B",
            cwd: "/tmp/project-b",
            projectMembership: .none
        )
        let selectionA = makeSelection(id: "thread-a")
        let selectionB = makeSelection(id: "thread-b")
        let provider = BlockingMetadataProvider(values: [
            "thread-a": metadataA,
            "thread-b": metadataB,
        ])
        let store = NoteStore(rootURL: root)
        let taskDocumentB = store.taskDocument(selection: selectionB, metadata: metadataB)
        try store.save("新无项目任务的正文", to: taskDocumentB)
        let model = ProbeViewModel(noteStore: store, metadataProvider: provider)

        model.apply(selectionA, recordLatency: false)
        model.selectScope(.project)
        model.noteText = "旧 Project 切换前必须保存"
        let oldProjectDocument = try XCTUnwrap(model.activeDocument)

        model.apply(selectionB, recordLatency: true)

        XCTAssertEqual(try store.load(oldProjectDocument), "旧 Project 切换前必须保存")
        XCTAssertEqual(model.selection?.threadID, "thread-b")
        XCTAssertEqual(model.metadata, metadataB)
        XCTAssertEqual(model.selectedScope, .task)
        XCTAssertEqual(model.activeDocument?.scope, .task)
        XCTAssertEqual(model.activeDocument?.stableKey, selectionB.stableKey)
        XCTAssertEqual(model.noteText, "新无项目任务的正文")
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertNil(model.projectChecklistProgress)
        XCTAssertFalse(model.isSwitchBlocked)
    }

    func testRemovingProjectWhileEditingProjectFallsBackToTaskNote() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = NoteStore(rootURL: root)
        let initialMetadata = CodexThreadMetadata(
            id: "thread-a",
            name: "任务",
            cwd: "/tmp/project",
            projectName: "Project A"
        )
        let provider = MutableMetadataProvider(initialMetadata)
        let model = ProbeViewModel(
            noteStore: store,
            metadataProvider: provider,
            metadataRefreshInterval: .zero
        )
        let selection = makeSelection()
        let taskDocument = store.taskDocument(selection: selection, metadata: initialMetadata)
        try store.save("原来的任务笔记", to: taskDocument)

        model.apply(selection, recordLatency: false)
        model.selectScope(.project)
        model.noteText = "移除 Project 前必须保存的正文"
        let oldProjectDocument = try XCTUnwrap(model.activeDocument)

        provider.set(
            CodexThreadMetadata(
                id: "thread-a",
                name: "任务",
                cwd: "/tmp/project",
                projectMembership: .none
            )
        )
        model.apply(selection, recordLatency: true)
        try await waitUntil { model.selectedScope == .task }

        XCTAssertEqual(try store.load(oldProjectDocument), "移除 Project 前必须保存的正文")
        XCTAssertEqual(model.noteText, "原来的任务笔记")
        XCTAssertEqual(model.activeDocument?.scope, .task)
        XCTAssertNil(model.metadata?.projectName)
        XCTAssertEqual(model.metadata?.projectMembership, CodexProjectMembership.none)
        XCTAssertNil(model.projectChecklistProgress)
        XCTAssertFalse(model.canUseProjectNote)
        XCTAssertFalse(model.isSwitchBlocked)
        XCTAssertEqual(model.saveState, .saved)
    }

    func testProjectPathChangeSavesOldNoteBeforeSwitching() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = NoteStore(rootURL: root)
        let provider = MutableMetadataProvider(
            CodexThreadMetadata(
                id: "thread-a",
                name: "任务",
                cwd: "/tmp/project-a",
                projectName: "Project A"
            )
        )
        let model = ProbeViewModel(
            noteStore: store,
            metadataProvider: provider,
            metadataRefreshInterval: .zero
        )
        let selection = makeSelection()
        model.apply(selection, recordLatency: false)
        model.selectScope(.project)
        model.noteText = "必须先保存到旧 Project 的正文"
        let oldDocument = try XCTUnwrap(model.activeDocument)

        provider.set(
            CodexThreadMetadata(
                id: "thread-a",
                name: "任务",
                cwd: "/tmp/project-b",
                projectName: "Project B"
            )
        )
        model.apply(selection, recordLatency: true)
        try await waitUntil { model.metadata?.cwd == "/tmp/project-b" }

        XCTAssertEqual(try store.load(oldDocument), "必须先保存到旧 Project 的正文")
        XCTAssertNotEqual(model.activeDocument?.stableKey, oldDocument.stableKey)
        XCTAssertEqual(model.noteText, "")
        XCTAssertFalse(model.isSwitchBlocked)
    }

    func testLateMetadataResultFromOldTaskCannotOverwriteNewTask() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let metadataA = CodexThreadMetadata(
            id: "thread-a",
            name: "任务 A",
            cwd: "/tmp/project-a",
            projectName: "Project A"
        )
        let metadataB = CodexThreadMetadata(
            id: "thread-b",
            name: "任务 B",
            cwd: "/tmp/project-b",
            projectName: "Project B"
        )
        let provider = BlockingMetadataProvider(values: [
            "thread-a": metadataA,
            "thread-b": metadataB,
        ])
        let model = ProbeViewModel(
            noteStore: NoteStore(rootURL: root),
            metadataProvider: provider,
            metadataRefreshInterval: .zero
        )
        let selectionA = makeSelection(id: "thread-a")
        let selectionB = makeSelection(id: "thread-b")
        model.apply(selectionA, recordLatency: false)

        provider.set(
            CodexThreadMetadata(
                id: "thread-a",
                name: "任务 A 的迟到结果",
                cwd: "/tmp/project-a",
                projectName: "Project A"
            ),
            for: "thread-a"
        )
        provider.blockNextRequest(for: "thread-a")
        model.apply(selectionA, recordLatency: true)
        try await waitUntil { provider.blockedRequestDidStart }

        model.apply(selectionB, recordLatency: true)
        provider.releaseBlockedRequest()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(model.selection?.threadID, "thread-b")
        XCTAssertEqual(model.metadata, metadataB)
        XCTAssertEqual(model.activeDocument?.stableKey, selectionB.stableKey)
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("等待实时名称同步超时")
    }

    private func temporaryNoteRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexMetadataSync-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeSelection(id: String = "thread-a") -> CodexSelection {
        CodexSelection(
            timestamp: "2026-08-08T00:00:00.000Z",
            conversationID: id,
            route: "/local/\(id)",
            windowID: "1",
            kind: .local,
            threadID: id,
            hostID: nil,
            stableKey: "local:\(id)"
        )
    }
}

private final class MutableMetadataProvider: CodexThreadMetadataProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: CodexThreadMetadata?
    private var metadataCallCount = 0

    init(_ current: CodexThreadMetadata?) {
        self.current = current
    }

    func set(_ metadata: CodexThreadMetadata?) {
        lock.lock()
        current = metadata
        lock.unlock()
    }

    func metadata(for threadID: String) -> CodexThreadMetadata? {
        lock.lock()
        defer { lock.unlock() }
        metadataCallCount += 1
        guard current?.id == threadID else { return nil }
        return current
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return metadataCallCount
    }
}

private final class BlockingMetadataProvider: CodexThreadMetadataProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: CodexThreadMetadata]
    private var blockedThreadID: String?
    private var didStartBlockedRequest = false
    private let blockedRequestRelease = DispatchSemaphore(value: 0)

    init(values: [String: CodexThreadMetadata]) {
        self.values = values
    }

    func set(_ metadata: CodexThreadMetadata, for threadID: String) {
        lock.lock()
        values[threadID] = metadata
        lock.unlock()
    }

    func blockNextRequest(for threadID: String) {
        lock.lock()
        blockedThreadID = threadID
        lock.unlock()
    }

    func metadata(for threadID: String) -> CodexThreadMetadata? {
        lock.lock()
        let result = values[threadID]
        let shouldBlock = blockedThreadID == threadID
        if shouldBlock {
            blockedThreadID = nil
        }
        lock.unlock()

        if shouldBlock {
            lock.lock()
            didStartBlockedRequest = true
            lock.unlock()
            blockedRequestRelease.wait()
        }
        return result
    }

    var blockedRequestDidStart: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didStartBlockedRequest
    }

    func releaseBlockedRequest() {
        blockedRequestRelease.signal()
    }
}
