import SQLite3
import XCTest
@testable import CodexNotesCore

final class CodexThreadStoreTests: XCTestCase {
    private var directory: URL!
    private var databaseURL: URL!
    private var globalStateURL: URL!
    private var sessionIndexURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseURL = directory.appendingPathComponent("state.sqlite")
        globalStateURL = directory.appendingPathComponent("global-state.json")
        sessionIndexURL = directory.appendingPathComponent("session_index.jsonl")

        try executeSQL("""
        CREATE TABLE threads (
          id TEXT PRIMARY KEY,
          name TEXT,
          title TEXT,
          cwd TEXT NOT NULL,
          history_mode TEXT NOT NULL,
          first_user_message TEXT NOT NULL
        );
        INSERT INTO threads (id, name, title, cwd, history_mode, first_user_message)
        VALUES (
          'thread-a', NULL, '旧任务名称', '/tmp/project', 'legacy', '旧任务名称'
        );
        """)
        try writeProjectState(name: "旧 Project 名称")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testReflectsTaskAndProjectRenamesWithoutRecreatingStore() throws {
        let projectStore = CodexProjectStore(globalStateURL: globalStateURL)
        let store = CodexThreadStore(
            databaseURL: databaseURL,
            projectStore: projectStore,
            sessionIndexURL: sessionIndexURL
        )

        XCTAssertEqual(
            store.metadata(for: "thread-a"),
            CodexThreadMetadata(
                id: "thread-a",
                name: "旧任务名称",
                cwd: "/tmp/project",
                projectMembership: .assigned(
                    kind: "local",
                    id: "project-a",
                    name: "旧 Project 名称"
                )
            )
        )

        try executeSQL("UPDATE threads SET title = '新任务名称' WHERE id = 'thread-a';")
        try writeProjectState(name: "新 Project 名称")

        XCTAssertEqual(
            store.metadata(for: "thread-a"),
            CodexThreadMetadata(
                id: "thread-a",
                name: "新任务名称",
                cwd: "/tmp/project",
                projectMembership: .assigned(
                    kind: "local",
                    id: "project-a",
                    name: "新 Project 名称"
                )
            )
        )
    }

    func testCarriesExplicitProjectlessMembershipEvenWithWorkingDirectory() throws {
        try writeProjectlessState()
        let store = CodexThreadStore(
            databaseURL: databaseURL,
            projectStore: CodexProjectStore(globalStateURL: globalStateURL),
            sessionIndexURL: sessionIndexURL
        )

        let metadata = try XCTUnwrap(store.metadata(for: "thread-a"))
        XCTAssertEqual(metadata.cwd, "/tmp/project")
        XCTAssertEqual(metadata.projectMembership, .none)
        XCTAssertNil(metadata.projectName)
    }

    func testCarriesUnknownMembershipWhenProjectStateIsMalformed() throws {
        try Data("not json".utf8).write(to: globalStateURL, options: .atomic)
        let store = CodexThreadStore(
            databaseURL: databaseURL,
            projectStore: CodexProjectStore(globalStateURL: globalStateURL),
            sessionIndexURL: sessionIndexURL
        )

        let metadata = try XCTUnwrap(store.metadata(for: "thread-a"))
        XCTAssertEqual(metadata.projectMembership, .unknown)
        XCTAssertNil(metadata.projectName)
    }

    func testLegacyProjectNameInitializerRemainsSourceCompatible() {
        let metadata = CodexThreadMetadata(
            id: "thread-a",
            name: "任务",
            cwd: "/tmp/project",
            projectName: "兼容项目名"
        )

        XCTAssertEqual(metadata.projectName, "兼容项目名")
        XCTAssertTrue(metadata.projectMembership.isAssigned)
    }

    func testLegacyTaskUsesLatestSessionIndexName() throws {
        let projectStore = CodexProjectStore(globalStateURL: globalStateURL)
        let store = CodexThreadStore(
            databaseURL: databaseURL,
            projectStore: projectStore,
            sessionIndexURL: sessionIndexURL
        )
        try Data(
            """
            {"id":"thread-a","thread_name":"第一次改名","updated_at":"2026-08-08T00:00:00Z"}
            {"id":"other","thread_name":"其他任务","updated_at":"2026-08-08T00:00:01Z"}
            {"id":"thread-a","thread_name":"侧边栏最新名称","updated_at":"2026-08-08T00:00:02Z"}

            """.utf8
        ).write(to: sessionIndexURL)

        XCTAssertEqual(store.metadata(for: "thread-a")?.name, "侧边栏最新名称")
    }

    func testLegacyTaskPrefersDistinctDatabaseTitleOverStaleSessionIndex() throws {
        try executeSQL("UPDATE threads SET title = '数据库明确改名' WHERE id = 'thread-a';")
        try Data(
            """
            {"id":"thread-a","thread_name":"索引中的旧名称","updated_at":"2026-08-08T00:00:00Z"}

            """.utf8
        ).write(to: sessionIndexURL)

        let store = CodexThreadStore(
            databaseURL: databaseURL,
            projectStore: CodexProjectStore(globalStateURL: globalStateURL),
            sessionIndexURL: sessionIndexURL
        )
        XCTAssertEqual(store.metadata(for: "thread-a")?.name, "数据库明确改名")
    }

    func testPaginatedTaskPrefersDatabaseNameOverSessionIndex() throws {
        try executeSQL("""
        UPDATE threads
        SET name = '数据库最新名称', history_mode = 'paginated'
        WHERE id = 'thread-a';
        """)
        try Data(
            """
            {"id":"thread-a","thread_name":"旧索引名称","updated_at":"2026-08-08T00:00:00Z"}

            """.utf8
        ).write(to: sessionIndexURL)

        let store = CodexThreadStore(
            databaseURL: databaseURL,
            projectStore: CodexProjectStore(globalStateURL: globalStateURL),
            sessionIndexURL: sessionIndexURL
        )
        XCTAssertEqual(store.metadata(for: "thread-a")?.name, "数据库最新名称")
    }

    private func executeSQL(_ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK,
              let database
        else {
            if database != nil { sqlite3_close(database) }
            throw SQLiteFixtureError.open
        }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteFixtureError.execute
        }
    }

    private func writeProjectState(name: String) throws {
        let fixture = """
        {
          "projectless-thread-ids": [],
          "thread-project-assignments": {
            "thread-a": {"projectKind": "local", "projectId": "project-a"}
          },
          "local-projects": {
            "project-a": {"name": "\(name)"}
          },
          "remote-projects": []
        }
        """
        try Data(fixture.utf8).write(to: globalStateURL, options: .atomic)
    }

    private func writeProjectlessState() throws {
        let fixture = """
        {
          "projectless-thread-ids": ["thread-a"],
          "thread-project-assignments": {
            "thread-a": {"projectKind": "local", "projectId": "project-a"}
          },
          "local-projects": {
            "project-a": {"name": "应被忽略的陈旧项目"}
          },
          "remote-projects": []
        }
        """
        try Data(fixture.utf8).write(to: globalStateURL, options: .atomic)
    }
}

private enum SQLiteFixtureError: Error {
    case open
    case execute
}
