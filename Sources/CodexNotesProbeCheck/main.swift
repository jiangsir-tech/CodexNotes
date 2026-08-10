import CodexNotesCore
import Foundation

@main
enum CodexNotesProbeCheck {
    static func main() async {
        let monitor = CodexLogMonitor()
        do {
            guard let selection = try await monitor.bootstrap() else {
                fputs("ERROR: \(L10n.text(.probeCheckErrorNoTask))\n", stderr)
                Foundation.exit(2)
            }

            let metadata = selection.threadID.flatMap { CodexThreadStore().metadata(for: $0) }
            let payload: [String: Any] = [
                "status": "detected",
                "kind": selection.kind.rawValue,
                "stableKey": selection.stableKey,
                "threadID": selection.threadID ?? NSNull(),
                "hostID": selection.hostID ?? NSNull(),
                "name": metadata?.name ?? NSNull(),
                "cwd": metadata?.cwd ?? NSNull(),
                "route": selection.route,
                "timestamp": selection.timestamp
            ]

            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}
