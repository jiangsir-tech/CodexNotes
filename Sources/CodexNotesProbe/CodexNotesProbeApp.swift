import AppKit
import CodexNotesCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: ProbeViewModel?
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
                languagePreference: languagePreference
            )
                .environment(\.locale, resolvedLanguage.locale)
                .onAppear {
                    appDelegate.model = model
                }
        }
        .defaultSize(width: 400, height: 660)
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
            SettingsView()
                .environment(\.locale, resolvedLanguage.locale)
        }
    }
}
