import AppKit
import CodexNotesCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ProbeViewModel?
    let globalHotKeyController = GlobalHotKeyController()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let application = notification.object as? NSApplication else { return }
        if !CodexNotesApplicationPresentation.isSatisfied(
            by: application.activationPolicy()
        ) {
            _ = application.setActivationPolicy(
                CodexNotesApplicationPresentation.activationPolicy
            )
        }
        if statusItemController == nil {
            statusItemController = StatusItemController()
        }
        globalHotKeyController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKeyController.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        return model.flushImmediately() ? .terminateNow : .terminateCancel
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            NotificationCenter.default.post(
                name: MainWindowCommandNotification.show,
                object: nil
            )
        }
        return true
    }
}

@main
struct CodexNotesProbeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ProbeViewModel()
    @StateObject private var updateCoordinator = UpdateCheckCoordinator()
    @AppStorage(AppLanguagePreference.key)
    private var storedLanguagePreference = AppLanguagePreference.defaultValue.rawValue

    private var languagePreference: AppLanguagePreference {
        AppLanguagePreference.normalized(storedLanguagePreference)
    }

    private var resolvedLanguage: ResolvedAppLanguage {
        AppLocalization.resolve(languagePreference)
    }

    private var localization: AppLocalization {
        AppLocalization(preference: languagePreference)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                model: model,
                updateCoordinator: updateCoordinator,
                globalHotKeyController: appDelegate.globalHotKeyController,
                languagePreference: languagePreference
            )
                .environment(\.locale, resolvedLanguage.locale)
                .onAppear {
                    appDelegate.model = model
                    updateCoordinator.start()
                }
        }
        .defaultSize(
            width: MainWindowInitialPlacementPolicy.swiftUIBootstrapSize.width,
            height: MainWindowInitialPlacementPolicy.swiftUIBootstrapSize.height
        )
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .saveItem) {
                Button(localization.text(.appCommandSaveNow)) {
                    model.flushImmediately()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }

        Settings {
            SettingsView(
                updateCoordinator: updateCoordinator,
                globalHotKeyController: appDelegate.globalHotKeyController
            )
                .environment(\.locale, resolvedLanguage.locale)
        }
    }
}
