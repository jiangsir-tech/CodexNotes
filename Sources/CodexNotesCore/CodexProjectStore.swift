import Foundation

public enum CodexProjectMembership: Equatable, Sendable {
    case none
    case assigned(kind: String, id: String, name: String?)
    case unknown

    public var projectName: String? {
        guard case let .assigned(_, _, name) = self else { return nil }
        return name
    }

    public var isAssigned: Bool {
        guard case .assigned = self else { return false }
        return true
    }
}

/// A project resolved from Codex's process-wide `selected-project` value.
///
/// This is only a persisted candidate. It does not prove that the currently
/// visible new-task route was opened for this project because Codex stores the
/// route binding separately and does not give the two values a shared revision.
public struct CodexGlobalProjectCandidate: Equatable, Sendable {
    public let kind: String
    public let id: String
    public let name: String?
    public let rootPath: String
    public let hostID: String?

    public init(
        kind: String,
        id: String,
        name: String?,
        rootPath: String,
        hostID: String?
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.hostID = hostID
    }

    public var membership: CodexProjectMembership {
        .assigned(kind: kind, id: id, name: name)
    }
}

public enum CodexGlobalProjectCandidateState: Equatable, Sendable {
    /// Codex explicitly persisted `selected-project: null`.
    ///
    /// This describes only the persisted global candidate and does not prove
    /// that the currently visible new-task route is projectless.
    case none
    /// Codex persisted enough data to resolve a usable global candidate.
    ///
    /// Callers must not treat this as proof of the visible new task's project.
    case selected(CodexGlobalProjectCandidate)
    /// The global state cannot provide a usable project candidate.
    case unknown

    public var candidate: CodexGlobalProjectCandidate? {
        guard case let .selected(candidate) = self else { return nil }
        return candidate
    }
}

public protocol CodexGlobalProjectCandidateProviding: Sendable {
    /// Reads the persisted, process-wide project candidate.
    ///
    /// The result is deliberately route-agnostic. A caller needs separate,
    /// authoritative route data or explicit user confirmation before binding a
    /// new task to a returned candidate.
    func globalProjectCandidate() -> CodexGlobalProjectCandidateState
}

public final class CodexProjectStore: CodexGlobalProjectCandidateProviding, @unchecked Sendable {
    private struct GlobalState: Decodable {
        let projectlessThreadIDs: [String]?
        let threadProjectAssignments: [String: Assignment]?
        let localProjects: [String: LocalProject]?
        let remoteProjects: [RemoteProject]?

        enum CodingKeys: String, CodingKey {
            case projectlessThreadIDs = "projectless-thread-ids"
            case threadProjectAssignments = "thread-project-assignments"
            case localProjects = "local-projects"
            case remoteProjects = "remote-projects"
        }
    }

    private struct Assignment: Decodable {
        let projectKind: String
        let projectID: String

        enum CodingKeys: String, CodingKey {
            case projectKind
            case projectID = "projectId"
        }
    }

    private struct LocalProject: Decodable {
        let name: String?
    }

    private struct RemoteProject: Decodable {
        let id: String
        let label: String?
    }

    private struct SelectedProjectReference: Decodable {
        let kind: String
        let projectID: String

        enum CodingKeys: String, CodingKey {
            case kind = "type"
            case projectID = "projectId"
        }
    }

    private enum SelectedProjectField {
        case missing
        case none
        case value(SelectedProjectReference)
        case malformed
    }

    private struct SelectedLocalProject: Decodable {
        let id: String?
        let name: String?
        let rootPaths: [String]?
    }

    private struct SelectedRemoteProject: Decodable {
        let id: String
        let hostID: String?
        let remotePath: String?
        let label: String?

        enum CodingKeys: String, CodingKey {
            case id
            case hostID = "hostId"
            case remotePath
            case label
        }
    }

    private struct SelectedProjectState: Decodable {
        let selection: SelectedProjectField
        let localProjects: [String: SelectedLocalProject]?
        let remoteProjects: [SelectedRemoteProject]?

