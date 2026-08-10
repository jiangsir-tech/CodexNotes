import CryptoKit
import Foundation

public enum NoteScope: String, CaseIterable, Codable, Sendable {
    case task
    case project

    public var displayName: String {
        switch self {
        case .task: return L10n.text(.noteScopeTask)
        case .project: return L10n.text(.noteScopeProject)
        }
    }
}

public struct NoteDocument: Hashable, Sendable {
    public let scope: NoteScope
    public let stableKey: String
    public let displayName: String
    public let context: String?
    public let fileURL: URL

    public init(
        scope: NoteScope,
        stableKey: String,
        displayName: String,
        context: String?,
        fileURL: URL
    ) {
        self.scope = scope
        self.stableKey = stableKey
        self.displayName = displayName
        self.context = context
        self.fileURL = fileURL
    }
}

public enum NoteStoreError: LocalizedError, Sendable {
    case projectUnavailable
    case cannotCreateDirectory(String)
    case cannotRead(String)
    case cannotWrite(String)
    case migrationConflict(String)

    public var errorDescription: String? {
        switch self {
        case .projectUnavailable:
            return L10n.text(.noteStoreErrorProjectUnavailable)
        case let .cannotCreateDirectory(path):
            return L10n.text(
                .noteStoreErrorCannotCreateDirectory,
                replacements: ["path": path]
            )
        case let .cannotRead(path):
            return L10n.text(
                .noteStoreErrorCannotRead,
                replacements: ["path": path]
            )
        case let .cannotWrite(path):
            return L10n.text(
                .noteStoreErrorCannotSave,
                replacements: ["path": path]
            )
        case let .migrationConflict(path):
            return L10n.text(
                .noteStoreErrorMigrationConflict,
                replacements: ["path": path]
            )
        }
    }
}

public final class NoteStore: @unchecked Sendable {
    public let rootURL: URL
    private let atomicWrite: @Sendable (Data, URL) throws -> Void
    private let readUTF8: @Sendable (URL) throws -> String

    public init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            self.rootURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("Codex Task Notes", isDirectory: true)
                .appendingPathComponent("Notes", isDirectory: true)
        }
        self.atomicWrite = { data, url in
            try data.write(to: url, options: .atomic)
        }
        self.readUTF8 = { url in
            try String(contentsOf: url, encoding: .utf8)
        }
    }

    init(
        rootURL: URL,
        atomicWrite: @escaping @Sendable (Data, URL) throws -> Void,
        readUTF8: @escaping @Sendable (URL) throws -> String = { url in
            try String(contentsOf: url, encoding: .utf8)
        }
    ) {
        self.rootURL = rootURL
        self.atomicWrite = atomicWrite
        self.readUTF8 = readUTF8
    }

    public func taskDocument(
        selection: CodexSelection,
        metadata: CodexThreadMetadata?
    ) -> NoteDocument {
        let filename: String
        if selection.kind == .local,
           selection.hostID == nil,
           let threadID = selection.threadID,
           isSafeIdentifier(threadID) {
            filename = "\(threadID).md"
        } else {
            let prefix: String
            switch selection.kind {
            case .local: prefix = selection.hostID == nil ? "task" : "remote"
            case .work: prefix = "work"
            case .newTask: prefix = "draft"
            case .unknown: prefix = "unknown"
            }
            filename = "\(prefix)-\(digest(selection.stableKey)).md"
        }

        return NoteDocument(
            scope: .task,
            stableKey: selection.stableKey,
            displayName: metadata?.name ?? fallbackTaskName(for: selection),
            context: metadata?.cwd,
            fileURL: rootURL
                .appendingPathComponent("Tasks", isDirectory: true)
                .appendingPathComponent(filename)
        )
    }

    public func projectDocument(
        selection: CodexSelection,
        metadata: CodexThreadMetadata?
    ) throws -> NoteDocument {
        guard metadata?.projectMembership.isAssigned == true,
              let cwd = metadata?.cwd.trimmingCharacters(in: .whitespacesAndNewlines),
              !cwd.isEmpty
        else {
            throw NoteStoreError.projectUnavailable
        }

        let normalizedPath = normalizeProjectPath(cwd, remote: selection.hostID != nil)
        let hostKey = selection.hostID ?? "local"
        let stableKey = "project:\(hostKey):\(normalizedPath)"
        let folderName: String
        if selection.hostID != nil {
            folderName = normalizedPath.split(separator: "/").last.map(String.init) ?? ""
        } else {
            folderName = URL(fileURLWithPath: normalizedPath).lastPathComponent
        }
        let readableName = sanitizeFilename(folderName.isEmpty ? "Project" : folderName)
        let filename = "\(readableName)-\(digest(stableKey)).md"

        return NoteDocument(
            scope: .project,
            stableKey: stableKey,
            displayName: folderName.isEmpty ? cwd : folderName,
            context: cwd,
            fileURL: rootURL
                .appendingPathComponent("Projects", isDirectory: true)
                .appendingPathComponent(filename)
        )
    }

    public func load(_ document: NoteDocument) throws -> String {
        guard FileManager.default.fileExists(atPath: document.fileURL.path) else {
            return ""
        }
        do {
            return try readUTF8(document.fileURL)
        } catch {
            throw NoteStoreError.cannotRead(document.fileURL.path)
        }
    }

    public func save(_ text: String, to document: NoteDocument) throws {
        if text.isEmpty, !FileManager.default.fileExists(atPath: document.fileURL.path) {
            return
        }

        let directory = document.fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw NoteStoreError.cannotCreateDirectory(directory.path)
        }

        do {
            try atomicWrite(Data(text.utf8), document.fileURL)
        } catch {
            throw NoteStoreError.cannotWrite(document.fileURL.path)
        }
    }

    @discardableResult
    public func mergeDraftIfNeeded(
        from source: NoteDocument,
        into destination: NoteDocument
    ) throws -> String? {
        guard source.fileURL != destination.fileURL,
              FileManager.default.fileExists(atPath: source.fileURL.path)
        else {
            return nil
        }

        let draft = try load(source)
        guard !draft.isEmpty else { return nil }

        let existing = try load(destination)
        let merged: String
        if existing.isEmpty {
            merged = draft
        } else if existing == draft {
            merged = existing
        } else {
            throw NoteStoreError.migrationConflict(source.fileURL.path)
        }
        try save(merged, to: destination)
        return merged
    }

    public func ensureRootDirectory() throws {
        do {
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw NoteStoreError.cannotCreateDirectory(rootURL.path)
        }
    }

    private func fallbackTaskName(for selection: CodexSelection) -> String {
        switch selection.kind {
        case .local:
            return L10n.text(
                selection.hostID == nil ? .taskFallbackLocal : .taskFallbackRemote
            )
        case .work:
            return L10n.text(.taskFallbackWork)
        case .newTask:
            return L10n.text(.taskFallbackNewDraft)
        case .unknown:
            return L10n.text(.taskFallbackUnknown)
        }
    }

    private func normalizeProjectPath(_ path: String, remote: Bool) -> String {
        if remote {
            return path.replacingOccurrences(of: "\\", with: "/")
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }

    private func sanitizeFilename(_ value: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:\n\r\t")
        let parts = value.components(separatedBy: disallowed)
        let result = parts.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((result.isEmpty ? "Project" : result).prefix(48))
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(6)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
