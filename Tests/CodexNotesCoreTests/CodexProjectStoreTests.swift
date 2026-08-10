import XCTest
@testable import CodexNotesCore

final class CodexProjectStoreTests: XCTestCase {
    private var directory: URL!
    private var stateURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateURL = directory.appendingPathComponent("state.json")
        try Data(Self.fixture.utf8).write(to: stateURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testResolvesLocalProjectName() {
        let store = CodexProjectStore(globalStateURL: stateURL)
        XCTAssertEqual(
            store.membership(for: "local-thread"),
            .assigned(kind: "local", id: "local-project", name: "自定义项目名")
        )
        XCTAssertEqual(store.projectName(for: "local-thread"), "自定义项目名")
    }

    func testResolvesRemoteProjectLabel() {
        let store = CodexProjectStore(globalStateURL: stateURL)
        XCTAssertEqual(
            store.membership(for: "remote-thread"),
            .assigned(kind: "remote", id: "remote-project", name: "远程 Project")
        )
        XCTAssertEqual(store.projectName(for: "remote-thread"), "远程 Project")
    }

    func testProjectlessListOverridesStaleAssignment() {
        let store = CodexProjectStore(globalStateURL: stateURL)
        XCTAssertEqual(store.membership(for: "projectless-thread"), .none)
        XCTAssertNil(store.projectName(for: "projectless-thread"))
    }

    func testUnknownThreadHasNoProjectName() {
        let store = CodexProjectStore(globalStateURL: stateURL)
        XCTAssertEqual(store.membership(for: "unknown-thread"), .none)
        XCTAssertNil(store.projectName(for: "unknown-thread"))
    }

    func testAssignmentWithBlankNameRemainsAssigned() {
        let store = CodexProjectStore(globalStateURL: stateURL)

        XCTAssertEqual(
            store.membership(for: "unnamed-thread"),
            .assigned(kind: "local", id: "unnamed-project", name: nil)
        )
        XCTAssertNil(store.projectName(for: "unnamed-thread"))
    }

    func testMissingProjectRecordIsUnknownInsteadOfUnnamed() {
        let store = CodexProjectStore(globalStateURL: stateURL)

        XCTAssertEqual(store.membership(for: "missing-record-thread"), .unknown)
        XCTAssertNil(store.projectName(for: "missing-record-thread"))
    }

    func testUnsupportedProjectKindIsUnknown() {
        let store = CodexProjectStore(globalStateURL: stateURL)

        XCTAssertEqual(store.membership(for: "unsupported-thread"), .unknown)
        XCTAssertNil(store.projectName(for: "unsupported-thread"))
    }

    func testMissingStateFileIsUnknown() throws {
        try FileManager.default.removeItem(at: stateURL)
        let store = CodexProjectStore(globalStateURL: stateURL)

        XCTAssertEqual(store.membership(for: "local-thread"), .unknown)
        XCTAssertNil(store.projectName(for: "local-thread"))
        XCTAssertEqual(store.globalProjectCandidate(), .unknown)
    }

    func testMalformedStateFileIsUnknown() throws {
        try Data("not json".utf8).write(to: stateURL, options: .atomic)
        let store = CodexProjectStore(globalStateURL: stateURL)

        XCTAssertEqual(store.membership(for: "local-thread"), .unknown)
        XCTAssertNil(store.projectName(for: "local-thread"))
        XCTAssertEqual(store.globalProjectCandidate(), .unknown)
    }

    func testMissingProjectContainersAreUnknownUnlessAbsenceIsExplicit() throws {
        let store = CodexProjectStore(globalStateURL: stateURL)

        for fixture in [
            "{}",
            #"{"projectless-thread-ids": []}"#,
            #"{"thread-project-assignments": {}}"#,
        ] {
            try Data(fixture.utf8).write(to: stateURL, options: .atomic)
            XCTAssertEqual(store.membership(for: "thread-a"), .unknown)
        }

        try Data(
            #"{"projectless-thread-ids": [], "thread-project-assignments": {}}"#.utf8
        ).write(to: stateURL, options: .atomic)
        XCTAssertEqual(store.membership(for: "thread-a"), .none)
    }

    func testExplicitProjectlessAndAssignmentDoNotRequireBothContainers() throws {
        let store = CodexProjectStore(globalStateURL: stateURL)

        try Data(
            #"{"projectless-thread-ids": ["thread-a"]}"#.utf8
        ).write(to: stateURL, options: .atomic)
        XCTAssertEqual(store.membership(for: "thread-a"), .none)

        let assignedOnly = """
        {
          "thread-project-assignments": {
            "thread-a": {"projectKind": "local", "projectId": "project-a"}
          },
          "local-projects": {
            "project-a": {"name": "项目 A"}
          }
        }
        """
        try Data(assignedOnly.utf8).write(to: stateURL, options: .atomic)
        XCTAssertEqual(
            store.membership(for: "thread-a"),
            .assigned(kind: "local", id: "project-a", name: "项目 A")
        )
    }

    func testReflectsRenamedProjectWithoutRecreatingStore() throws {
        let store = CodexProjectStore(globalStateURL: stateURL)
        XCTAssertEqual(store.projectName(for: "local-thread"), "自定义项目名")

        let renamedFixture = Self.fixture.replacingOccurrences(
            of: "  自定义项目名  ",
            with: "实时同步后的名称"
        )
        try Data(renamedFixture.utf8).write(to: stateURL, options: .atomic)

        XCTAssertEqual(
            store.membership(for: "local-thread"),
            .assigned(kind: "local", id: "local-project", name: "实时同步后的名称")
        )
        XCTAssertEqual(store.projectName(for: "local-thread"), "实时同步后的名称")
    }

    func testResolvesLocalGlobalProjectCandidate() {
        let store = CodexProjectStore(globalStateURL: stateURL)
        let candidate = CodexGlobalProjectCandidate(
            kind: "local",
            id: "local-project",
            name: "自定义项目名",
            rootPath: "/tmp/项目 A",
            hostID: nil
        )

        XCTAssertEqual(store.globalProjectCandidate(), .selected(candidate))
        XCTAssertEqual(store.globalProjectCandidate().candidate, candidate)
        XCTAssertEqual(candidate.membership, .assigned(
            kind: "local",
            id: "local-project",
            name: "自定义项目名"
        ))
    }

    func testResolvesRemoteGlobalProjectCandidateOnlyWithHostAndRemotePath() throws {
        let remoteFixture = Self.fixture.replacingOccurrences(
            of: #"{"type": "local", "projectId": "local-project"}"#,
            with: #"{"type": "remote", "projectId": "remote-project"}"#
        )
        try writeState(remoteFixture)
        let store = CodexProjectStore(globalStateURL: stateURL)

        XCTAssertEqual(
            store.globalProjectCandidate(),
            .selected(
                CodexGlobalProjectCandidate(
                    kind: "remote",
                    id: "remote-project",
                    name: "远程 Project",
                    rootPath: "C:/Users/alice/Project",
                    hostID: "remote-host"
                )
            )
        )
    }

    func testExplicitNullSelectedProjectMeansNoGlobalCandidate() throws {
        try writeState(
            #"{"selected-project": null, "local-projects": "malformed"}"#
        )
        let store = CodexProjectStore(globalStateURL: stateURL)

        XCTAssertEqual(store.globalProjectCandidate(), .none)
        XCTAssertNil(store.globalProjectCandidate().candidate)
    }

    func testMissingOrMalformedSelectedProjectIsUnknown() throws {
        let store = CodexProjectStore(globalStateURL: stateURL)

        for fixture in [
            #"{}"#,
            #"{"selected-project": "local"}"#,
            #"{"selected-project": {}}"#,
            #"{"selected-project": {"type": "local"}}"#,
            #"{"selected-project": {"type": "", "projectId": "local-project"}}"#,
            #"{"selected-project": {"type": "future", "projectId": "project-a"}}"#,
        ] {
            try writeState(fixture)
            XCTAssertEqual(store.globalProjectCandidate(), .unknown, fixture)
        }
    }

    func testDanglingSelectedProjectIDIsUnknown() throws {
        try writeState(
            """
            {
              "selected-project": {"type": "local", "projectId": "missing-project"},
              "local-projects": {
                "local-project": {
                  "id": "local-project",
                  "name": "Project",
                  "rootPaths": ["/tmp/project"]
                }
              }
            }
            """
        )
        let store = CodexProjectStore(globalStateURL: stateURL)

        XCTAssertEqual(store.globalProjectCandidate(), .unknown)
    }

    func testSelectedLocalProjectRequiresValidPrimaryRootPath() throws {
        let store = CodexProjectStore(globalStateURL: stateURL)

        for rootPaths in [
            "[]",
            #"["   "]"#,
            #"["relative/project"]"#,
            #"["/tmp/project-a", "/tmp/project-b"]"#,
        ] {
            try writeState(
                """
                {
                  "selected-project": {"type": "local", "projectId": "project-a"},
                  "local-projects": {
                    "project-a": {
                      "id": "project-a",
                      "name": "Project A",
                      "rootPaths": \(rootPaths)
                    }
                  }
                }
                """
            )
            XCTAssertEqual(store.globalProjectCandidate(), .unknown, rootPaths)
        }
    }

    func testMismatchedLocalProjectRecordIDIsUnknown() throws {
        try writeState(
            """
            {
              "selected-project": {"type": "local", "projectId": "project-a"},
              "local-projects": {
                "project-a": {
                  "id": "project-b",
                  "name": "Project A",
                  "rootPaths": ["/tmp/project-a"]
                }
              }
            }
            """
        )
        let store = CodexProjectStore(globalStateURL: stateURL)

        XCTAssertEqual(store.globalProjectCandidate(), .unknown)
    }

    func testSelectedRemoteProjectRequiresUniqueRecordHostAndPath() throws {
        let store = CodexProjectStore(globalStateURL: stateURL)

        for remoteProjects in [
            #"[{"id":"remote-project","remotePath":"C:/project"}]"#,
            #"[{"id":"remote-project","hostId":"remote-host"}]"#,
            #"[{"id":"remote-project","hostId":"   ","remotePath":"C:/project"}]"#,
            #"[{"id":"remote-project","hostId":"remote-host","remotePath":"   "}]"#,
            #"[{"id":"remote-project","hostId":"host-a","remotePath":"C:/a"},{"id":"remote-project","hostId":"host-b","remotePath":"C:/b"}]"#,
        ] {
            try writeState(
                """
                {
                  "selected-project": {"type": "remote", "projectId": "remote-project"},
                  "remote-projects": \(remoteProjects)
                }
                """
            )
            XCTAssertEqual(store.globalProjectCandidate(), .unknown, remoteProjects)
        }
    }

    func testGlobalProjectCandidateReflectsStateChangesWithoutRecreatingStore() throws {
        let store = CodexProjectStore(globalStateURL: stateURL)
        XCTAssertEqual(store.globalProjectCandidate().candidate?.id, "local-project")

        try writeState(#"{"selected-project": null}"#)
        XCTAssertEqual(store.globalProjectCandidate(), .none)
    }

    private func writeState(_ fixture: String) throws {
        try Data(fixture.utf8).write(to: stateURL, options: .atomic)
    }

    private static let fixture = """
    {
      "selected-project": {"type": "local", "projectId": "local-project"},
      "projectless-thread-ids": ["projectless-thread"],
      "thread-project-assignments": {
        "local-thread": {"projectKind": "local", "projectId": "local-project"},
        "remote-thread": {"projectKind": "remote", "projectId": "remote-project"},
        "projectless-thread": {"projectKind": "local", "projectId": "local-project"},
        "unnamed-thread": {"projectKind": "local", "projectId": "unnamed-project"},
        "missing-record-thread": {"projectKind": "local", "projectId": "missing-project"},
        "unsupported-thread": {"projectKind": "future", "projectId": "local-project"}
      },
      "local-projects": {
        "local-project": {
          "id": "local-project",
          "name": "  自定义项目名  ",
          "rootPaths": ["  /tmp/项目 A  "]
        },
        "unnamed-project": {"name": "   "}
      },
      "remote-projects": [
        {
          "id": "remote-project",
          "hostId": "  remote-host  ",
          "remotePath": "  C:/Users/alice/Project  ",
          "label": "远程 Project"
        }
      ]
    }
    """
}
