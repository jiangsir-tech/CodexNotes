import AppKit
import CodexNotesCore
import SwiftUI

enum GlobalHotKeyRecorderKeyAction: Equatable {
    case ignore
    case cancel
    case clear
    case record(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)
}

enum GlobalHotKeyRecorderKeyPolicy {
    static func action(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> GlobalHotKeyRecorderKeyAction {
        guard !isRepeat else { return .ignore }
        switch keyCode {
        case 53:
            return .cancel
        case 51, 117:
            return .clear
        default:
            return .record(
                keyCode: keyCode,
                modifiers: modifierFlags.intersection([
                    .command,
                    .control,
                    .option,
                    .shift,
                ])
            )
        }
    }
}

struct GlobalHotKeyRecorderView: View {
    let shortcutDisplayName: String?
    let isRecording: Bool
    let isDefault: Bool
    let errorMessage: String?
    let palette: NoteThemePalette
    let beginRecording: () -> Void
    let cancelRecording: () -> Void
    let recordShortcut: (_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> Void
    let clearShortcut: () -> Void
    let restoreDefault: () -> Void
    @AccessibilityFocusState private var recorderHasAccessibilityFocus: Bool

    private var displayedShortcut: String {
        let normalized = shortcutDisplayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.flatMap { $0.isEmpty ? nil : $0 }
            ?? L10n.text(.globalHotKeyNotSet)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(.settingsGlobalHotKeyTitle))
                        .font(.subheadline.weight(.medium))
                    Text(L10n.text(.settingsGlobalHotKeyDescription))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityHidden(true)

                Spacer(minLength: 20)

                HStack(spacing: 6) {
                    Button {
                        if isRecording {
                            cancelRecording()
                        } else {
                            beginRecording()
                        }
                    } label: {
                        Text(
                            isRecording
                                ? L10n.text(.settingsGlobalHotKeyRecording)
                                : displayedShortcut
                        )
                        .monospaced()
                        .lineLimit(1)
                        .frame(minWidth: 112)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(
                        Text(L10n.text(.settingsGlobalHotKeyAccessibilityLabel))
                    )
                    .accessibilityValue(
                        Text(
                            isRecording
                                ? L10n.text(.settingsGlobalHotKeyRecording)
                                : displayedShortcut
                        )
                    )
                    .accessibilityHint(
                        Text(L10n.text(.settingsGlobalHotKeyAccessibilityHint))
                    )
                    .accessibilityFocused($recorderHasAccessibilityFocus)

                    if shortcutDisplayName != nil && !isRecording {
                        Button(action: clearShortcut) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(palette.secondaryText.color)
                                .accessibilityHidden(true)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .help(L10n.text(.settingsGlobalHotKeyClear))
                        .accessibilityLabel(
                            Text(L10n.text(.settingsGlobalHotKeyClear))
                        )
                    }
                }
            }

            if !isDefault && !isRecording {
                HStack {
                    Spacer()
                    Button(L10n.text(.settingsGlobalHotKeyRestoreDefault)) {
                        restoreDefault()
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.warning.color)
                        .accessibilityHidden(true)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(palette.warning.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            GlobalHotKeyCaptureView(
                isActive: isRecording,
                recordShortcut: recordShortcut,
                cancelRecording: cancelRecording,
                clearShortcut: clearShortcut
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .onDisappear {
            if isRecording {
                cancelRecording()
            }
        }
        .onChange(of: isRecording) { _, isRecording in
            DispatchQueue.main.async {
                recorderHasAccessibilityFocus = true
            }
            if isRecording {
                announceForAccessibility(
                    L10n.text(.settingsGlobalHotKeyRecording)
                )
            }
        }
        .onChange(of: errorMessage) { _, errorMessage in
            guard let errorMessage, !errorMessage.isEmpty else { return }
            announceForAccessibility(errorMessage)
        }
    }

    private func announceForAccessibility(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

private struct GlobalHotKeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let recordShortcut: (_ keyCode: UInt16, _ modifiers: NSEvent.ModifierFlags) -> Void
    let cancelRecording: () -> Void
    let clearShortcut: () -> Void

    func makeNSView(context: Context) -> GlobalHotKeyCaptureNSView {
        let view = GlobalHotKeyCaptureNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: GlobalHotKeyCaptureNSView, context: Context) {
        update(nsView)
        guard isActive else {
            if nsView.window?.firstResponder === nsView {
                _ = nsView.window?.makeFirstResponder(nil)
            }
            return
        }

        DispatchQueue.main.async { [weak nsView] in
            guard let nsView, nsView.isActive,
                  nsView.window?.firstResponder !== nsView else { return }
            _ = nsView.window?.makeFirstResponder(nsView)
        }
    }

    static func dismantleNSView(
        _ nsView: GlobalHotKeyCaptureNSView,
        coordinator: Void
    ) {
        guard nsView.isActive else { return }
        nsView.isActive = false
        let cancelRecording = nsView.cancelRecording
        DispatchQueue.main.async {
            cancelRecording()
        }
    }

    private func update(_ view: GlobalHotKeyCaptureNSView) {
        view.recordShortcut = recordShortcut
        view.cancelRecording = cancelRecording
        view.clearShortcut = clearShortcut
        view.isActive = isActive
    }
}

final class GlobalHotKeyCaptureNSView: NSView {
    var isActive = false
    var recordShortcut: (UInt16, NSEvent.ModifierFlags) -> Void = { _, _ in }
    var cancelRecording: () -> Void = {}
    var clearShortcut: () -> Void = {}
    private var windowResignObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isActive else { return }
        handleKeyDown(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isActive, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        handleKeyDown(event)
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowResignObserver()
    }

    private func handleKeyDown(_ event: NSEvent) {
        switch GlobalHotKeyRecorderKeyPolicy.action(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            isRepeat: event.isARepeat
        ) {
        case .ignore:
            return
        case .cancel:
            cancelRecording()
        case .clear:
            clearShortcut()
        case let .record(keyCode, modifiers):
            recordShortcut(keyCode, modifiers)
        }
    }

    private func installWindowResignObserver() {
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
            self.windowResignObserver = nil
        }
        guard let window else { return }
        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                self.cancelRecording()
            }
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign && isActive {
            cancelRecording()
        }
        return didResign
    }

    deinit {
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
        }
    }
}
