import AppKit
import Foundation

public enum CodexProbeError: LocalizedError, Sendable {
    case logDirectoryMissing(String)
    case noCodexLog
    case unreadableLog(String)

    public var errorDescription: String? {
        switch self {
        case let .logDirectoryMissing(path):
            return L10n.text(
                .codexLogErrorDirectoryMissing,
                replacements: ["path": path]
            )
        case .noCodexLog:
            return L10n.text(.codexLogErrorMainLogMissing)
        case let .unreadableLog(path):
            return L10n.text(
                .codexLogErrorUnreadable,
                replacements: ["path": path]
            )
        }
    }
}

struct CodexProcessIdentity: Equatable, Sendable {
    let pid: pid_t
    let launchDate: Date?
}

public enum CodexEnvironment {
    public static var defaultLogRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/com.openai.codex", isDirectory: true)
    }

    public static var defaultStateDatabase: URL {
        let environment = ProcessInfo.processInfo.environment
        let codexHome: URL
        if let configured = environment["CODEX_HOME"], !configured.isEmpty {
            codexHome = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            codexHome = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
        return codexHome.appendingPathComponent("state_5.sqlite")
    }

    public static func runningCodexPID() -> pid_t? {
        runningCodexProcess()?.pid
    }

    static func runningCodexProcess() -> CodexProcessIdentity? {
        guard let application = NSWorkspace.shared.runningApplications
            .first(where: {
                $0.bundleIdentifier == "com.openai.codex" && !$0.isTerminated
            })
        else { return nil }
        return CodexProcessIdentity(
            pid: application.processIdentifier,
            launchDate: application.launchDate
        )
    }
}

private struct LogFileIdentity: Equatable, Sendable {
    let systemNumber: UInt64?
    let fileNumber: UInt64?
}

private struct LogCursor: Sendable {
    var offset: UInt64
    var remainder: Data
    var anchor: Data
    var fileIdentity: LogFileIdentity
}

private struct LogSeed: Sendable {
    let selection: CodexSelection?
    let cursor: LogCursor
}