        enum CodingKeys: String, CodingKey {
            case selectedProject = "selected-project"
            case localProjects = "local-projects"
            case remoteProjects = "remote-projects"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if !container.contains(.selectedProject) {
                selection = .missing
            } else if try container.decodeNil(forKey: .selectedProject) {
                selection = .none
            } else if let reference = try? container.decode(
                SelectedProjectReference.self,
                forKey: .selectedProject
            ) {
                selection = .value(reference)
            } else {
                selection = .malformed
            }

            localProjects = try? container.decodeIfPresent(
                [String: SelectedLocalProject].self,
                forKey: .localProjects
            )
            remoteProjects = try? container.decodeIfPresent(
                [SelectedRemoteProject].self,
                forKey: .remoteProjects
            )
        }
    }

    private let globalStateURL: URL

    public init(
        globalStateURL: URL = CodexEnvironment.defaultStateDatabase
            .deletingLastPathComponent()
            .appendingPathComponent(".codex-global-state.json")
    ) {
        self.globalStateURL = globalStateURL
    }

    public func membership(for threadID: String) -> CodexProjectMembership {
        guard let data = try? Data(contentsOf: globalStateURL),
              let state = try? JSONDecoder().decode(GlobalState.self, from: data)
        else { return .unknown }

        if state.projectlessThreadIDs?.contains(threadID) == true {
            return .none
        }

        guard let assignment = state.threadProjectAssignments?[threadID] else {
            if state.projectlessThreadIDs != nil,
               state.threadProjectAssignments != nil {
                return .none
            }
            return .unknown
        }

        let kind = assignment.projectKind.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = assignment.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kind.isEmpty, !projectID.isEmpty else { return .unknown }

        let rawName: String?
        switch kind {
        case "local":
            guard let project = state.localProjects?[projectID] else { return .unknown }
            rawName = project.name
        case "remote":
            guard let project = state.remoteProjects?.first(where: { $0.id == projectID }) else {
                return .unknown
            }
            rawName = project.label
        default:
            return .unknown
        }

        let normalizedName = rawName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        return .assigned(kind: kind, id: projectID, name: normalizedName)
    }

    public func projectName(for threadID: String) -> String? {
        membership(for: threadID).projectName
    }

    public func globalProjectCandidate() -> CodexGlobalProjectCandidateState {
        guard let data = try? Data(contentsOf: globalStateURL),
              let state = try? JSONDecoder().decode(SelectedProjectState.self, from: data)
        else { return .unknown }

        let reference: SelectedProjectReference
        switch state.selection {
        case .none:
            return .none
        case .missing, .malformed:
            return .unknown
        case let .value(value):
            reference = value
        }

        let kind = reference.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = reference.projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kind.isEmpty, !projectID.isEmpty else { return .unknown }

        switch kind {
        case "local":
            guard let project = state.localProjects?[projectID],
                  let rootPath = normalizedLocalRootPath(project.rootPaths),
                  normalizedRecordID(project.id, fallback: projectID) == projectID
            else { return .unknown }

            return .selected(
                CodexGlobalProjectCandidate(
                    kind: kind,
                    id: projectID,
                    name: normalizedName(project.name),
                    rootPath: rootPath,
                    hostID: nil
                )
            )

        case "remote":
            let matches = state.remoteProjects?.filter {
                $0.id.trimmingCharacters(in: .whitespacesAndNewlines) == projectID
            } ?? []
            guard matches.count == 1,
                  let project = matches.first,
                  let hostID = normalizedName(project.hostID),
                  let remotePath = normalizedName(project.remotePath)
            else { return .unknown }

            return .selected(
                CodexGlobalProjectCandidate(
                    kind: kind,
                    id: projectID,
                    name: normalizedName(project.label),
                    rootPath: remotePath,
                    hostID: hostID
                )
            )

        default:
            return .unknown
        }
    }

    private func normalizedLocalRootPath(_ rootPaths: [String]?) -> String? {
        let normalizedPaths = rootPaths?.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let normalizedPaths,
              normalizedPaths.count == 1,
              let rootPath = normalizedPaths.first,
              !rootPath.isEmpty,
              (rootPath as NSString).isAbsolutePath
        else { return nil }

        return rootPath
    }

    private func normalizedRecordID(_ id: String?, fallback: String) -> String {
        guard let id else { return fallback }
        return id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedName(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
