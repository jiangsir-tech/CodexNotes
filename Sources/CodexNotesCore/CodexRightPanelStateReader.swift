import CoreFoundation
import Foundation

public enum CodexRightPanelState: String, Codable, Equatable, Sendable {
    case unknown
    case closed
    case open
}

/// Parses Codex's persisted right-panel state for one exact thread.
///
/// The generic panel state is authoritative when it contains a strict Boolean.
/// If that private schema is unavailable, the browser-only state is a backward
/// compatible fallback. A valid atom store with neither exact-thread key means
/// the panel is still in its default closed state. Present but drifted values
/// remain unknown and never borrow another thread's state or rely on truthiness.
public enum CodexRightPanelStateParser {
    private static let atomStateKey = "electron-persisted-atom-state"
    private static let genericThreadKeyPrefix = "thread-tab-routes-v1:"
    private static let browserThreadKeyPrefix = "thread-browser-tabs-v1:"

    public static func state(
        for threadID: String,
        in data: Data
    ) -> CodexRightPanelState {
        guard !threadID.isEmpty,
              let root = try? JSONSerialization.jsonObject(with: data),
              let rootObject = root as? [String: Any],
              let atomState = rootObject[atomStateKey] as? [String: Any]
        else {
            return .unknown
        }

        let genericKey = genericPersistedKey(for: threadID)
        let browserKey = browserPersistedKey(for: threadID)
        let genericValue = atomState[genericKey]
        let browserValue = atomState[browserKey]

        if let genericThreadState = genericValue as? [String: Any],
           let topology = genericThreadState["topology"] as? [String: Any],
           let right = topology["right"] as? [String: Any],
           let state = strictBooleanState(right["open"]) {
            return state
        }

        if let browserThreadState = browserValue as? [String: Any],
           let state = strictBooleanState(
               browserThreadState["rightPanelOpen"]
           ) {
            return state
        }

        if genericValue == nil, browserValue == nil {
            return .closed
        }

        return .unknown
    }

    /// The legacy browser-only key, retained for source compatibility.
    public static func persistedKey(for threadID: String) -> String {
        browserPersistedKey(for: threadID)
    }

    /// Matches Codex's generic right-panel persisted key.
    public static func genericPersistedKey(for threadID: String) -> String {
        genericThreadKeyPrefix + encodeURIComponent(threadID)
    }

    /// Matches Codex's browser-only right-panel persisted key.
    public static func browserPersistedKey(for threadID: String) -> String {
        browserThreadKeyPrefix + encodeURIComponent(threadID)
    }

    private static func strictBooleanState(
        _ value: Any?
    ) -> CodexRightPanelState? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID()
        else {
            return nil
        }

        return number.boolValue ? .open : .closed
    }

    private static func encodeURIComponent(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)

        for byte in value.utf8 {
            if isEncodeURIComponentUnescaped(byte) {
                result.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                result.append(String(format: "%%%02X", byte))
            }
        }
        return result
    }

    private static func isEncodeURIComponentUnescaped(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30 ... 0x39, // 0-9
             0x41 ... 0x5A, // A-Z
             0x61 ... 0x7A, // a-z
             0x21, // !
             0x27, // '
             0x28, // (
             0x29, // )
             0x2A, // *
             0x2D, // -
             0x2E, // .
             0x5F, // _
             0x7E: // ~
            return true
        default:
            return false
        }
    }
}

/// Reads a fresh snapshot on each call so atomic replacements of Codex's state
/// file are observed without retaining stale panel state.
public actor CodexRightPanelStateReader {
    private let globalStateURL: URL

    public init(
        globalStateURL: URL = CodexEnvironment.defaultStateDatabase
            .deletingLastPathComponent()
            .appendingPathComponent(".codex-global-state.json")
    ) {
        self.globalStateURL = globalStateURL
    }

    public func state(for threadID: String) -> CodexRightPanelState {
        guard let data = try? Data(
            contentsOf: globalStateURL,
            options: .mappedIfSafe
        ) else {
            return .unknown
        }
        return CodexRightPanelStateParser.state(for: threadID, in: data)
    }
}