public actor CodexLogMonitor {
    private static let defaultBootstrapChunkSize = 256 * 1_024
    private static let cursorAnchorSize = 64

    private let logRoot: URL
    private let runningCodexProcessProvider: @Sendable () -> CodexProcessIdentity?
    private let bootstrapChunkSize: Int
    private var cursors: [URL: LogCursor] = [:]
    private var latest: CodexSelection?
    private var pollCounter = 0
    private var selectedProcess: CodexProcessIdentity?

    public init(logRoot: URL = CodexEnvironment.defaultLogRoot) {
        self.logRoot = logRoot
        self.runningCodexProcessProvider = {
            CodexEnvironment.runningCodexProcess()
        }
        self.bootstrapChunkSize = Self.defaultBootstrapChunkSize
    }

    init(
        logRoot: URL,
        runningCodexPIDProvider: @escaping @Sendable () -> pid_t?,
        bootstrapChunkSize: Int = CodexLogMonitor.defaultBootstrapChunkSize
    ) {
        precondition(bootstrapChunkSize > 0)
        self.logRoot = logRoot
        self.runningCodexProcessProvider = {
            runningCodexPIDProvider().map {
                CodexProcessIdentity(pid: $0, launchDate: nil)
            }
        }
        self.bootstrapChunkSize = bootstrapChunkSize
    }

    public func bootstrap() throws -> CodexSelection? {
        guard let runningProcess = runningCodexProcessProvider() else {
            selectedProcess = nil
            cursors.removeAll()
            latest = nil
            throw CodexProbeError.noCodexLog
        }
        selectedProcess = runningProcess
        let files = try candidateLogFiles(for: runningProcess)
        guard !files.isEmpty else {
            cursors.removeAll()
            latest = nil
            throw CodexProbeError.noCodexLog
        }
        try bootstrap(from: files)
        return latest
    }

    public func poll() throws -> CodexSelection? {
        pollCounter += 1
        let currentProcess = runningCodexProcessProvider()

        guard let currentProcess else {
            selectedProcess = nil
            cursors.removeAll()
            latest = nil
            throw CodexProbeError.noCodexLog
        }

        if currentProcess != selectedProcess {
            selectedProcess = currentProcess
            let files = try candidateLogFiles(for: currentProcess)
            guard !files.isEmpty else {
                cursors.removeAll()
                latest = nil
                throw CodexProbeError.noCodexLog
            }
            try bootstrap(from: files)
            return latest
        }

        let lostCursorContinuity = try drainIncrementalCursors()

        if lostCursorContinuity || cursors.isEmpty {
            let files = try candidateLogFiles(for: currentProcess)
            guard !files.isEmpty else {
                cursors.removeAll()
                latest = nil
                throw CodexProbeError.noCodexLog
            }
            // A rotated file can be renamed between polls. Re-bootstrap the
            // current launch family so an unread tail selection in that old
            // inode is recovered before following the new active log.
            try bootstrap(from: files)
        } else if pollCounter % 6 == 0 {
            // Drain the current file to its snapshot EOF before replacing its
            // cursor with a newer rotation target. Reversing this order can
            // permanently skip the old file's final selection event.
            let files = try candidateLogFiles(for: currentProcess)
            guard !files.isEmpty else {
                cursors.removeAll()
                latest = nil
                throw CodexProbeError.noCodexLog
            }
            if let nextActiveFile = files.first,
               cursors[nextActiveFile] == nil {
                // A final event can land in the old file after the first drain
                // but before rotation becomes visible to enumeration. Once a
                // different active URL exists, drain the old cursor again at
                // its now-sealed snapshot EOF before switching targets.
                let lostDuringFinalDrain = try drainIncrementalCursors()
                if lostDuringFinalDrain || cursors.isEmpty {
                    let refreshedFiles = try candidateLogFiles(for: currentProcess)
                    guard !refreshedFiles.isEmpty else {
                        cursors.removeAll()
                        latest = nil
                        throw CodexProbeError.noCodexLog
                    }
                    try bootstrap(from: refreshedFiles)
                    return latest
                }
            }
            try reconcileIncrementalCursor(with: files)
        }
        return latest
    }

    private func drainIncrementalCursors() throws -> Bool {
        var lostCursorContinuity = false
        for file in Array(cursors.keys) {
            do {
                if try readAppendedData(from: file) {
                    lostCursorContinuity = true
                }
            } catch where isMissingFileError(error) {
                cursors.removeValue(forKey: file)
                lostCursorContinuity = true
            }
        }
        return lostCursorContinuity
    }

    private func candidateLogFiles(
        for process: CodexProcessIdentity
    ) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: logRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw CodexProbeError.logDirectoryMissing(logRoot.path)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: logRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw CodexProbeError.logDirectoryMissing(logRoot.path)
        }

        var matches: [(url: URL, modified: Date, family: String)] = []
        let pidMarker = "-\(process.pid)-t0-"
        let earliestCurrentLaunchDate = process.launchDate?.addingTimeInterval(-5)

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasSuffix(".log"), name.contains("-t0-") else { continue }
            guard let pidRange = name.range(of: pidMarker, options: .backwards) else {
                continue
            }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let modified = values?.contentModificationDate ?? .distantPast
            if let earliestCurrentLaunchDate,
               modified < earliestCurrentLaunchDate {
                continue
            }
            matches.append(
                (
                    url,
                    modified,
                    String(name[..<pidRange.lowerBound])
                )
            )
        }

        let sorted = matches.sorted { $0.modified > $1.modified }
        guard let currentLaunchFamily = sorted.first?.family else { return [] }
        return sorted
            .filter { $0.family == currentLaunchFamily }
            .map(\.url)
    }

    private func bootstrap(from files: [URL]) throws {
        cursors.removeAll()
        latest = nil

        var newestSeed: (file: URL, seed: LogSeed)?
        for file in files {
            guard let seed = try makeSeed(for: file) else { continue }
            if newestSeed == nil {
                newestSeed = (file, seed)
            }
            guard let selection = seed.selection else { continue }
            latest = selection
            break
        }

        // Only the newest surviving log can receive normal forward appends.
        // Older rotated files are bootstrap history, not 250 ms poll targets.
        guard let newestSeed else { throw CodexProbeError.noCodexLog }
        cursors[newestSeed.file] = newestSeed.seed.cursor
    }

    private func reconcileIncrementalCursor(with files: [URL]) throws {
        for activeFile in files {
            if let existing = cursors[activeFile] {
                cursors = [activeFile: existing]
                return
            }
            guard let seed = try makeSeed(for: activeFile) else { continue }
            if let selection = seed.selection,
               latest == nil || selection.timestamp >= latest!.timestamp {
                latest = selection
            }
            cursors = [activeFile: seed.cursor]
            return
        }

        cursors.removeAll()
        throw CodexProbeError.noCodexLog
    }

    private func makeSeed(for file: URL) throws -> LogSeed? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        } catch where isMissingFileError(error) {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let fileIdentity = identity(from: attributes)

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch where isMissingFileError(error) {
            return nil
        } catch {
            throw CodexProbeError.unreadableLog(file.path)
        }
        defer { try? handle.close() }

        let scan: (selection: CodexSelection?, trailingRemainder: Data)
        do {
            scan = try scanBackwardForLatestSelection(
                in: handle,
                fileSize: size
            )
        } catch where isMissingFileError(error) {
            return nil
        }
        let anchor = try readAnchor(from: handle, endingAt: size)

        // Bootstrap reads a snapshot ending at `size`. Keeping that exact EOF
        // offset and its unterminated trailing line preserves the same
        // incremental behavior as forward polling.
        return LogSeed(
            selection: scan.selection,
            cursor: LogCursor(
                offset: size,
                remainder: scan.trailingRemainder,
                anchor: anchor,
                fileIdentity: fileIdentity
            )
        )
    }

    private func scanBackwardForLatestSelection(
        in handle: FileHandle,
        fileSize: UInt64
    ) throws -> (selection: CodexSelection?, trailingRemainder: Data) {
        var position = fileSize
        var lineSuffix = Data()
        var trailingRemainder: Data?

        while position > 0 {
            let byteCount = Int(min(UInt64(bootstrapChunkSize), position))
            position -= UInt64(byteCount)
            try handle.seek(toOffset: position)
            let chunk = try readData(from: handle, upToCount: byteCount)

            var segmentEnd = chunk.endIndex
            var index = chunk.endIndex
            while index > chunk.startIndex {
                index = chunk.index(before: index)
                guard chunk[index] == 0x0A else { continue }

                var line = Data(
                    chunk[chunk.index(after: index)..<segmentEnd]
                )
                line.append(lineSuffix)

                if trailingRemainder == nil {
                    // The bytes after the final newline are intentionally not
                    // parsed until a later poll completes that line.
                    trailingRemainder = line
                } else if let selection = parse(line: line) {
                    return (selection, trailingRemainder ?? Data())
                }

                lineSuffix.removeAll(keepingCapacity: true)
                segmentEnd = index
            }

            if segmentEnd > chunk.startIndex {
                var combined = Data(chunk[chunk.startIndex..<segmentEnd])
                combined.append(lineSuffix)
                lineSuffix = combined
            }
        }

        guard let trailingRemainder else {
            // A file without any newline consists entirely of an unfinished
            // line, matching `consume`'s remainder behavior.
            return (nil, lineSuffix)
        }

        // The first line has no preceding newline but is complete whenever the
        // file contained at least one newline after it.
        return (
            parse(line: lineSuffix),
            trailingRemainder
        )
    }

    private func parse(line data: Data) -> CodexSelection? {
        CodexSelectionParser.parse(
            line: String(decoding: data, as: UTF8.self)
        )
    }

    /// Returns `true` when the stored cursor no longer describes a continuous
    /// byte stream and the current launch family must be bootstrapped again.
    private func readAppendedData(from file: URL) throws -> Bool {
        guard var cursor = cursors[file] else { return false }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let fileIdentity = identity(from: attributes)

        if fileIdentity != cursor.fileIdentity {
            // Log rotation can replace a file at the same path with a new inode
            // whose size is already larger than the old cursor. Reseeding is
            // the only safe way to avoid silently skipping its beginning.
            cursors.removeValue(forKey: file)
            return true
        }

        if size < cursor.offset {
            cursors.removeValue(forKey: file)
            return true
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch where isMissingFileError(error) {
            cursors.removeValue(forKey: file)
            return true
        } catch {
            throw CodexProbeError.unreadableLog(file.path)
        }
        defer { try? handle.close() }

        let currentAnchor = try readAnchor(
            from: handle,
            endingAt: cursor.offset
        )
        if currentAnchor != cursor.anchor {
            // copytruncate can rewrite the same inode and regrow beyond the old
            // offset between polls. Verify a small byte anchor before trusting
            // that offset, otherwise reseed the rewritten file.
            cursors.removeValue(forKey: file)
            return true
        }

        guard size > cursor.offset else {
            cursors[file] = cursor
            return false
        }

        try handle.seek(toOffset: cursor.offset)
        while cursor.offset < size {
            let byteCount = Int(
                min(UInt64(bootstrapChunkSize), size - cursor.offset)
            )
            let data = try readData(from: handle, upToCount: byteCount)
            guard !data.isEmpty else { break }

            var bufferedData = cursor.remainder
            bufferedData.append(data)
            let nextAnchor = updatedAnchor(
                previous: cursor.anchor,
                appended: data
            )
            cursor = consume(
                data: bufferedData,
                offset: cursor.offset + UInt64(data.count),
                anchor: nextAnchor,
                fileIdentity: fileIdentity
            )
            cursors[file] = cursor
        }
        return false
    }

    private func consume(
        data: Data,
        offset: UInt64,
        anchor: Data,
        fileIdentity: LogFileIdentity
    ) -> LogCursor {
        var lineStart = data.startIndex
        var index = data.startIndex

        while index < data.endIndex {
            if data[index] == 0x0A {
                let line = Data(data[lineStart..<index])
                if let selection = parse(line: line),
                   latest == nil || selection.timestamp >= latest!.timestamp {
                    latest = selection
                }
                lineStart = data.index(after: index)
            }
            index = data.index(after: index)
        }

        return LogCursor(
            offset: offset,
            remainder: Data(data[lineStart..<data.endIndex]),
            anchor: anchor,
            fileIdentity: fileIdentity
        )
    }

    private func readData(
        from handle: FileHandle,
        upToCount byteCount: Int
    ) throws -> Data {
        var result = Data()
        result.reserveCapacity(byteCount)

        while result.count < byteCount {
            let remaining = byteCount - result.count
            guard let chunk = try handle.read(upToCount: remaining),
                  !chunk.isEmpty
            else { break }
            result.append(chunk)
        }
        return result
    }

    private func readAnchor(
        from handle: FileHandle,
        endingAt offset: UInt64
    ) throws -> Data {
        let byteCount = Int(min(UInt64(Self.cursorAnchorSize), offset))
        guard byteCount > 0 else { return Data() }
        try handle.seek(toOffset: offset - UInt64(byteCount))
        return try readData(from: handle, upToCount: byteCount)
    }

    private func updatedAnchor(previous: Data, appended: Data) -> Data {
        if appended.count >= Self.cursorAnchorSize {
            return Data(appended.suffix(Self.cursorAnchorSize))
        }

        var combined = previous
        combined.append(appended)
        return Data(combined.suffix(Self.cursorAnchorSize))
    }

    private func identity(
        from attributes: [FileAttributeKey: Any]
    ) -> LogFileIdentity {
        LogFileIdentity(
            systemNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileNoSuchFileError
                || nsError.code == NSFileReadNoSuchFileError
        }
        if let posixError = error as? POSIXError {
            return posixError.code == .ENOENT
        }
        return false
    }
}
