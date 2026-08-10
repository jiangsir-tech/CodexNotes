import Foundation

public struct NoteSelectionMoveResult: Equatable, Sendable {
    public let sourceDocument: NoteDocument
    public let destinationDocument: NoteDocument
    public let sourceTextBefore: String
    public let sourceTextAfter: String
    public let destinationTextBefore: String
    public let destinationTextAfter: String
    public let movedText: String
    /// The collapsed source selection after the move succeeds.
    public let sourceCaretRange: NSRange
    /// The UTF-16 range occupied by `movedText` in `destinationTextAfter`.
    /// Boundary line endings added by the move are intentionally excluded.
    public let destinationInsertedRange: NSRange

    public init(
        sourceDocument: NoteDocument,
        destinationDocument: NoteDocument,
        sourceTextBefore: String,
        sourceTextAfter: String,
        destinationTextBefore: String,
        destinationTextAfter: String,
        movedText: String,
        sourceCaretRange: NSRange,
        destinationInsertedRange: NSRange
    ) {
        self.sourceDocument = sourceDocument
        self.destinationDocument = destinationDocument
        self.sourceTextBefore = sourceTextBefore
        self.sourceTextAfter = sourceTextAfter
        self.destinationTextBefore = destinationTextBefore
        self.destinationTextAfter = destinationTextAfter
        self.movedText = movedText
        self.sourceCaretRange = sourceCaretRange
        self.destinationInsertedRange = destinationInsertedRange
    }
}

public enum NoteSelectionMoveError: LocalizedError, Equatable, Sendable {
    case emptySelection
    case selectionOutOfBounds
    case sameDocument
    case staleMoveSource(String)
    case staleUndoSource(String)
    case staleUndoDestination(String)
    case writeStateUnknown(
        operation: String,
        uncertainDocument: String,
        preservedCopy: String,
        writeError: String,
        verification: String
    )
    case rollbackFailed(operation: String, originalError: String, rollbackError: String)

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            return L10n.text(.selectionMoveErrorEmptySelection)
        case .selectionOutOfBounds:
            return L10n.text(.selectionMoveErrorSelectionOutOfBounds)
        case .sameDocument:
            return L10n.text(.selectionMoveErrorSameDocument)
        case let .staleMoveSource(path):
            return L10n.text(
                .selectionMoveErrorStaleMoveSource,
                replacements: ["path": path]
            )
        case let .staleUndoSource(path):
            return L10n.text(
                .selectionMoveErrorStaleUndoSource,
                replacements: ["path": path]
            )
        case let .staleUndoDestination(path):
            return L10n.text(
                .selectionMoveErrorStaleUndoDestination,
                replacements: ["path": path]
            )
        case let .writeStateUnknown(
            operation,
            uncertainDocument,
            preservedCopy,
            writeError,
            verification
        ):
            return L10n.text(
                .selectionMoveErrorWriteStateUnknown,
                replacements: [
                    "operation": operation,
                    "uncertainDocument": uncertainDocument,
                    "preservedCopy": preservedCopy,
                    "writeError": writeError,
                    "verification": verification
                ]
            )
        case let .rollbackFailed(operation, originalError, rollbackError):
            return L10n.text(
                .selectionMoveErrorRollbackFailed,
                replacements: [
                    "operation": operation,
                    "originalError": originalError,
                    "rollbackError": rollbackError
                ]
            )
        }
    }
}

extension NoteStore {
    private enum WriteAttempt {
        case committed
        case notCommitted(Error)
        case unknown(writeError: Error, verification: String)
    }

