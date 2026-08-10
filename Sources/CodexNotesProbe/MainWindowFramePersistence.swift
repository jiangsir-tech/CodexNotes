import AppKit

enum MainWindowFramePersistencePlan: Equatable {
    case restoreStableFrame
    case migrateLegacyFrame
    case placeInitially
}

enum MainWindowFramePersistence {
    static let autosaveName = "CodexNotes.MainWindow"
    static let autosaveDefaultsKey = "NSWindow Frame \(autosaveName)"

    private static let legacyFrameKeyPrefix = "NSWindow Frame SwiftUI.WindowGroup<"
    private static let legacyContentViewMarker = "CodexNotesProbe.ContentView"
    private static let preferredLegacyMarker =
        "SwiftUI.ModifiedContent<CodexNotesProbe.ContentView"

    static func plan(
        stableFrameRestored: Bool,
        currentLegacyFrameAvailable: Bool
    ) -> MainWindowFramePersistencePlan {
        if stableFrameRestored {
            return .restoreStableFrame
        }
        if currentLegacyFrameAvailable {
            return .migrateLegacyFrame
        }
        return .placeInitially
    }

    static func currentLegacyFrameIsAvailable(
        autosaveName currentAutosaveName: String,
        defaults: UserDefaults
    ) -> Bool {
        legacyFrame(
            autosaveName: currentAutosaveName,
            defaults: defaults
        ) != nil
    }

    static func legacyFrame(
        autosaveName currentAutosaveName: String,
        defaults: UserDefaults
    ) -> String? {
        guard currentAutosaveName != autosaveName else {
            return nil
        }
        if !currentAutosaveName.isEmpty,
           let currentFrame = savedFrame(
               forKey: defaultsKey(for: currentAutosaveName),
               in: defaults
           ) {
            return currentFrame
        }
        return preferredLegacyFrame(in: defaults)
    }

    @MainActor
    static func configure(
        window: NSWindow,
        defaults: UserDefaults = .standard,
        initialPlacement: () -> Void
    ) {
        let currentAutosaveName = window.frameAutosaveName
        let stableFrame = savedFrame(
            forKey: autosaveDefaultsKey,
            in: defaults
        )
        let legacyFrame = legacyFrame(
            autosaveName: currentAutosaveName,
            defaults: defaults
        )
        let persistencePlan = plan(
            stableFrameRestored: stableFrame != nil,
            currentLegacyFrameAvailable: legacyFrame != nil
        )
        // SwiftUI assigns WindowGroup a generated autosave name. Capture that
        // name above for one-time migration, then disable its writer so the
        // stable CodexNotes key remains the single source of truth.
        _ = window.setFrameAutosaveName("")
        switch persistencePlan {
        case .restoreStableFrame:
            if let stableFrame {
                window.setFrame(from: stableFrame)
            }
        case .migrateLegacyFrame:
            if let legacyFrame {
                window.setFrame(from: legacyFrame)
            }
        case .placeInitially:
            initialPlacement()
        }
        persist(window: window, defaults: defaults)
    }

    @MainActor
    static func persistIfVisible(
        window: NSWindow,
        defaults: UserDefaults = .standard
    ) {
        // Ordering a hidden AppKit window on screen can emit move/resize
        // notifications before `isVisible` flips to true. Those are system
        // placement events, not user changes, and must not replace the saved
        // frame.
        guard window.isVisible else { return }
        persist(window: window, defaults: defaults)
    }

    @MainActor
    static func showPreservingFrame(
        window: NSWindow,
        defaults: UserDefaults = .standard,
        present: @MainActor (NSWindow) -> Void = { $0.orderFrontRegardless() }
    ) {
        let fallbackFrame = window.frame
        let stableFrame = savedFrame(
            forKey: autosaveDefaultsKey,
            in: defaults
        )

        // Keep SwiftUI's generated autosave writer disabled even if the scene
        // lifecycle assigned it again while the window was hidden.
        _ = window.setFrameAutosaveName("")
        present(window)

        // `orderFrontRegardless()` may center an ordered-out window before it
        // becomes visible. Reapply the trusted frame synchronously after the
        // presentation call, when AppKit has finished that placement pass.
        if let stableFrame {
            window.setFrame(from: stableFrame)
        } else {
            window.setFrame(fallbackFrame, display: false)
        }
        _ = window.setFrameAutosaveName("")
        persist(window: window, defaults: defaults)
    }

    @MainActor
    static func persist(
        window: NSWindow,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(window.frameDescriptor, forKey: autosaveDefaultsKey)
    }

    static func preferredLegacyFrame(in defaults: UserDefaults) -> String? {
        defaults.dictionaryRepresentation()
            .compactMap { key, value -> (key: String, frame: String)? in
                guard key.hasPrefix(legacyFrameKeyPrefix),
                      key.contains(legacyContentViewMarker),
                      let frame = value as? String,
                      isValidFrame(frame)
                else {
                    return nil
                }
                return (key, frame)
            }
            .sorted { lhs, rhs in
                let lhsIsPreferred = lhs.key.contains(preferredLegacyMarker)
                let rhsIsPreferred = rhs.key.contains(preferredLegacyMarker)
                if lhsIsPreferred != rhsIsPreferred {
                    return lhsIsPreferred
                }
                return lhs.key < rhs.key
            }
            .first?
            .frame
    }

    private static func defaultsKey(for autosaveName: String) -> String {
        "NSWindow Frame \(autosaveName)"
    }

    private static func savedFrame(
        forKey key: String,
        in defaults: UserDefaults
    ) -> String? {
        guard let frame = defaults.string(forKey: key),
              isValidFrame(frame) else {
            return nil
        }
        return frame
    }

    private static func isValidFrame(_ frame: String) -> Bool {
        let components = frame.split(whereSeparator: { $0.isWhitespace })
        guard components.count == 8 else {
            return false
        }
        let values = components.compactMap { Double($0) }
        guard values.count == components.count,
              values.allSatisfy(\.isFinite) else {
            return false
        }
        return values[2] > 0 && values[3] > 0 &&
            values[6] > 0 && values[7] > 0
    }
}
