import AppKit
import CodexNotesCore
import XCTest
@testable import CodexNotesProbe

@MainActor
final class GlobalHotKeyRecorderViewTests: XCTestCase {
    func testRecorderHasConciseChineseAndEnglishLabels() {
        XCTAssertEqual(
            L10n.text(
                .settingsGlobalHotKeyTitle,
                preference: .simplifiedChinese
            ),
            "显示/隐藏 CodexNotes"
        )
        XCTAssertEqual(
            L10n.text(.settingsGlobalHotKeyTitle, preference: .english),
            "Show/Hide CodexNotes"
        )
        XCTAssertEqual(
            L10n.text(.globalHotKeyNotSet, preference: .simplifiedChinese),
            "未设置"
        )
        XCTAssertEqual(
            L10n.text(.globalHotKeyNotSet, preference: .english),
            "Not Set"
        )
    }

    func testEscapeCancelsInsteadOfBecomingARecordedShortcut() {
        XCTAssertEqual(
            GlobalHotKeyRecorderKeyPolicy.action(
                keyCode: 53,
                modifierFlags: [.command, .shift],
                isRepeat: false
            ),
            .cancel
        )
    }

    func testBackspaceAndForwardDeleteClearTheShortcut() {
        for keyCode: UInt16 in [51, 117] {
            XCTAssertEqual(
                GlobalHotKeyRecorderKeyPolicy.action(
                    keyCode: keyCode,
                    modifierFlags: [],
                    isRepeat: false
                ),
                .clear
            )
        }
    }

    func testRepeatedKeyDownIsIgnored() {
        XCTAssertEqual(
            GlobalHotKeyRecorderKeyPolicy.action(
                keyCode: 49,
                modifierFlags: [.control, .shift],
                isRepeat: true
            ),
            .ignore
        )
    }

    func testRecordedShortcutKeepsOnlySupportedModifierFlags() {
        XCTAssertEqual(
            GlobalHotKeyRecorderKeyPolicy.action(
                keyCode: 49,
                modifierFlags: [.control, .shift, .capsLock, .numericPad],
                isRepeat: false
            ),
            .record(keyCode: 49, modifiers: [.control, .shift])
        )
    }

    func testCommandKeyEquivalentIsConsumedBeforeTheApplicationMenu() throws {
        let captureView = GlobalHotKeyCaptureNSView()
        captureView.isActive = true
        var recordedAction: GlobalHotKeyRecorderKeyAction?
        captureView.recordShortcut = { keyCode, modifiers in
            recordedAction = .record(keyCode: keyCode, modifiers: modifiers)
        }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "q",
                charactersIgnoringModifiers: "q",
                isARepeat: false,
                keyCode: 12
            )
        )

        XCTAssertTrue(captureView.performKeyEquivalent(with: event))
        XCTAssertEqual(
            recordedAction,
            .record(keyCode: 12, modifiers: .command)
        )
    }

    func testWindowResigningKeyCancelsAnActiveRecording() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        defer { window.orderOut(nil) }
        let captureView = GlobalHotKeyCaptureNSView()
        window.contentView = captureView
        captureView.isActive = true
        var cancellationCount = 0
        captureView.cancelRecording = { cancellationCount += 1 }

        NotificationCenter.default.post(
            name: NSWindow.didResignKeyNotification,
            object: window
        )

        XCTAssertEqual(cancellationCount, 1)
    }

    func testSettingsSourceRestoresRecordingOnEveryExitPath() throws {
        let recorderSource = try source(
            "Sources/CodexNotesProbe/GlobalHotKeyRecorderView.swift"
        )
        XCTAssertTrue(recorderSource.contains(".onDisappear"))
        XCTAssertTrue(recorderSource.contains("cancelRecording()"))
        XCTAssertTrue(recorderSource.contains("override func resignFirstResponder()"))

        let settingsSource = try source(
            "Sources/CodexNotesProbe/SettingsView.swift"
        )
        XCTAssertTrue(settingsSource.contains("globalHotKeyController.beginRecording()"))
        XCTAssertTrue(settingsSource.contains("globalHotKeyController.cancelRecording()"))
        XCTAssertTrue(settingsSource.contains("commitRecordedShortcut(shortcut)"))
        XCTAssertTrue(recorderSource.contains(".accessibilityFocused("))
        XCTAssertTrue(recorderSource.contains(".announcementRequested"))
        XCTAssertTrue(recorderSource.contains(".frame(width: 28, height: 28)"))
    }

    private func source(_ relativePath: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        let repositoryRoot = testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
