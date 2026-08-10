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
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.openai.codex" })?
            .processIdentifier
    }
}

private struct LogCursor: Sendable {
    var offset: UInt64
    var remainder: String
}

public actor CodexLogMonitor {
    private let logRoot: URL
    private var cursors: [URL: LogCursor] = [:]
    private var latest: CodexSelection?
    private var pollCounter = 0
    private var selectedPID: pid_t?

    public init(logRoot: URL = CodexEnvironment.defaultLogRoot) {
        self.logRoot = logRoot
    }

    public func bootstrap() throws -> CodexSelection? {
        selectedPID = CodexEnvironment.runningCodexPID()
        let files = try candidateLogFiles(pid: selectedPID)
        guard !files.isEmpty else { throw CodexProbeError.noCodexLog }

        for file in files.prefix(40) {
            try seed(file: file)
        }
        return latest
    }

    public func poll() throws -> CodexSelection? {
        pollCounter += 1
        let currentPID = CodexEnvironment.runningCodexPID()

        if currentPID != selectedPID || pollCounter % 6 == 0 {
            if currentPID != selectedPID {
                cursors.removeAll()
                latest = nil
                selectedPID = currentPID
            }

            for file in try candidateLogFiles(pid: selectedPID).prefix(40) where cursors[file] == nil {
                try seed(file: file)
            }
        }

        for file in cursors.keys {
            try readAppendedData(from: file)
        }
        return latest
    }

    private func candidateLogFiles(pid: pid_t?) throws -> [URL] {
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

        var matches: [(url: URL, modified: Date)] = []
        let pidMarker = pid.map { "-\($0)-t0-" }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasSuffix(".log"), name.contains("-t0-") else { continue }
            if let pidMarker, !name.contains(pidMarker) { continue }

            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            matches.append((url, values?.contentModificationDate ?? .distantPast))
        }

        return matches
            .sorted { $0.modified > $1.modified }
            .map(\.url)
    }

    private func seed(file: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let maximumTail: UInt64 = 2_000_000
        let start = size > maximumTail ? size - maximumTail : 0

        guard let handle = try? FileHandle(forReadingFrom: file) else {
            throw CodexProbeError.unreadableLog(file.path)
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()
        var text = String(decoding: data, as: UTF8.self)

        if start > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }

        consume(text: text, file: file, offset: size)
    }

    private func readAppendedData(from file: URL) throws {
        guard var cursor = cursors[file] else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

        if size < cursor.offset {
            cursor = LogCursor(offset: 0, remainder: "")
        }
        guard size > cursor.offset else {
            cursors[file] = cursor
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: file) else {
            throw CodexProbeError.unreadableLog(file.path)
        }
        defer { try? handle.close() }

        try handle.seek(toOffset: cursor.offset)
        let data = try handle.readToEnd() ?? Data()
        let text = cursor.remainder + String(decoding: data, as: UTF8.self)
        consume(text: text, file: file, offset: size)
    }

    private func consume(text: String, file: URL, offset: UInt64) {
        let endsWithNewline = text.last == "\n"
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let remainder = endsWithNewline ? "" : (lines.popLast() ?? "")

        for line in lines {
            guard let selection = CodexSelectionParser.parse(line: line) else { continue }
            if latest == nil || selection.timestamp >= latest!.timestamp {
                latest = selection
            }
        }

        cursors[file] = LogCursor(offset: offset, remainder: remainder)
    }
}
