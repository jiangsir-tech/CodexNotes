import Foundation
import XCTest
@testable import CodexNotesCore
@testable import CodexNotesProbe

@MainActor
final class ProbeViewModelSelectionMoveTests: XCTestCase {
    func testMovesSelectionToProjectAndPublishesResultAndProgress() throws {
        let harness = try makeHarness(
            taskText: "- [ ] 简单\n- [ ] 难题",
            projectText: "- [x] 项目事项"
        )
        defer { harness.removeTemporaryFiles() }

        let snapshot = try snapshot(in: harness.model, selecting: "- [ ] 难题")
        let result = try XCTUnwrap(move(snapshot, in: harness.model, to: .project))

        XCTAssertEqual(harness.model.noteText, "- [ ] 简单\n")
        XCTAssertEqual(try harness.store.load(harness.taskDocument), "- [ ] 简单\n")
        XCTAssertEqual(
            try harness.store.load(harness.projectDocument),
            "- [x] 项目事项\n\n- [ ] 难题"
        )
        XCTAssertEqual(result.sourceCaretRange, NSRange(location: 9, length: 0))
        XCTAssertEqual(result.destinationInsertedRange, NSRange(location: 12, length: 8))
        XCTAssertEqual(
            harness.model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 1)
        )
        XCTAssertEqual(
            harness.model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 2)
        )
        XCTAssertEqual(
            harness.model.selectionMoveNotice,
            SelectionMoveNotice(
                destinationScope: .project,
                destinationName: "Project A",
                canUndo: true,
                canViewDestination: true
            )
        )
        XCTAssertNil(harness.model.selectionMoveError)
        XCTAssertFalse(harness.model.isSwitchBlocked)
    }

    func testMovesProjectSelectionToTaskThenViewsAndUndoes() throws {
        let taskBefore = "- [ ] 任务原有"
        let projectBefore = "- [x] 项目保留\n- [ ] 移回任务"
        let harness = try makeHarness(taskText: taskBefore, projectText: projectBefore)
        defer { harness.removeTemporaryFiles() }
        harness.model.selectScope(.project)

        let snapshot = try snapshot(in: harness.model, selecting: "- [ ] 移回任务")
        let result = try XCTUnwrap(move(snapshot, in: harness.model, to: .task))

        XCTAssertEqual(harness.model.selectedScope, .project)
        XCTAssertEqual(harness.model.noteText, "- [x] 项目保留\n")
        XCTAssertEqual(try harness.store.load(harness.projectDocument), "- [x] 项目保留\n")
        XCTAssertEqual(
            try harness.store.load(harness.taskDocument),
            "- [ ] 任务原有\n\n- [ ] 移回任务"
        )
        XCTAssertEqual(
            harness.model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 2)
        )
        XCTAssertEqual(
            harness.model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 1)
        )
        XCTAssertEqual(
            harness.model.selectionMoveNotice,
            SelectionMoveNotice(
                destinationScope: .task,
                destinationName: "任务 A",
                canUndo: true,
                canViewDestination: true
            )
        )

        XCTAssertEqual(
            harness.model.viewSelectionMoveDestination(),
            result.destinationInsertedRange
        )
        XCTAssertEqual(harness.model.selectedScope, .task)
        XCTAssertEqual(harness.model.noteText, result.destinationTextAfter)
        XCTAssertEqual(harness.model.selectionMoveNotice?.canViewDestination, false)

        XCTAssertEqual(harness.model.undoLastSelectionMove(), result)
        XCTAssertEqual(harness.model.selectedScope, .task)
        XCTAssertEqual(harness.model.noteText, taskBefore)
        XCTAssertEqual(try harness.store.load(harness.taskDocument), taskBefore)
        XCTAssertEqual(try harness.store.load(harness.projectDocument), projectBefore)
        XCTAssertEqual(
            harness.model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 1)
        )
        XCTAssertEqual(
            harness.model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 2)
        )
        XCTAssertNil(harness.model.selectionMoveNotice)
        XCTAssertNil(harness.model.selectionMoveError)
    }

    func testViewsDestinationAndReturnsInsertedRange() throws {
        let harness = try makeHarness(taskText: "前文\n移动我", projectText: "项目正文")
        defer { harness.removeTemporaryFiles() }

        let snapshot = try snapshot(in: harness.model, selecting: "移动我")
        let move = try XCTUnwrap(move(snapshot, in: harness.model, to: .project))

        let destinationRange = harness.model.viewSelectionMoveDestination()

        XCTAssertEqual(destinationRange, move.destinationInsertedRange)
        XCTAssertEqual(harness.model.selectedScope, .project)
        XCTAssertEqual(harness.model.activeDocument?.fileURL, harness.projectDocument.fileURL)
        XCTAssertEqual(harness.model.noteText, "项目正文\n\n移动我")
        XCTAssertEqual(harness.model.selectionMoveNotice?.canUndo, true)
        XCTAssertEqual(harness.model.selectionMoveNotice?.canViewDestination, false)
    }

    func testMoveNoticeAutoDismissesInBothDirectionsAndClearsPendingActions() async throws {
        let taskToProject = try makeHarness(
            taskText: "移到项目",
            projectText: "项目正文",
            selectionMoveNoticeDuration: .milliseconds(80)
        )
        defer { taskToProject.removeTemporaryFiles() }

        let taskSnapshot = try snapshot(in: taskToProject.model, selecting: "移到项目")
        XCTAssertNotNil(move(taskSnapshot, in: taskToProject.model, to: .project))
        XCTAssertNotNil(taskToProject.model.selectionMoveNotice)

        try await waitUntil { taskToProject.model.selectionMoveNotice == nil }

        XCTAssertNil(taskToProject.model.viewSelectionMoveDestination())
        XCTAssertNil(taskToProject.model.undoLastSelectionMove())

        let projectToTask = try makeHarness(
            taskText: "任务正文",
            projectText: "移到任务",
            selectionMoveNoticeDuration: .milliseconds(80)
        )
        defer { projectToTask.removeTemporaryFiles() }
        projectToTask.model.selectScope(.project)

        let projectSnapshot = try snapshot(in: projectToTask.model, selecting: "移到任务")
        XCTAssertNotNil(move(projectSnapshot, in: projectToTask.model, to: .task))
        XCTAssertEqual(projectToTask.model.selectionMoveNotice?.destinationScope, .task)

        try await waitUntil { projectToTask.model.selectionMoveNotice == nil }

        XCTAssertNil(projectToTask.model.viewSelectionMoveDestination())
        XCTAssertNil(projectToTask.model.undoLastSelectionMove())
    }

    func testNewMoveRestartsNoticeDeadlineAndOldTaskCannotDismissSameNotice() async throws {
        let harness = try makeHarness(
            taskText: "第一次\n第二次",
            projectText: "项目正文",
            selectionMoveNoticeDuration: .milliseconds(400)
        )
        defer { harness.removeTemporaryFiles() }

        let firstSnapshot = try snapshot(in: harness.model, selecting: "第一次")
        XCTAssertNotNil(move(firstSnapshot, in: harness.model, to: .project))
        try await Task.sleep(for: .milliseconds(300))

        let secondSnapshot = try snapshot(in: harness.model, selecting: "第二次")
        XCTAssertNotNil(move(secondSnapshot, in: harness.model, to: .project))

        // Cross the first move's original deadline while remaining well inside
        // the second move's full display duration. Both notices intentionally
        // have the same value, so identity must come from the scheduled request.
        try await Task.sleep(for: .milliseconds(160))
        XCTAssertEqual(harness.model.selectionMoveNotice?.destinationScope, .project)
        XCTAssertEqual(harness.model.selectionMoveNotice?.destinationName, "Project A")
        XCTAssertEqual(harness.model.selectionMoveNotice?.canUndo, true)

        try await waitUntil { harness.model.selectionMoveNotice == nil }
        XCTAssertNil(harness.model.undoLastSelectionMove())
    }

    func testNewNoticeResetsOldHoverAndIgnoresStaleHoverEnter() async throws {
        let harness = try makeHarness(
            taskText: "第一次\n第二次",
            projectText: "项目正文",
            selectionMoveNoticeDuration: .milliseconds(120)
        )
        defer { harness.removeTemporaryFiles() }

        let firstSnapshot = try snapshot(in: harness.model, selecting: "第一次")
        XCTAssertNotNil(move(firstSnapshot, in: harness.model, to: .project))
        let oldNoticeID = try XCTUnwrap(harness.model.selectionMoveNotice?.id)
        harness.model.setSelectionMoveNoticeHovered(true, for: oldNoticeID)

        let secondSnapshot = try snapshot(in: harness.model, selecting: "第二次")
        XCTAssertNotNil(move(secondSnapshot, in: harness.model, to: .project))
        let newNoticeID = try XCTUnwrap(harness.model.selectionMoveNotice?.id)
        XCTAssertNotEqual(newNoticeID, oldNoticeID)

        // A new notice must clear the previous banner's hover state, and a late
        // mouse-enter callback from that old banner must not pause the new one.
        harness.model.setSelectionMoveNoticeHovered(true, for: oldNoticeID)
        try await waitUntil { harness.model.selectionMoveNotice == nil }
    }

    func testStaleHoverExitCannotResumeCurrentPausedNotice() async throws {
        let harness = try makeHarness(
            taskText: "第一次\n第二次",
            projectText: "项目正文",
            selectionMoveNoticeDuration: .milliseconds(120)
        )
        defer { harness.removeTemporaryFiles() }

        let firstSnapshot = try snapshot(in: harness.model, selecting: "第一次")
        XCTAssertNotNil(move(firstSnapshot, in: harness.model, to: .project))
        let oldNoticeID = try XCTUnwrap(harness.model.selectionMoveNotice?.id)

        let secondSnapshot = try snapshot(in: harness.model, selecting: "第二次")
        XCTAssertNotNil(move(secondSnapshot, in: harness.model, to: .project))
        let newNoticeID = try XCTUnwrap(harness.model.selectionMoveNotice?.id)
        harness.model.setSelectionMoveNoticeHovered(true, for: newNoticeID)

        // SwiftUI may deliver the removed old banner's mouse-exit/onDisappear
        // after the replacement is visible. Its ID must not restart the timer.
        harness.model.setSelectionMoveNoticeHovered(false, for: oldNoticeID)
        try await Task.sleep(for: .milliseconds(180))
        XCTAssertEqual(harness.model.selectionMoveNotice?.id, newNoticeID)

        harness.model.setSelectionMoveNoticeHovered(false, for: newNoticeID)
        try await waitUntil { harness.model.selectionMoveNotice == nil }
    }

    func testHoverPausesNoticeAndLeavingRestartsFullDuration() async throws {
        let harness = try makeHarness(
            taskText: "悬停测试",
            projectText: "项目正文",
            selectionMoveNoticeDuration: .milliseconds(180)
        )
        defer { harness.removeTemporaryFiles() }

        let moveSnapshot = try snapshot(in: harness.model, selecting: "悬停测试")
        XCTAssertNotNil(move(moveSnapshot, in: harness.model, to: .project))
        let noticeID = try XCTUnwrap(harness.model.selectionMoveNotice?.id)
        try await Task.sleep(for: .milliseconds(100))

        harness.model.setSelectionMoveNoticeHovered(true, for: noticeID)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNotNil(harness.model.selectionMoveNotice)
        XCTAssertEqual(harness.model.selectionMoveNotice?.canUndo, true)

        harness.model.setSelectionMoveNoticeHovered(false, for: noticeID)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNotNil(harness.model.selectionMoveNotice)

        try await waitUntil { harness.model.selectionMoveNotice == nil }
        XCTAssertNil(harness.model.undoLastSelectionMove())
    }

    func testViewingDestinationRestartsNoticeAndKeepsUndoAvailable() async throws {
        let harness = try makeHarness(
            taskText: "查看后仍可撤销",
            projectText: "项目正文",
            selectionMoveNoticeDuration: .milliseconds(400)
        )
        defer { harness.removeTemporaryFiles() }

        let moveSnapshot = try snapshot(in: harness.model, selecting: "查看后仍可撤销")
        let result = try XCTUnwrap(move(moveSnapshot, in: harness.model, to: .project))
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(
            harness.model.viewSelectionMoveDestination(),
            result.destinationInsertedRange
        )
        XCTAssertEqual(harness.model.selectionMoveNotice?.canViewDestination, false)
        XCTAssertEqual(harness.model.selectionMoveNotice?.canUndo, true)

        try await Task.sleep(for: .milliseconds(160))
        XCTAssertNotNil(harness.model.selectionMoveNotice)
        XCTAssertEqual(harness.model.undoLastSelectionMove(), result)
        XCTAssertNil(harness.model.selectionMoveNotice)
    }

    func testManualDismissCancelsOldTaskWithoutHarmingNextNotice() async throws {
        let harness = try makeHarness(
            taskText: "第一次\n第二次",
            projectText: "项目正文",
            selectionMoveNoticeDuration: .milliseconds(400)
        )
        defer { harness.removeTemporaryFiles() }

        let firstSnapshot = try snapshot(in: harness.model, selecting: "第一次")
        XCTAssertNotNil(move(firstSnapshot, in: harness.model, to: .project))
        try await Task.sleep(for: .milliseconds(300))
        harness.model.dismissSelectionMoveNotice()
        XCTAssertNil(harness.model.selectionMoveNotice)

        let secondSnapshot = try snapshot(in: harness.model, selecting: "第二次")
        XCTAssertNotNil(move(secondSnapshot, in: harness.model, to: .project))
        try await Task.sleep(for: .milliseconds(160))

        XCTAssertNotNil(harness.model.selectionMoveNotice)
        XCTAssertEqual(harness.model.selectionMoveNotice?.canUndo, true)
        harness.model.dismissSelectionMoveNotice()
    }

    func testUndoCancelsOldTaskWithoutHarmingNextNotice() async throws {
        let harness = try makeHarness(
            taskText: "第一次\n第二次",
            projectText: "项目正文",
            selectionMoveNoticeDuration: .milliseconds(400)
        )
        defer { harness.removeTemporaryFiles() }

        let firstSnapshot = try snapshot(in: harness.model, selecting: "第一次")
        let firstResult = try XCTUnwrap(move(firstSnapshot, in: harness.model, to: .project))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(harness.model.undoLastSelectionMove(), firstResult)
        XCTAssertNil(harness.model.selectionMoveNotice)

        let secondSnapshot = try snapshot(in: harness.model, selecting: "第二次")
        XCTAssertNotNil(move(secondSnapshot, in: harness.model, to: .project))
        try await Task.sleep(for: .milliseconds(160))

        XCTAssertNotNil(harness.model.selectionMoveNotice)
        XCTAssertEqual(harness.model.selectionMoveNotice?.canUndo, true)
        harness.model.dismissSelectionMoveNotice()
    }

    func testIdentityChangeCancelsOldTaskWithoutHarmingNewIdentityNotice() async throws {
        let harness = try makeHarness(
            taskText: "任务 A 的移动",
            projectText: "Project A 正文",
            selectionMoveNoticeDuration: .milliseconds(400)
        )
        defer { harness.removeTemporaryFiles() }

        let firstSnapshot = try snapshot(in: harness.model, selecting: "任务 A 的移动")
        XCTAssertNotNil(move(firstSnapshot, in: harness.model, to: .project))
        try await Task.sleep(for: .milliseconds(300))

        let selectionB = makeSelection(id: "thread-b")
        harness.provider.set(
            CodexThreadMetadata(
                id: "thread-b",
                name: "任务 B",
                cwd: "/tmp/Project-B",
                projectName: "Project B"
            )
        )
        harness.model.apply(selectionB, recordLatency: false)
        XCTAssertNil(harness.model.selectionMoveNotice)

        harness.model.noteText = "任务 B 的移动"
        let secondSnapshot = try snapshot(in: harness.model, selecting: "任务 B 的移动")
        XCTAssertNotNil(move(secondSnapshot, in: harness.model, to: .project))
        try await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(harness.model.selectionMoveNotice?.destinationScope, .project)
        XCTAssertEqual(harness.model.selectionMoveNotice?.destinationName, "Project B")
        XCTAssertEqual(harness.model.selectionMoveNotice?.canUndo, true)
        harness.model.dismissSelectionMoveNotice()
    }

    func testUndoFromSourceRestoresBothNotesAndProgress() throws {
        let harness = try makeHarness(
            taskText: "- [x] 保留\n- [ ] 移动",
            projectText: "- [ ] 项目"
        )
        defer { harness.removeTemporaryFiles() }

        let snapshot = try snapshot(in: harness.model, selecting: "- [ ] 移动")
        let move = try XCTUnwrap(move(snapshot, in: harness.model, to: .project))

        let undone = harness.model.undoLastSelectionMove()

        XCTAssertEqual(undone, move)
        XCTAssertEqual(harness.model.noteText, move.sourceTextBefore)
        XCTAssertEqual(try harness.store.load(harness.taskDocument), move.sourceTextBefore)
        XCTAssertEqual(
            try harness.store.load(harness.projectDocument),
            move.destinationTextBefore
        )
        XCTAssertEqual(
            harness.model.taskChecklistProgress,
            MarkdownChecklistProgress(completed: 1, total: 2)
        )
        XCTAssertEqual(
            harness.model.projectChecklistProgress,
            MarkdownChecklistProgress(completed: 0, total: 1)
        )
        XCTAssertNil(harness.model.selectionMoveNotice)
        XCTAssertNil(harness.model.selectionMoveError)
    }

    func testUndoFromDestinationRestoresVisibleDestination() throws {
        let harness = try makeHarness(taskText: "保留\n移动我", projectText: "目标")
        defer { harness.removeTemporaryFiles() }

        let snapshot = try snapshot(in: harness.model, selecting: "移动我")
        let move = try XCTUnwrap(move(snapshot, in: harness.model, to: .project))
        XCTAssertNotNil(harness.model.viewSelectionMoveDestination())

        let undone = harness.model.undoLastSelectionMove()

        XCTAssertEqual(undone, move)
        XCTAssertEqual(harness.model.selectedScope, .project)
        XCTAssertEqual(harness.model.noteText, "目标")
        XCTAssertEqual(try harness.store.load(harness.taskDocument), "保留\n移动我")
        XCTAssertEqual(try harness.store.load(harness.projectDocument), "目标")
    }

    func testStaleSnapshotIsRejectedWithoutBlockingOrWriting() throws {
        let harness = try makeHarness(taskText: "原始文字", projectText: "目标正文")
        defer { harness.removeTemporaryFiles() }

        let snapshot = try snapshot(in: harness.model, selecting: "文字")
        harness.model.noteText = "用户已经改过"

        XCTAssertNil(move(snapshot, in: harness.model, to: .project))

        XCTAssertEqual(harness.model.noteText, "用户已经改过")
        XCTAssertEqual(try harness.store.load(harness.taskDocument), "原始文字")
        XCTAssertEqual(try harness.store.load(harness.projectDocument), "目标正文")
        XCTAssertNotNil(harness.model.selectionMoveError)
        XCTAssertFalse(harness.model.isSwitchBlocked)
        XCTAssertTrue(harness.model.canEdit)

        harness.model.dismissSelectionMoveError()
        XCTAssertNil(harness.model.selectionMoveError)
    }

    func testNewEditInvalidatesUndoButKeepsDestinationViewAvailable() throws {
        let harness = try makeHarness(taskText: "保留\n移动我", projectText: "目标")
        defer { harness.removeTemporaryFiles() }

        let snapshot = try snapshot(in: harness.model, selecting: "移动我")
        let move = try XCTUnwrap(move(snapshot, in: harness.model, to: .project))
        harness.model.noteText += "\n新编辑"

        XCTAssertEqual(harness.model.selectionMoveNotice?.canUndo, false)
        XCTAssertEqual(harness.model.selectionMoveNotice?.canViewDestination, true)
        XCTAssertNil(harness.model.undoLastSelectionMove())
        XCTAssertNotNil(harness.model.selectionMoveError)
        XCTAssertEqual(try harness.store.load(harness.projectDocument), move.destinationTextAfter)

        XCTAssertEqual(
            harness.model.viewSelectionMoveDestination(),
            move.destinationInsertedRange
        )
        XCTAssertEqual(harness.model.noteText, move.destinationTextAfter)
    }

    func testTaskIdentityChangeDismissesMoveAndPreventsUndo() throws {
        let harness = try makeHarness(taskText: "保留\n移动我", projectText: "目标")
        defer { harness.removeTemporaryFiles() }

        let snapshot = try snapshot(in: harness.model, selecting: "移动我")
        let move = try XCTUnwrap(move(snapshot, in: harness.model, to: .project))
        let nextSelection = makeSelection(id: "thread-b")
        harness.provider.set(
            CodexThreadMetadata(
                id: "thread-b",
                name: "任务 B",
                cwd: "/tmp/Project-B",
                projectName: "Project B"
            )
        )

        harness.model.apply(nextSelection, recordLatency: true)

        XCTAssertNil(harness.model.selectionMoveNotice)
        XCTAssertNil(harness.model.undoLastSelectionMove())
        XCTAssertEqual(try harness.store.load(harness.taskDocument), move.sourceTextAfter)
        XCTAssertEqual(
            try harness.store.load(harness.projectDocument),
            move.destinationTextAfter
        )
    }

    func testFrozenProjectSnapshotCannotMoveIntoAnotherTaskInSameProject() throws {
        let harness = try makeHarness(taskText: "任务 A", projectText: "共享项目文字")
        defer { harness.removeTemporaryFiles() }
        harness.model.selectScope(.project)
        let snapshot = try snapshot(in: harness.model, selecting: "项目文字")
        let frozenStableKey = try XCTUnwrap(harness.model.selection?.stableKey)

        let selectionB = makeSelection(id: "thread-b")
        let metadataB = CodexThreadMetadata(
            id: "thread-b",
            name: "任务 B",
            cwd: "/tmp/Project-A",
            projectName: "Project A"
        )
        harness.provider.set(metadataB)
        harness.model.apply(selectionB, recordLatency: true)
        let taskBDocument = harness.store.taskDocument(
            selection: selectionB,
            metadata: metadataB
        )

        XCTAssertNil(
            harness.model.moveSelection(
                snapshot,
                to: .task,
                expectedSelectionStableKey: frozenStableKey
            )
        )

        XCTAssertEqual(harness.model.noteText, "共享项目文字")
        XCTAssertEqual(try harness.store.load(harness.projectDocument), "共享项目文字")
        XCTAssertFalse(FileManager.default.fileExists(atPath: taskBDocument.fileURL.path))
        XCTAssertNotNil(harness.model.selectionMoveError)
        XCTAssertFalse(harness.model.isSwitchBlocked)
    }

    func testProjectMappingChangeInvalidatesPendingUndoAndView() async throws {
        let harness = try makeHarness(taskText: "移动我", projectText: "Project A")
        defer { harness.removeTemporaryFiles() }
        let selection = try XCTUnwrap(harness.model.selection)
        let snapshot = try snapshot(in: harness.model, selecting: "移动我")
        XCTAssertNotNil(move(snapshot, in: harness.model, to: .project))

        harness.provider.set(
            CodexThreadMetadata(
                id: "thread-a",
                name: "任务 A",
                cwd: "/tmp/Project-B",
                projectName: "Project B"
            )
        )
        harness.model.apply(selection, recordLatency: true)
        try await waitUntil { harness.model.metadata?.cwd == "/tmp/Project-B" }

        XCTAssertNil(harness.model.selectionMoveNotice)
        XCTAssertNil(harness.model.undoLastSelectionMove())
        XCTAssertNil(harness.model.viewSelectionMoveDestination())
        XCTAssertEqual(harness.model.selectedScope, .task)
        XCTAssertFalse(harness.model.isSwitchBlocked)
    }

    func testFrozenDestinationRejectsSameTaskProjectPathChange() async throws {
        let harness = try makeHarness(taskText: "不能写错项目", projectText: "Project A 原文")
        defer { harness.removeTemporaryFiles() }
        let selection = try XCTUnwrap(harness.model.selection)
        let snapshot = try snapshot(in: harness.model, selecting: "不能写错项目")

        let metadataB = CodexThreadMetadata(
            id: "thread-a",
            name: "任务 A",
            cwd: "/tmp/Project-B",
            projectName: "Project B"
        )
        harness.provider.set(metadataB)
        harness.model.apply(selection, recordLatency: true)
        try await waitUntil { harness.model.metadata?.cwd == metadataB.cwd }
        let projectBDocument = try harness.store.projectDocument(
            selection: selection,
            metadata: metadataB
        )

        XCTAssertNil(
            harness.model.moveSelection(
                snapshot,
                to: .project,
                expectedSelectionStableKey: selection.stableKey
            )
        )

        XCTAssertEqual(try harness.store.load(harness.taskDocument), "不能写错项目")
        XCTAssertEqual(try harness.store.load(harness.projectDocument), "Project A 原文")
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectBDocument.fileURL.path))
        XCTAssertNotNil(harness.model.selectionMoveError)
        XCTAssertFalse(harness.model.isSwitchBlocked)
    }

    func testStaleMoveSafetyRetryDoesNotOverwriteAndLoadsDisk() throws {
        let harness = try makeHarness(taskText: "内存中的旧正文", projectText: "项目")
        defer { harness.removeTemporaryFiles() }
        try harness.store.save("磁盘上的外部新正文", to: harness.taskDocument)

        harness.model.pauseForSelectionMoveSafety(
            NoteSelectionMoveError.staleMoveSource(harness.taskDocument.fileURL.path)
        )

        XCTAssertTrue(harness.model.isSwitchBlocked)
        XCTAssertFalse(harness.model.flushImmediately())
        XCTAssertEqual(try harness.store.load(harness.taskDocument), "磁盘上的外部新正文")

        harness.model.retry()

        XCTAssertEqual(harness.model.noteText, "磁盘上的外部新正文")
        XCTAssertEqual(try harness.store.load(harness.taskDocument), "磁盘上的外部新正文")
        XCTAssertFalse(harness.model.isSwitchBlocked)
        XCTAssertTrue(harness.model.canEdit)
        XCTAssertNil(harness.model.selectionMoveError)
    }

    func testUnknownUndoDestinationRetryKeepsMovedTextInAtLeastOneNote() throws {
        let movedText = "绝不能丢的文字"
        let harness = try makeHarness(
            taskText: "任务保留\n\(movedText)",
            projectText: "项目原文"
        )
        defer { harness.removeTemporaryFiles() }
        let snapshot = try snapshot(in: harness.model, selecting: movedText)
        let result = try XCTUnwrap(move(snapshot, in: harness.model, to: .project))
        XCTAssertEqual(harness.model.selectedScope, .task)

        // Simulate the observable disk state after undo restored the source while
        // the destination restoration committed but its read-back could not be verified.
        try harness.store.save(result.sourceTextBefore, to: harness.taskDocument)
        try harness.store.save(result.destinationTextBefore, to: harness.projectDocument)
        harness.model.pauseForSelectionMoveSafety(
            NoteSelectionMoveError.writeStateUnknown(
                operation: "撤销移动",
                uncertainDocument: harness.projectDocument.fileURL.path,
                preservedCopy: "/tmp/preserved-selection-move.md",
                writeError: "simulated write failure",
                verification: "simulated verification failure"
            )
        )
        XCTAssertFalse(harness.model.flushImmediately())

        harness.model.retry()

        let taskAfterRetry = try harness.store.load(harness.taskDocument)
        let projectAfterRetry = try harness.store.load(harness.projectDocument)
        XCTAssertEqual(harness.model.noteText, taskAfterRetry)
        XCTAssertTrue(taskAfterRetry.contains(movedText))
        XCTAssertFalse(projectAfterRetry.contains(movedText))
        XCTAssertFalse(harness.model.isSwitchBlocked)
    }

    func testSafetyRetryMissingFileKeepsWriteGuardActive() throws {
        let harness = try makeHarness(taskText: "必须保留在内存", projectText: "项目")
        defer { harness.removeTemporaryFiles() }
        try FileManager.default.removeItem(at: harness.taskDocument.fileURL)
        harness.model.pauseForSelectionMoveSafety(
            NoteSelectionMoveError.writeStateUnknown(
                operation: "移动选中内容",
                uncertainDocument: harness.taskDocument.fileURL.path,
                preservedCopy: "/tmp/preserved-selection-move.md",
                writeError: "simulated write failure",
                verification: "simulated verification failure"
            )
        )

        harness.model.retry()

        XCTAssertEqual(harness.model.noteText, "必须保留在内存")
        XCTAssertTrue(harness.model.isSwitchBlocked)
        XCTAssertFalse(harness.model.flushImmediately())
        XCTAssertNotNil(harness.model.selectionMoveError)
    }

    func testDestinationReadFailureNeverDeletesSourceOrBlocksEditing() throws {
        let harness = try makeHarness(taskText: "不能丢失的原文", projectText: "")
        defer { harness.removeTemporaryFiles() }
        try FileManager.default.createDirectory(
            at: harness.projectDocument.fileURL,
            withIntermediateDirectories: true
        )
        let snapshot = try snapshot(in: harness.model, selecting: "不能丢失")

        XCTAssertNil(move(snapshot, in: harness.model, to: .project))

        XCTAssertEqual(harness.model.noteText, "不能丢失的原文")
        XCTAssertEqual(try harness.store.load(harness.taskDocument), "不能丢失的原文")
        XCTAssertNotNil(harness.model.selectionMoveError)
        XCTAssertFalse(harness.model.isSwitchBlocked)
        XCTAssertTrue(harness.model.canEdit)
    }

    func testUnavailableProjectIsRejectedWithoutSavingStaleSnapshot() throws {
        let root = temporaryNoteRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let selection = makeSelection()
        let provider = SelectionMoveMetadataProvider(
            CodexThreadMetadata(
                id: "thread-a",
                name: "无项目任务",
                cwd: "/tmp/no-project",
                projectName: nil
            )
        )
        let store = NoteStore(rootURL: root)
        let model = ProbeViewModel(
            noteStore: store,
            metadataProvider: provider,
            metadataRefreshInterval: .zero
        )
        model.apply(selection, recordLatency: false)
        model.noteText = "选中内容"
        let document = try XCTUnwrap(model.activeDocument)
        let snapshot = EditorSelectionSnapshot(
            document: document,
            destinationDocument: NoteDocument(
                scope: .project,
                stableKey: "unavailable-project",
                displayName: "不可用项目",
                context: nil,
                fileURL: root.appendingPathComponent("unavailable-project.md")
            ),
            selectionStableKey: try XCTUnwrap(model.selection?.stableKey),
            sourceText: model.noteText,
            range: NSRange(location: 0, length: 4),
            selectedText: "选中内容"
        )

        XCTAssertNil(move(snapshot, in: model, to: .project))
        XCTAssertEqual(model.noteText, "选中内容")
        XCTAssertFalse(FileManager.default.fileExists(atPath: document.fileURL.path))
        XCTAssertFalse(model.isSwitchBlocked)
        XCTAssertNotNil(model.selectionMoveError)
    }

    private func makeHarness(
        taskText: String,
        projectText: String,
        selectionMoveNoticeDuration: Duration = .seconds(8)
    ) throws -> SelectionMoveHarness {
        let root = temporaryNoteRoot()
        let selection = makeSelection()
        let metadata = CodexThreadMetadata(
            id: "thread-a",
            name: "任务 A",
            cwd: "/tmp/Project-A",
            projectName: "Project A"
        )
        let provider = SelectionMoveMetadataProvider(metadata)
        let store = NoteStore(rootURL: root)
        let taskDocument = store.taskDocument(selection: selection, metadata: metadata)
        let projectDocument = try store.projectDocument(selection: selection, metadata: metadata)
        try store.save(taskText, to: taskDocument)
        try store.save(projectText, to: projectDocument)
        let model = ProbeViewModel(
            noteStore: store,
            metadataProvider: provider,
            metadataRefreshInterval: .zero,
            selectionMoveNoticeDuration: selectionMoveNoticeDuration
        )
        model.apply(selection, recordLatency: false)
        return SelectionMoveHarness(
            root: root,
            store: store,
            model: model,
            provider: provider,
            taskDocument: taskDocument,
            projectDocument: projectDocument
        )
    }

    private func snapshot(
        in model: ProbeViewModel,
        selecting selectedText: String
    ) throws -> EditorSelectionSnapshot {
        let document = try XCTUnwrap(model.activeDocument)
        let selection = try XCTUnwrap(model.selection)
        let destinationDocument: NoteDocument
        switch document.scope {
        case .task:
            destinationDocument = try model.noteStore.projectDocument(
                selection: selection,
                metadata: model.metadata
            )
        case .project:
            destinationDocument = model.noteStore.taskDocument(
                selection: selection,
                metadata: model.metadata
            )
        }
        let range = (model.noteText as NSString).range(of: selectedText)
        XCTAssertNotEqual(range.location, NSNotFound)
        return EditorSelectionSnapshot(
            document: document,
            destinationDocument: destinationDocument,
            selectionStableKey: try XCTUnwrap(model.selection?.stableKey),
            sourceText: model.noteText,
            range: range,
            selectedText: selectedText
        )
    }

    private func move(
        _ snapshot: EditorSelectionSnapshot,
        in model: ProbeViewModel,
        to destinationScope: NoteScope
    ) -> NoteSelectionMoveResult? {
        model.moveSelection(
            snapshot,
            to: destinationScope,
            expectedSelectionStableKey: model.selection?.stableKey ?? ""
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("等待视图模型状态刷新超时")
    }

    private func temporaryNoteRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexSelectionMoveVMTests-\(UUID().uuidString)")
    }

    private func makeSelection(id: String = "thread-a") -> CodexSelection {
        CodexSelection(
            timestamp: "2026-08-09T00:00:00.000Z",
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

@MainActor
private struct SelectionMoveHarness {
    let root: URL
    let store: NoteStore
    let model: ProbeViewModel
    let provider: SelectionMoveMetadataProvider
    let taskDocument: NoteDocument
    let projectDocument: NoteDocument

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class SelectionMoveMetadataProvider:
    CodexThreadMetadataProviding,
    @unchecked Sendable
{
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
