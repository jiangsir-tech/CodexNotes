import Foundation
import XCTest
@testable import CodexNotesCore
@testable import CodexNotesProbe

@MainActor
final class ProbeViewModelProgressTests: XCTestCase {
    func testLoadsBothScopeProgressAndUpdatesActiveScopeImmediately() throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let metadata = makeMetadata(cwd: "/tmp/project-a", projectName: "Project A")
        let provider = ProgressMetadataProvider(metadata)
        let store = NoteStore(rootURL: root)
        let selection = makeSelection()
        let taskDocument = store.taskDocument(selection: selection, metadata: metadata)
        let projectDocument = try store.projectDocument(selection: selection, metadata: metadata)
        try store.save("- [x] 已完成\n- [ ] 未完成", to: taskDocument)
        try store.save("- [x] 已完成\n- [ ] 未完成\n- [ ] 也未完成", to: projectDocument)

        let model = ProbeViewModel(noteStore: store, metadataProvider: provider)
        model.apply(selection, recordLatency: false)

        XCTAssertEqual(
            model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 2)
        )
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 3)
        )

        model.noteText = "- [x] 第一项\n- [x] 第二项"

        XCTAssertEqual(
            model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 2, total: 2)
        )
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 3)
        )

        model.selectScope(.project)
        XCTAssertEqual(
            model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 2, total: 2)
        )
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 3)
        )

        model.noteText = "普通正文，没有待办"
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 0)
        )
    }

    func testZeroProgressMeansReadableNoteWithoutTodosAndNilMeansUnavailableProject() {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let provider = ProgressMetadataProvider(
            makeMetadata(id: "thread-a", cwd: "/tmp/project-a", projectName: "Project A")
        )
        let model = ProbeViewModel(
            noteStore: NoteStore(rootURL: root),
            metadataProvider: provider
        )

        model.apply(makeSelection(id: "thread-a"), recordLatency: false)

        XCTAssertEqual(
            model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 0)
        )
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 0)
        )

        provider.set(
            makeMetadata(id: "thread-b", cwd: "", projectName: nil)
        )
        model.apply(makeSelection(id: "thread-b"), recordLatency: true)

        XCTAssertEqual(
            model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 0)
        )
        XCTAssertNil(model.projectChecklistProgress)
        XCTAssertFalse(model.canUseProjectNote)
    }

    func testTaskIdentityChangeReloadsBothProgressValues() throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let metadataA = makeMetadata(
            id: "thread-a",
            cwd: "/tmp/project-a",
            projectName: "Project A"
        )
        let metadataB = makeMetadata(
            id: "thread-b",
            cwd: "/tmp/project-b",
            projectName: "Project B"
        )
        let selectionA = makeSelection(id: "thread-a")
        let selectionB = makeSelection(id: "thread-b")
        let provider = ProgressMetadataProvider(metadataA)
        let store = NoteStore(rootURL: root)

        try store.save(
            "- [ ] A task",
            to: store.taskDocument(selection: selectionA, metadata: metadataA)
        )
        try store.save(
            "- [x] A project",
            to: store.projectDocument(selection: selectionA, metadata: metadataA)
        )
        try store.save(
            "- [x] B task",
            to: store.taskDocument(selection: selectionB, metadata: metadataB)
        )
        try store.save(
            "- [x] B project 1\n- [ ] B project 2",
            to: store.projectDocument(selection: selectionB, metadata: metadataB)
        )

        let model = ProbeViewModel(noteStore: store, metadataProvider: provider)
        model.apply(selectionA, recordLatency: false)
        XCTAssertEqual(
            model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 1)
        )
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 1)
        )

        provider.set(metadataB)
        model.apply(selectionB, recordLatency: true)

        XCTAssertEqual(
            model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 1)
        )
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 2)
        )
    }

    func testProjectIdentityRefreshReloadsInactiveProjectProgress() async throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let selection = makeSelection()
        let metadataA = makeMetadata(cwd: "/tmp/project-a", projectName: "Project A")
        let metadataB = makeMetadata(cwd: "/tmp/project-b", projectName: "Project B")
        let provider = ProgressMetadataProvider(metadataA)
        let store = NoteStore(rootURL: root)
        try store.save(
            "- [ ] Project A",
            to: store.projectDocument(selection: selection, metadata: metadataA)
        )
        try store.save(
            "- [x] Project B 1\n- [x] Project B 2",
            to: store.projectDocument(selection: selection, metadata: metadataB)
        )

        let model = ProbeViewModel(
            noteStore: store,
            metadataProvider: provider,
            metadataRefreshInterval: .zero
        )
        model.apply(selection, recordLatency: false)
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 1)
        )

        provider.set(metadataB)
        model.apply(selection, recordLatency: true)
        try await waitUntil { model.metadata?.cwd == metadataB.cwd }

        XCTAssertEqual(model.selectedScope, .task)
        XCTAssertTrue(model.canEdit)
        XCTAssertEqual(
            model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 2, total: 2)
        )
    }

    func testInactiveReadFailureDoesNotBlockActiveEditing() throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let metadata = makeMetadata(cwd: "/tmp/project-a", projectName: "Project A")
        let provider = ProgressMetadataProvider(metadata)
        let store = NoteStore(rootURL: root)
        let selection = makeSelection()
        let taskDocument = store.taskDocument(selection: selection, metadata: metadata)
        let projectDocument = try store.projectDocument(selection: selection, metadata: metadata)
        try store.save("- [ ] 可继续编辑", to: taskDocument)
        try FileManager.default.createDirectory(
            at: projectDocument.fileURL,
            withIntermediateDirectories: true
        )

        let model = ProbeViewModel(noteStore: store, metadataProvider: provider)
        model.apply(selection, recordLatency: false)

        XCTAssertEqual(model.state, .detected)
        XCTAssertTrue(model.canEdit)
        XCTAssertFalse(model.isSwitchBlocked)
        XCTAssertNil(model.projectChecklistProgress)
        XCTAssertEqual(
            model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 1)
        )

        model.noteText = "- [x] 仍可即时编辑"
        XCTAssertEqual(
            model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 1)
        )
        XCTAssertTrue(model.canEdit)
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("等待进度刷新超时")
    }

    private func temporaryNoteRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexProgressTests-\(UUID().uuidString)", isDirectory: true)
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

    private func makeMetadata(
        id: String = "thread-a",
        cwd: String,
        projectName: String?
    ) -> CodexThreadMetadata {
        CodexThreadMetadata(
            id: id,
            name: "任务 \(id)",
            cwd: cwd,
            projectName: projectName
        )
    }
}

private final class ProgressMetadataProvider: CodexThreadMetadataProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var current: CodexThreadMetadata?

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
        guard current?.id == threadID else { return nil }
        return current
    }
}
