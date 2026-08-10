import Foundation
import SQLite3

public struct CodexThreadMetadata: Equatable, Sendable {
    public let id: String
    public let name: String
    public let cwd: String
    public let projectMembership: CodexProjectMembership

    public var projectName: String? {
        projectMembership.projectName
    }

    public init(
        id: String,
        name: String,
        cwd: String,
        projectMembership: CodexProjectMembership
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.projectMembership = projectMembership
    }

    public init(id: String, name: String, cwd: String, projectName: String? = nil) {
        self.init(
            id: id,
            name: name,
            cwd: cwd,
            projectMembership: projectName.map {
                .assigned(kind: "legacy", id: "legacy:\(id)", name: $0)
            } ?? .none
        )
    }
}

public protocol CodexThreadMetadataProviding: Sendable {
    func metadata(for threadID: String) -> CodexThreadMetadata?
}

public final class CodexThreadStore: CodexThreadMetadataProviding, @unchecked Sendable {
    private struct SessionIndexEntry: Decodable {
        let id: String
        let threadName: String

        enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
        }
    }

    private let databaseURL: URL
    private let projectStore: CodexProjectStore
    private let sessionIndexURL: URL

    public init(
        databaseURL: URL = CodexEnvironment.defaultStateDatabase,
        projectStore: CodexProjectStore = CodexProjectStore(),
        sessionIndexURL: URL? = nil
    ) {
        self.databaseURL = databaseURL
        self.projectStore = projectStore
        self.sessionIndexURL = sessionIndexURL
            ?? databaseURL.deletingLastPathComponent().appendingPathComponent("session_index.jsonl")
    }

    public func metadata(for threadID: String) -> CodexThreadMetadata? {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let database
        else {
            if database != nil { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 300)

        let sql = """
        SELECT id,
               name,
               title,
               cwd,
               COALESCE(history_mode, 'legacy'),
               first_user_message
        FROM threads
        WHERE id = ?
        LIMIT 1
        """

        let compatibilitySQL = """
        SELECT id,
               name,
               title,
               cwd,
               'legacy',
               ''
        FROM threads
        WHERE id = ?
        LIMIT 1
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(database, sql, -1, &statement, nil) != SQLITE_OK {
            if statement != nil { sqlite3_finalize(statement) }
            statement = nil
            guard sqlite3_prepare_v2(
                database,
                compatibilitySQL,
                -1,
                &statement,
                nil
            ) == SQLITE_OK else {
                if statement != nil { sqlite3_finalize(statement) }
                return nil
            }
        }
        guard let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, 1, threadID, -1, transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW
        else {
            return nil
        }

        func text(at column: Int32) -> String {
            guard let value = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: value)
        }

        let storedName = normalizedName(text(at: 1))
        let storedTitle = normalizedName(text(at: 2))
        let historyMode = text(at: 4)
        let firstUserMessage = text(at: 5).trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = storedName ?? storedTitle ?? L10n.text(.taskFallbackUntitled)

        let resolvedName: String
        if historyMode == "legacy" {
            let distinctTitle = storedTitle.flatMap { title in
                title != firstUserMessage ? title : nil
            }
            resolvedName = distinctTitle
                ?? latestSessionIndexName(for: threadID)
                ?? storedTitle
                ?? storedName
                ?? L10n.text(.taskFallbackUntitled)
        } else {
            resolvedName = fallbackName
        }

        return CodexThreadMetadata(
            id: text(at: 0),
            name: resolvedName,
            cwd: text(at: 3),
            projectMembership: projectStore.membership(for: threadID)
        )
    }

    private func normalizedName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func latestSessionIndexName(for threadID: String) -> String? {
        guard let data = try? Data(contentsOf: sessionIndexURL) else { return nil }

        let decoder = JSONDecoder()
        var latestName: String?
        for line in data.split(separator: 0x0A) {
            guard line.range(of: Data(threadID.utf8)) != nil,
                  let entry = try? decoder.decode(SessionIndexEntry.self, from: Data(line)),
                  entry.id == threadID
            else { continue }

            let name = entry.threadName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                latestName = name
            }
        }
        return latestName
    }
}
