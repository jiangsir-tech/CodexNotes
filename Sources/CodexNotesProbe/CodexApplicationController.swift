import AppKit
import CodexNotesCore

enum CodexApplicationActivationPlan: Equatable {
    case activateRunning
    case launchInstalled
    case unavailable
}

enum CodexApplicationActivationPolicy {
    static let timeoutInterval: TimeInterval = 10

    static func plan(
        hasRunningApplication: Bool,
        hasInstalledApplication: Bool
    ) -> CodexApplicationActivationPlan {
        if hasRunningApplication {
            return .activateRunning
        }
        if hasInstalledApplication {
            return .launchInstalled
        }
        return .unavailable
    }

    static func shouldUseCooperativeActivation(
        isCompanionApplicationActive: Bool
    ) -> Bool {
        isCompanionApplicationActive
    }
}

@MainActor
enum CodexApplicationController {
    typealias Completion = @MainActor @Sendable (Bool) -> Void

    static func activateOrLaunch(
        completion: @escaping Completion
    ) {
        let bundleIdentifier = CompanionVisibilityPolicy.codexBundleIdentifier
        let runningApplication = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first(where: { !$0.isTerminated })
        let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        )
        let plan = CodexApplicationActivationPolicy.plan(
            hasRunningApplication: runningApplication != nil,
            hasInstalledApplication: applicationURL != nil
        )

        switch plan {
        case .activateRunning:
            guard let runningApplication else {
                completion(false)
                return
            }
            _ = runningApplication.unhide()
            let accepted: Bool
            if CodexApplicationActivationPolicy.shouldUseCooperativeActivation(
                isCompanionApplicationActive: NSApp.isActive
            ) {
                NSApp.yieldActivation(to: runningApplication)
                accepted = runningApplication.activate(
                    from: .current,
                    options: [.activateAllWindows]
                )
            } else {
                accepted = runningApplication.activate(
                    options: [.activateAllWindows]
                )
            }
            if accepted {
                completion(true)
            } else {
                launchInstalledApplication(
                    at: applicationURL,
                    completion: completion
                )
            }
        case .launchInstalled:
            launchInstalledApplication(
                at: applicationURL,
                completion: completion
            )
        case .unavailable:
            completion(false)
        }
    }

    static func launchConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.addsToRecentItems = false
        return configuration
    }

    private static func launchInstalledApplication(
        at applicationURL: URL?,
        completion: @escaping Completion
    ) {
        guard let applicationURL else {
            completion(false)
            return
        }
        let bundleIdentifier = CompanionVisibilityPolicy.codexBundleIdentifier
        if NSApp.isActive {
            NSApp.yieldActivation(
                toApplicationWithBundleIdentifier: bundleIdentifier
            )
        }
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: launchConfiguration()
        ) { runningApplication, error in
            let succeeded = runningApplication != nil && error == nil
            Task { @MainActor in
                completion(succeeded)
            }
        }
    }
}