    public func moveSelection(
        in range: NSRange,
        sourceText: String,
        from sourceDocument: NoteDocument,
        to destinationDocument: NoteDocument
    ) throws -> NoteSelectionMoveResult {
        guard range.length > 0 else {
            throw NoteSelectionMoveError.emptySelection
        }
        guard !sameFile(sourceDocument.fileURL, destinationDocument.fileURL) else {
            throw NoteSelectionMoveError.sameDocument
        }

        let source = sourceText as NSString
        guard isValid(range, in: source) else {
            throw NoteSelectionMoveError.selectionOutOfBounds
        }

        let persistedSourceText = try load(sourceDocument)
        guard persistedSourceText == sourceText else {
            throw NoteSelectionMoveError.staleMoveSource(sourceDocument.fileURL.path)
        }

        let movedText = source.substring(with: range)
        let sourceTextAfter = source.replacingCharacters(in: range, with: "")
        let destinationTextBefore = try load(destinationDocument)
        let appended = appendingSelection(movedText, to: destinationTextBefore)
        let result = NoteSelectionMoveResult(
            sourceDocument: sourceDocument,
            destinationDocument: destinationDocument,
            sourceTextBefore: sourceText,
            sourceTextAfter: sourceTextAfter,
            destinationTextBefore: destinationTextBefore,
            destinationTextAfter: appended.text,
            movedText: movedText,
            sourceCaretRange: NSRange(location: range.location, length: 0),
            destinationInsertedRange: appended.insertedRange
        )

        switch attemptWrite(
            result.destinationTextAfter,
            replacing: result.destinationTextBefore,
            in: destinationDocument
        ) {
        case .committed:
            break
        case let .notCommitted(error):
            throw error
        case let .unknown(writeError, verification):
            throw unknownWriteStateError(
                operation: L10n.text(.selectionMoveOperationMoveToDestination),
                uncertainDocument: destinationDocument,
                preservedCopy: sourceDocument,
                writeError: writeError,
                verification: verification
            )
        }

        switch attemptWrite(
            result.sourceTextAfter,
            replacing: result.sourceTextBefore,
            in: sourceDocument
        ) {
        case .committed:
            return result
        case let .unknown(writeError, verification):
            throw unknownWriteStateError(
                operation: L10n.text(.selectionMoveOperationRemoveFromSource),
                uncertainDocument: sourceDocument,
                preservedCopy: destinationDocument,
                writeError: writeError,
                verification: verification
            )
        case let .notCommitted(sourceError):
            switch attemptWrite(
                result.destinationTextBefore,
                replacing: result.destinationTextAfter,
                in: destinationDocument
            ) {
            case .committed:
                throw sourceError
            case let .notCommitted(rollbackError):
                throw NoteSelectionMoveError.rollbackFailed(
                    operation: L10n.text(.selectionMoveOperationMoveSelection),
                    originalError: sourceError.localizedDescription,
                    rollbackError: rollbackError.localizedDescription
                )
            case let .unknown(writeError, verification):
                throw unknownWriteStateError(
                    operation: L10n.text(.selectionMoveOperationRollbackDestination),
                    uncertainDocument: destinationDocument,
                    preservedCopy: sourceDocument,
                    writeError: writeError,
                    verification: verification
                )
            }
        }
    }

    public func undoSelectionMove(_ result: NoteSelectionMoveResult) throws {
        let currentSourceText = try load(result.sourceDocument)
        guard currentSourceText == result.sourceTextAfter else {
            throw NoteSelectionMoveError.staleUndoSource(result.sourceDocument.fileURL.path)
        }

        let currentDestinationText = try load(result.destinationDocument)
        guard currentDestinationText == result.destinationTextAfter else {
            throw NoteSelectionMoveError.staleUndoDestination(
                result.destinationDocument.fileURL.path
            )
        }

        switch attemptWrite(
            result.sourceTextBefore,
            replacing: result.sourceTextAfter,
            in: result.sourceDocument
        ) {
        case .committed:
            break
        case let .notCommitted(error):
            throw error
        case let .unknown(writeError, verification):
            throw unknownWriteStateError(
                operation: L10n.text(.selectionMoveOperationRestoreSourceDuringUndo),
                uncertainDocument: result.sourceDocument,
                preservedCopy: result.destinationDocument,
                writeError: writeError,
                verification: verification
            )
        }

        switch attemptWrite(
            result.destinationTextBefore,
            replacing: result.destinationTextAfter,
            in: result.destinationDocument
        ) {
        case .committed:
            return
        case let .unknown(writeError, verification):
            throw unknownWriteStateError(
                operation: L10n.text(.selectionMoveOperationRestoreDestinationDuringUndo),
                uncertainDocument: result.destinationDocument,
                preservedCopy: result.sourceDocument,
                writeError: writeError,
                verification: verification
            )
        case let .notCommitted(destinationError):
            switch attemptWrite(
                result.sourceTextAfter,
                replacing: result.sourceTextBefore,
                in: result.sourceDocument
            ) {
            case .committed:
                throw destinationError
            case let .notCommitted(rollbackError):
                throw NoteSelectionMoveError.rollbackFailed(
                    operation: L10n.text(.selectionMoveOperationUndoMove),
                    originalError: destinationError.localizedDescription,
                    rollbackError: rollbackError.localizedDescription
                )
            case let .unknown(writeError, verification):
                throw unknownWriteStateError(
                    operation: L10n.text(.selectionMoveOperationRollbackSource),
                    uncertainDocument: result.sourceDocument,
                    preservedCopy: result.destinationDocument,
                    writeError: writeError,
                    verification: verification
                )
            }
        }
    }

