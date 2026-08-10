import Foundation
import XCTest
@testable import CodexNotesCore

final class NoteSelectionMoveTests: XCTestCase {
    private var temporaryRoot: URL!
    private var store: NoteStore!
    private var sourceDocument: NoteDocument!
    private var destinationDocument: NoteDocument!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexMoveTests-\(UUID().uuidString)", isDirectory: true)
        store = NoteStore(rootURL: temporaryRoot)
        sourceDocument = document(scope: .task, filename: "source.md")
        destinationDocument = document(scope: .project, filename: "destination.md")
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        store = nil
        sourceDocument = nil
        destinationDocument = nil
        temporaryRoot = nil
    }

    func testMovesSelectionToEmptyDestinationAndCanUndo() throws {
        let sourceText = "前文\n需要移动\n后文"
        try store.save(sourceText, to: sourceDocument)
        let range = (sourceText as NSString).range(of: "需要移动")

        let result = try store.moveSelection(
            in: range,
            sourceText: sourceText,
            from: sourceDocument,
            to: destinationDocument
        )

        XCTAssertEqual(result.sourceDocument, sourceDocument)
        XCTAssertEqual(result.destinationDocument, destinationDocument)
        XCTAssertEqual(result.sourceTextBefore, sourceText)
        XCTAssertEqual(result.sourceTextAfter, "前文\n\n后文")
        XCTAssertEqual(result.destinationTextBefore, "")
        XCTAssertEqual(result.destinationTextAfter, "需要移动")
        XCTAssertEqual(result.movedText, "需要移动")
        XCTAssertEqual(result.sourceCaretRange, NSRange(location: range.location, length: 0))
        XCTAssertEqual(
            result.destinationInsertedRange,
            NSRange(location: 0, length: ("需要移动" as NSString).length)
        )
        XCTAssertEqual(try store.load(sourceDocument), result.sourceTextAfter)
        XCTAssertEqual(try store.load(destinationDocument), result.destinationTextAfter)

        try store.undoSelectionMove(result)

        XCTAssertEqual(try store.load(sourceDocument), sourceText)
        XCTAssertEqual(try store.load(destinationDocument), "")
    }

    func testAppendsToPopulatedDestinationWithOnlyMissingBlankLine() throws {
        let sourceText = "移动这段"
        let destinationText = "已有内容\n"
        try store.save(sourceText, to: sourceDocument)
        try store.save(destinationText, to: destinationDocument)

        let result = try store.moveSelection(
            in: NSRange(location: 0, length: (sourceText as NSString).length),
            sourceText: sourceText,
            from: sourceDocument,
            to: destinationDocument
        )

        XCTAssertEqual(result.destinationTextAfter, "已有内容\n\n移动这段")
        XCTAssertEqual(
            result.destinationInsertedRange,
            NSRange(
                location: ("已有内容\n\n" as NSString).length,
                length: (sourceText as NSString).length
            )
        )
    }

    func testPreservesEmojiUsingUTF16SelectionOffsets() throws {
        let sourceText = "前😀后"
        let emojiRange = (sourceText as NSString).range(of: "😀")
        XCTAssertEqual(emojiRange.length, 2)
        try store.save(sourceText, to: sourceDocument)

        let result = try store.moveSelection(
            in: emojiRange,
            sourceText: sourceText,
            from: sourceDocument,
            to: destinationDocument
        )

        XCTAssertEqual(result.movedText, "😀")
        XCTAssertEqual(result.sourceTextAfter, "前后")
        XCTAssertEqual(result.sourceCaretRange, NSRange(location: 1, length: 0))
        XCTAssertEqual(result.destinationInsertedRange, NSRange(location: 0, length: 2))
    }

    func testUsesCRLFWhenCompletingDestinationBlankLine() throws {
        let sourceText = "第一行\r\n第二行"
        let destinationText = "已有\r\n"
        try store.save(sourceText, to: sourceDocument)
        try store.save(destinationText, to: destinationDocument)

        let result = try store.moveSelection(
            in: NSRange(location: 0, length: (sourceText as NSString).length),
            sourceText: sourceText,
            from: sourceDocument,
            to: destinationDocument
        )

        XCTAssertEqual(result.movedText, sourceText)
        XCTAssertEqual(result.destinationTextAfter, "已有\r\n\r\n第一行\r\n第二行")
        XCTAssertEqual(
            result.destinationInsertedRange.location,
            ("已有\r\n\r\n" as NSString).length
        )
    }

    func testLeadingSelectionNewlineCountsTowardBoundaryWithoutChangingMovedText() throws {
        let sourceText = "\n移动"
        try store.save(sourceText, to: sourceDocument)
        try store.save("已有\n", to: destinationDocument)

        let result = try store.moveSelection(
            in: NSRange(location: 0, length: (sourceText as NSString).length),
            sourceText: sourceText,
            from: sourceDocument,
            to: destinationDocument
        )

        XCTAssertEqual(result.movedText, sourceText)
        XCTAssertEqual(result.destinationTextAfter, "已有\n\n移动")
        XCTAssertEqual(
            result.destinationInsertedRange.location,
            ("已有\n" as NSString).length
        )
    }

    func testRejectsEmptyOutOfBoundsAndSameFileSelections() throws {
        XCTAssertThrowsError(
            try store.moveSelection(
                in: NSRange(location: 0, length: 0),
                sourceText: "abc",
                from: sourceDocument,
                to: destinationDocument
            )
        ) { error in
            XCTAssertEqual(error as? NoteSelectionMoveError, .emptySelection)
        }

        XCTAssertThrowsError(
            try store.moveSelection(
                in: NSRange(location: 2, length: 2),
                sourceText: "abc",
                from: sourceDocument,
                to: destinationDocument
            )
        ) { error in
            XCTAssertEqual(error as? NoteSelectionMoveError, .selectionOutOfBounds)
        }

        XCTAssertThrowsError(
            try store.moveSelection(
                in: NSRange(location: 0, length: 1),
                sourceText: "abc",
                from: sourceDocument,
                to: sourceDocument
            )
        ) { error in
            XCTAssertEqual(error as? NoteSelectionMoveError, .sameDocument)
        }
    }

    func testDestinationWriteFailureLeavesSourceUnchanged() throws {
        let sourceText = "不能丢失"
        let destinationText = "原目标"
        try store.save(sourceText, to: sourceDocument)
        try store.save(destinationText, to: destinationDocument)
        let writer = ControlledAtomicWriter()
        writer.failNextWrite(to: destinationDocument.fileURL)
        let failingStore = NoteStore(rootURL: temporaryRoot) { data, url in
            try writer.write(data, to: url)
        }

        XCTAssertThrowsError(
            try failingStore.moveSelection(
                in: NSRange(location: 0, length: (sourceText as NSString).length),
                sourceText: sourceText,
                from: sourceDocument,
                to: destinationDocument
            )
        )
        XCTAssertEqual(try store.load(sourceDocument), sourceText)
        XCTAssertEqual(try store.load(destinationDocument), destinationText)
    }

    func testRejectsMoveWhenPersistedSourceDiffersFromEditorText() throws {
        try store.save("磁盘内容", to: sourceDocument)
        try store.save("目标保持", to: destinationDocument)
        let editorText = "编辑器内容"

        XCTAssertThrowsError(
            try store.moveSelection(
                in: NSRange(location: 0, length: (editorText as NSString).length),
                sourceText: editorText,
                from: sourceDocument,
                to: destinationDocument
            )
        ) { error in
            guard case .staleMoveSource = error as? NoteSelectionMoveError else {
                return XCTFail("应拒绝过期的编辑器内容，实际为：\(error)")
            }
        }
        XCTAssertEqual(try store.load(sourceDocument), "磁盘内容")
        XCTAssertEqual(try store.load(destinationDocument), "目标保持")
    }

    func testMoveTreatsSourceAfterCommitThrowAsCommitted() throws {
        let sourceText = "前文 移动 后文"
        try store.save(sourceText, to: sourceDocument)
        try store.save("目标", to: destinationDocument)
        let writer = ControlledAtomicWriter()
        writer.failAfterCommittingNextWrite(to: sourceDocument.fileURL)
        let committingStore = NoteStore(rootURL: temporaryRoot) { data, url in
            try writer.write(data, to: url)
        }

        let result = try committingStore.moveSelection(
            in: (sourceText as NSString).range(of: "移动"),
            sourceText: sourceText,
            from: sourceDocument,
            to: destinationDocument
        )

        XCTAssertEqual(try store.load(sourceDocument), result.sourceTextAfter)
        XCTAssertEqual(try store.load(destinationDocument), result.destinationTextAfter)
        XCTAssertTrue(result.destinationTextAfter.contains(result.movedText))
    }

    func testSourceWriteFailureRollsDestinationBack() throws {
        let sourceText = "不能丢失"
        let destinationText = "原目标"
        try store.save(sourceText, to: sourceDocument)
        try store.save(destinationText, to: destinationDocument)
        let writer = ControlledAtomicWriter()
        writer.failNextWrite(to: sourceDocument.fileURL)
        let failingStore = NoteStore(rootURL: temporaryRoot) { data, url in
            try writer.write(data, to: url)
        }

        XCTAssertThrowsError(
            try failingStore.moveSelection(
                in: NSRange(location: 0, length: (sourceText as NSString).length),
                sourceText: sourceText,
                from: sourceDocument,
                to: destinationDocument
            )
        )
        XCTAssertEqual(try store.load(sourceDocument), sourceText)
        XCTAssertEqual(try store.load(destinationDocument), destinationText)
    }

    func testRollbackFailureLeavesDuplicateButDoesNotLoseSource() throws {
        let sourceText = "不能丢失"
        let destinationText = "原目标"
        try store.save(sourceText, to: sourceDocument)
        try store.save(destinationText, to: destinationDocument)
        let writer = ControlledAtomicWriter()
        writer.failWrite(to: sourceDocument.fileURL, onAttempt: 1)
        writer.failWrite(to: destinationDocument.fileURL, onAttempt: 2)
        let failingStore = NoteStore(rootURL: temporaryRoot) { data, url in
            try writer.write(data, to: url)
        }

        XCTAssertThrowsError(
            try failingStore.moveSelection(
                in: NSRange(location: 0, length: (sourceText as NSString).length),
                sourceText: sourceText,
                from: sourceDocument,
                to: destinationDocument
            )
        ) { error in
            guard case .rollbackFailed = error as? NoteSelectionMoveError else {
                return XCTFail("应明确报告回滚失败，实际为：\(error)")
            }
        }
        XCTAssertEqual(try store.load(sourceDocument), sourceText)
        XCTAssertEqual(try store.load(destinationDocument), destinationText + "\n\n" + sourceText)
    }

    func testUnknownSourceCommitStateKeepsConfirmedDestinationCopy() throws {
        let sourceText = "需要保留的内容"
        let destinationText = "原目标"
        try store.save(sourceText, to: sourceDocument)
        try store.save(destinationText, to: destinationDocument)
        let writer = ControlledAtomicWriter()
        writer.failNextWrite(to: sourceDocument.fileURL)
        let reader = ControlledUTF8Reader()
        reader.failRead(from: sourceDocument.fileURL, onAttempt: 2)
        let uncertainStore = NoteStore(
            rootURL: temporaryRoot,
            atomicWrite: { data, url in
                try writer.write(data, to: url)
            },
            readUTF8: { url in
                try reader.read(from: url)
            }
        )

        XCTAssertThrowsError(
            try uncertainStore.moveSelection(
                in: NSRange(location: 0, length: (sourceText as NSString).length),
                sourceText: sourceText,
                from: sourceDocument,
                to: destinationDocument
            )
        ) { error in
            guard case let .writeStateUnknown(_, _, preservedCopy, _, _) =
                error as? NoteSelectionMoveError
            else {
                return XCTFail("应报告写入状态未知，实际为：\(error)")
            }
            XCTAssertEqual(preservedCopy, self.destinationDocument.fileURL.path)
        }
        XCTAssertEqual(try store.load(sourceDocument), sourceText)
        XCTAssertEqual(
            try store.load(destinationDocument),
            destinationText + "\n\n" + sourceText
        )
    }

    func testUndoRejectsStaleSourceWithoutOverwritingEitherDocument() throws {
        let result = try completedMove()
        let externallyEditedSource = result.sourceTextAfter + "外部修改"
        try store.save(externallyEditedSource, to: sourceDocument)

        XCTAssertThrowsError(try store.undoSelectionMove(result)) { error in
            guard case .staleUndoSource = error as? NoteSelectionMoveError else {
                return XCTFail("应拒绝覆盖已修改的源笔记，实际为：\(error)")
            }
        }
        XCTAssertEqual(try store.load(sourceDocument), externallyEditedSource)
        XCTAssertEqual(try store.load(destinationDocument), result.destinationTextAfter)
    }

    func testUndoRejectsStaleDestinationWithoutRestoringSource() throws {
        let result = try completedMove()
        let externallyEditedDestination = result.destinationTextAfter + "外部修改"
        try store.save(externallyEditedDestination, to: destinationDocument)

        XCTAssertThrowsError(try store.undoSelectionMove(result)) { error in
            guard case .staleUndoDestination = error as? NoteSelectionMoveError else {
                return XCTFail("应拒绝覆盖已修改的目标笔记，实际为：\(error)")
            }
        }
        XCTAssertEqual(try store.load(sourceDocument), result.sourceTextAfter)
        XCTAssertEqual(try store.load(destinationDocument), externallyEditedDestination)
    }

    func testUndoTreatsDestinationAfterCommitThrowAsCommitted() throws {
        let result = try completedMove()
        let writer = ControlledAtomicWriter()
        writer.failAfterCommittingNextWrite(to: destinationDocument.fileURL)
        let committingStore = NoteStore(rootURL: temporaryRoot) { data, url in
            try writer.write(data, to: url)
        }

        try committingStore.undoSelectionMove(result)

        XCTAssertEqual(try store.load(sourceDocument), result.sourceTextBefore)
        XCTAssertEqual(try store.load(destinationDocument), result.destinationTextBefore)
        XCTAssertTrue(result.sourceTextBefore.contains(result.movedText))
    }

    func testUnknownUndoDestinationStateKeepsConfirmedSourceCopy() throws {
        let result = try completedMove()
        let writer = ControlledAtomicWriter()
        writer.failNextWrite(to: destinationDocument.fileURL)
        let reader = ControlledUTF8Reader()
        reader.failRead(from: destinationDocument.fileURL, onAttempt: 2)
        let uncertainStore = NoteStore(
            rootURL: temporaryRoot,
            atomicWrite: { data, url in
                try writer.write(data, to: url)
            },
            readUTF8: { url in
                try reader.read(from: url)
            }
        )

        XCTAssertThrowsError(try uncertainStore.undoSelectionMove(result)) { error in
            guard case let .writeStateUnknown(_, _, preservedCopy, _, _) =
                error as? NoteSelectionMoveError
            else {
                return XCTFail("应报告撤销写入状态未知，实际为：\(error)")
            }
            XCTAssertEqual(preservedCopy, self.sourceDocument.fileURL.path)
        }
        XCTAssertEqual(try store.load(sourceDocument), result.sourceTextBefore)
        XCTAssertEqual(try store.load(destinationDocument), result.destinationTextAfter)
        XCTAssertTrue(result.sourceTextBefore.contains(result.movedText))
    }

    private func completedMove() throws -> NoteSelectionMoveResult {
        let sourceText = "前文 移动 后文"
        try store.save(sourceText, to: sourceDocument)
        try store.save("目标", to: destinationDocument)
        return try store.moveSelection(
            in: (sourceText as NSString).range(of: "移动"),
            sourceText: sourceText,
            from: sourceDocument,
            to: destinationDocument
        )
    }

    private func document(scope: NoteScope, filename: String) -> NoteDocument {
        NoteDocument(
            scope: scope,
            stableKey: "\(scope.rawValue):\(filename)",
            displayName: filename,
            context: nil,
            fileURL: temporaryRoot.appendingPathComponent(filename)
        )
    }
}

