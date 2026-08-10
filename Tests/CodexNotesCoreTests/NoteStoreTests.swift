import Foundation
import XCTest
@testable import CodexNotesCore

final class NoteStoreTests: XCTestCase {
    private var temporaryRoot: URL!
    private var store: NoteStore!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexNotesTests-\(UUID().uuidString)", isDirectory: true)
        store = NoteStore(rootURL: temporaryRoot)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        store = nil
        temporaryRoot = nil
    }

    func testDuplicateTitlesStillUseDifferentTaskFiles() {
        let first = store.taskDocument(
            selection: selection(id: "thread-a"),
            metadata: metadata(id: "thread-a", name: "同名任务", cwd: "/tmp/project")
        )
        let second = store.taskDocument(
            selection: selection(id: "thread-b"),
            metadata: metadata(id: "thread-b", name: "同名任务", cwd: "/tmp/project")
        )

        XCTAssertNotEqual(first.fileURL, second.fileURL)
        XCTAssertNotEqual(first.stableKey, second.stableKey)
    }

    func testRenamingTaskDoesNotChangeItsFile() {
        let route = selection(id: "thread-a")
        let before = store.taskDocument(
            selection: route,
            metadata: metadata(id: "thread-a", name: "旧名称", cwd: "/tmp/project")
        )
        let after = store.taskDocument(
            selection: route,
            metadata: metadata(id: "thread-a", name: "新名称", cwd: "/tmp/project")
        )

        XCTAssertEqual(before.fileURL, after.fileURL)
        XCTAssertEqual(before.stableKey, after.stableKey)
    }

    func testRenamingProjectDisplayNameDoesNotChangeItsFile() throws {
        let route = selection(id: "thread-a")
        let before = try store.projectDocument(
            selection: route,
            metadata: metadata(
                id: "thread-a",
                name: "任务",
                cwd: "/tmp/project",
                projectName: "旧 Project 名称"
            )
        )
        let after = try store.projectDocument(
            selection: route,
            metadata: metadata(
                id: "thread-a",
                name: "任务",
                cwd: "/tmp/project",
                projectName: "新 Project 名称"
            )
        )

        XCTAssertEqual(before.fileURL, after.fileURL)
        XCTAssertEqual(before.stableKey, after.stableKey)
    }

    func testEquivalentProjectPathsUseSameFile() throws {
        let route = selection(id: "thread-a")
        let canonical = try store.projectDocument(
            selection: route,
            metadata: metadata(id: "thread-a", name: "任务", cwd: "/tmp/project")
        )
        let dotted = try store.projectDocument(
            selection: route,
            metadata: metadata(id: "thread-a", name: "任务", cwd: "/tmp/project/.")
        )

        XCTAssertEqual(canonical.stableKey, dotted.stableKey)
        XCTAssertEqual(canonical.fileURL, dotted.fileURL)
    }

    func testSameProjectSharesFileAndDifferentProjectDoesNot() throws {
        let first = try store.projectDocument(
            selection: selection(id: "thread-a"),
            metadata: metadata(id: "thread-a", name: "A", cwd: "/tmp/project-x")
        )
        let second = try store.projectDocument(
            selection: selection(id: "thread-b"),
            metadata: metadata(id: "thread-b", name: "B", cwd: "/tmp/project-x")
        )
        let third = try store.projectDocument(
            selection: selection(id: "thread-c"),
            metadata: metadata(id: "thread-c", name: "C", cwd: "/tmp/project-y")
        )

        XCTAssertEqual(first.fileURL, second.fileURL)
        XCTAssertEqual(first.stableKey, second.stableKey)
        XCTAssertNotEqual(first.fileURL, third.fileURL)
    }

    func testProjectlessMetadataCannotCreateProjectDocument() {
        let projectless = CodexThreadMetadata(
            id: "thread-a",
            name: "任务",
            cwd: "/tmp/project",
            projectMembership: .none
        )

        XCTAssertThrowsError(
            try store.projectDocument(
                selection: selection(id: "thread-a"),
                metadata: projectless
            )
        ) { error in
            guard let noteError = error as? NoteStoreError,
                  case .projectUnavailable = noteError
            else {
                return XCTFail("应返回 projectUnavailable，实际为：\(error)")
            }
        }
    }

    func testUnknownProjectMembershipCannotCreateProjectDocument() {
        let unknown = CodexThreadMetadata(
            id: "thread-a",
            name: "任务",
            cwd: "/tmp/project",
            projectMembership: .unknown
        )

        XCTAssertThrowsError(
            try store.projectDocument(
                selection: selection(id: "thread-a"),
                metadata: unknown
            )
        ) { error in
            guard let noteError = error as? NoteStoreError,
                  case .projectUnavailable = noteError
            else {
                return XCTFail("应返回 projectUnavailable，实际为：\(error)")
            }
        }
    }

    func testMarkdownRoundTripsWithoutModification() throws {
        let document = store.taskDocument(
            selection: selection(id: "thread-a"),
            metadata: metadata(id: "thread-a", name: "A", cwd: "/tmp/project")
        )
        let markdown = """
        # 中文标题 🚀

        - [ ] 下一步
          - 缩进内容
        - [x] 已完成

        [链接](https://example.com)

        ```swift
        print("保持原样")
        ```
        """

        try store.save(markdown, to: document)

        XCTAssertEqual(try store.load(document), markdown)
    }

    func testEmptyNewNoteDoesNotCreateFile() throws {
        let document = store.taskDocument(
            selection: selection(id: "thread-a"),
            metadata: nil
        )

        try store.save("", to: document)

        XCTAssertFalse(FileManager.default.fileExists(atPath: document.fileURL.path))
    }

    func testDraftMigratesWithoutDeletingBackup() throws {
        let draftSelection = CodexSelection(
            timestamp: "2026-08-08T00:00:00.000Z",
            conversationID: "client-new-thread:abc",
            route: "/",
            windowID: "1",
            kind: .newTask,
            threadID: nil,
            hostID: nil,
            stableKey: "new:1:client-new-thread:abc"
        )
        let finalSelection = CodexSelection(
            timestamp: "2026-08-08T00:00:01.000Z",
            conversationID: "client-new-thread:abc",
            route: "/local/thread-a",
            windowID: "1",
            kind: .local,
            threadID: "thread-a",
            hostID: nil,
            stableKey: "local:thread-a"
        )
        let draft = store.taskDocument(selection: draftSelection, metadata: nil)
        let final = store.taskDocument(selection: finalSelection, metadata: nil)
        try store.save("- [ ] 草稿内容", to: draft)

        let migrated = try store.mergeDraftIfNeeded(from: draft, into: final)

        XCTAssertEqual(migrated, "- [ ] 草稿内容")
        XCTAssertEqual(try store.load(final), "- [ ] 草稿内容")
        XCTAssertEqual(try store.load(draft), "- [ ] 草稿内容")
    }

    func testDraftConflictNeverOverwritesExistingTaskNote() throws {
        let draftSelection = CodexSelection(
            timestamp: "2026-08-08T00:00:00.000Z",
            conversationID: "client-new-thread:abc",
            route: "/",
            windowID: "1",
            kind: .newTask,
            threadID: nil,
            hostID: nil,
            stableKey: "new:1:client-new-thread:abc"
        )
        let draft = store.taskDocument(selection: draftSelection, metadata: nil)
        let final = store.taskDocument(selection: selection(id: "thread-a"), metadata: nil)
        try store.save("草稿", to: draft)
        try store.save("正式笔记", to: final)

        XCTAssertThrowsError(try store.mergeDraftIfNeeded(from: draft, into: final))
        XCTAssertEqual(try store.load(final), "正式笔记")
        XCTAssertEqual(try store.load(draft), "草稿")
    }

    private func selection(id: String) -> CodexSelection {
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

    private func metadata(
        id: String,
        name: String,
        cwd: String,
        projectName: String? = "测试项目"
    ) -> CodexThreadMetadata {
        CodexThreadMetadata(id: id, name: name, cwd: cwd, projectName: projectName)
    }
}