    private func attemptWrite(
        _ intendedText: String,
        replacing previousText: String,
        in document: NoteDocument
    ) -> WriteAttempt {
        do {
            try save(intendedText, to: document)
            return .committed
        } catch {
            let writeError = error
            do {
                let currentText = try load(document)
                if currentText == intendedText {
                    return .committed
                }
                if currentText == previousText {
                    return .notCommitted(writeError)
                }
                return .unknown(
                    writeError: writeError,
                    verification: L10n.text(.selectionMoveVerificationContentMismatch)
                )
            } catch {
                return .unknown(
                    writeError: writeError,
                    verification: L10n.text(
                        .selectionMoveVerificationReadbackFailed,
                        replacements: ["error": error.localizedDescription]
                    )
                )
            }
        }
    }

    private func unknownWriteStateError(
        operation: String,
        uncertainDocument: NoteDocument,
        preservedCopy: NoteDocument,
        writeError: Error,
        verification: String
    ) -> NoteSelectionMoveError {
        .writeStateUnknown(
            operation: operation,
            uncertainDocument: uncertainDocument.fileURL.path,
            preservedCopy: preservedCopy.fileURL.path,
            writeError: writeError.localizedDescription,
            verification: verification
        )
    }

    private func sameFile(_ first: URL, _ second: URL) -> Bool {
        first.standardizedFileURL == second.standardizedFileURL
    }

    private func isValid(_ range: NSRange, in source: NSString) -> Bool {
        range.location != NSNotFound
            && range.location >= 0
            && range.length >= 0
            && range.location <= source.length
            && range.length <= source.length - range.location
    }

    private func appendingSelection(
        _ movedText: String,
        to destinationText: String
    ) -> (text: String, insertedRange: NSRange) {
        guard !destinationText.isEmpty else {
            return (
                movedText,
                NSRange(location: 0, length: (movedText as NSString).length)
            )
        }

        let existingBoundaryBreaks = min(
            2,
            trailingLineBreakCount(in: destinationText) + leadingLineBreakCount(in: movedText)
        )
        let missingBreaks = 2 - existingBoundaryBreaks
        let separator = String(
            repeating: preferredLineEnding(destinationText: destinationText, movedText: movedText),
            count: missingBreaks
        )
        let insertedLocation = (destinationText as NSString).length
            + (separator as NSString).length
        return (
            destinationText + separator + movedText,
            NSRange(
                location: insertedLocation,
                length: (movedText as NSString).length
            )
        )
    }

    private func preferredLineEnding(destinationText: String, movedText: String) -> String {
        if destinationText.contains("\r\n") { return "\r\n" }
        if destinationText.contains("\n") { return "\n" }
        if destinationText.contains("\r") { return "\r" }
        if movedText.contains("\r\n") { return "\r\n" }
        if movedText.contains("\n") { return "\n" }
        if movedText.contains("\r") { return "\r" }
        return "\n"
    }

    private func leadingLineBreakCount(in text: String) -> Int {
        let source = text as NSString
        var offset = 0
        var count = 0
        while offset < source.length, count < 2 {
            let character = source.character(at: offset)
            if character == 0x0D {
                offset += 1
                if offset < source.length, source.character(at: offset) == 0x0A {
                    offset += 1
                }
            } else if character == 0x0A {
                offset += 1
            } else {
                break
            }
            count += 1
        }
        return count
    }

    private func trailingLineBreakCount(in text: String) -> Int {
        let source = text as NSString
        var offset = source.length
        var count = 0
        while offset > 0, count < 2 {
            let character = source.character(at: offset - 1)
            if character == 0x0A {
                offset -= 1
                if offset > 0, source.character(at: offset - 1) == 0x0D {
                    offset -= 1
                }
            } else if character == 0x0D {
                offset -= 1
            } else {
                break
            }
            count += 1
        }
        return count
    }
}