private final class ControlledAtomicWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var attemptsByPath: [String: Int] = [:]
    private var failingAttemptsByPath: [String: Set<Int>] = [:]
    private var committingFailureAttemptsByPath: [String: Set<Int>] = [:]

    func failNextWrite(to url: URL) {
        lock.lock()
        let path = url.standardizedFileURL.path
        failingAttemptsByPath[path, default: []].insert(attemptsByPath[path, default: 0] + 1)
        lock.unlock()
    }

    func failWrite(to url: URL, onAttempt attempt: Int) {
        lock.lock()
        failingAttemptsByPath[url.standardizedFileURL.path, default: []].insert(attempt)
        lock.unlock()
    }

    func failAfterCommittingNextWrite(to url: URL) {
        lock.lock()
        let path = url.standardizedFileURL.path
        committingFailureAttemptsByPath[path, default: []].insert(
            attemptsByPath[path, default: 0] + 1
        )
        lock.unlock()
    }

    func write(_ data: Data, to url: URL) throws {
        let path = url.standardizedFileURL.path
        lock.lock()
        attemptsByPath[path, default: 0] += 1
        let attempt = attemptsByPath[path, default: 0]
        let shouldFail = failingAttemptsByPath[path, default: []].remove(attempt) != nil
        let shouldFailAfterCommitting = committingFailureAttemptsByPath[path, default: []]
            .remove(attempt) != nil
        lock.unlock()

        if shouldFail {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        if shouldFailAfterCommitting {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

private final class ControlledUTF8Reader: @unchecked Sendable {
    private let lock = NSLock()
    private var attemptsByPath: [String: Int] = [:]
    private var failingAttemptsByPath: [String: Set<Int>] = [:]

    func failRead(from url: URL, onAttempt attempt: Int) {
        lock.lock()
        failingAttemptsByPath[url.standardizedFileURL.path, default: []].insert(attempt)
        lock.unlock()
    }

    func read(from url: URL) throws -> String {
        let path = url.standardizedFileURL.path
        lock.lock()
        attemptsByPath[path, default: 0] += 1
        let attempt = attemptsByPath[path, default: 0]
        let shouldFail = failingAttemptsByPath[path, default: []].remove(attempt) != nil
        lock.unlock()

        if shouldFail {
            throw CocoaError(.fileReadUnknown)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
