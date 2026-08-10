import Foundation

public enum CodexRouteKind: String, Codable, Sendable {
    case local
    case work
    case newTask
    case unknown
}

public struct CodexSelection: Equatable, Sendable {
    public let timestamp: String
    public let conversationID: String
    public let route: String
    public let windowID: String
    public let kind: CodexRouteKind
    public let threadID: String?
    public let hostID: String?
    public let stableKey: String

    public init(
        timestamp: String,
        conversationID: String,
        route: String,
        windowID: String,
        kind: CodexRouteKind,
        threadID: String?,
        hostID: String?,
        stableKey: String
    ) {
        self.timestamp = timestamp
        self.conversationID = conversationID
        self.route = route
        self.windowID = windowID
        self.kind = kind
        self.threadID = threadID
        self.hostID = hostID
        self.stableKey = stableKey
    }
}

public enum CodexSelectionParser {
    private static let marker = "[electron-message-handler] IAB_LIFECYCLE received browser sidebar owner sync"

    public static func parse(line: String) -> CodexSelection? {
        guard line.contains(marker),
              let conversationID = token(after: "conversationId=", in: line),
              let route = token(after: "ownerRoutePath=", in: line),
              let windowID = token(after: "windowId=", in: line),
              let timestamp = line.split(separator: " ", maxSplits: 1).first.map(String.init)
        else {
            return nil
        }

        let normalized = normalize(
            route: route,
            conversationID: conversationID,
            windowID: windowID
        )

        return CodexSelection(
            timestamp: timestamp,
            conversationID: conversationID,
            route: route,
            windowID: windowID,
            kind: normalized.kind,
            threadID: normalized.threadID,
            hostID: normalized.hostID,
            stableKey: normalized.stableKey
        )
    }

    private static func token(after prefix: String, in line: String) -> String? {
        guard let range = line.range(of: prefix) else { return nil }
        let remainder = line[range.upperBound...]
        guard let token = remainder.split(whereSeparator: { $0.isWhitespace }).first else {
            return nil
        }
        return String(token)
    }

    private static func normalize(
        route: String,
        conversationID: String,
        windowID: String
    ) -> (kind: CodexRouteKind, threadID: String?, hostID: String?, stableKey: String) {
        if route == "/" {
            return (
                .newTask,
                nil,
                nil,
                "new:\(windowID):\(conversationID)"
            )
        }

        guard let components = URLComponents(string: "codex-probe://host\(route)") else {
            return (.unknown, nil, nil, "unknown:\(windowID):\(route)")
        }

        let parts = components.percentEncodedPath
            .split(separator: "/")
            .map { String($0).removingPercentEncoding ?? String($0) }

        if parts.count >= 2, parts[0] == "local" {
            let threadID = parts[1]
            let hostID = components.queryItems?
                .first(where: { $0.name == "hostId" })?
                .value

            if let hostID, !hostID.isEmpty {
                return (.local, threadID, hostID, "\(hostID):\(threadID)")
            }
            return (.local, threadID, nil, "local:\(threadID)")
        }

        if parts.count >= 3, parts[0] == "work", parts[1] == "conversation" {
            let workID = parts[2]
            return (.work, workID, nil, "work:\(workID)")
        }

        return (.unknown, nil, nil, "unknown:\(windowID):\(route)")
    }
}
