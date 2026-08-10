import AppKit
import SwiftUI
@testable import CodexNotesCore
@testable import CodexNotesProbe
import XCTest

@MainActor
final class ShortcutReferencePanelTests: XCTestCase {
    func testStandardReferenceContainsExactlyTheFiveApprovedShortcuts() {
        let presentation = ShortcutReferencePresentation.standard

        XCTAssertEqual(presentation.title, L10n.text(.shortcutsTitle))
        XCTAssertEqual(
            Set(Mirror(reflecting: presentation).children.compactMap(\.label)),
            ["title", "sections"]
        )
        XCTAssertEqual(
            presentation.sections.map(\.title),
            [
                L10n.text(.shortcutsSectionTodos),
                L10n.text(.shortcutsSectionNotes),
                L10n.text(.shortcutsSectionFormatting),
            ]
        )
        XCTAssertEqual(
            presentation.items,
            [
                ShortcutReferenceItem(
                    id: .cycleTodo,
                    title: L10n.text(.shortcutsItemToggleCurrentLineTodo),
                    shortcut: "⌘↩"
                ),
                ShortcutReferenceItem(
                    id: .taskNote,
                    title: L10n.text(.shortcutsItemTaskNote),
                    shortcut: "⌘1"
                ),
                ShortcutReferenceItem(
                    id: .projectNote,
                    title: L10n.text(.shortcutsItemProjectNote),
                    shortcut: "⌘2"
                ),
                ShortcutReferenceItem(
                    id: .bold,
                    title: L10n.text(.shortcutsItemBoldSelection),
                    shortcut: "⌘B"
                ),
                ShortcutReferenceItem(
                    id: .highlight,
                    title: L10n.text(.shortcutsItemHighlightSelection),
                    shortcut: "⌘⇧H"
                ),
            ]
        )
        XCTAssertEqual(presentation.items.count, 5)
    }

    func testReferenceRowsArePureValuesWithoutActionsOrDisabledState() {
        let presentation = ShortcutReferencePresentation.standard

        XCTAssertFalse(presentation.isInteractive)
        for item in presentation.items {
            let storedProperties = Set(
                Mirror(reflecting: item).children.compactMap(\.label)
            )
            XCTAssertEqual(storedProperties, ["id", "title", "shortcut"])
            XCTAssertFalse(item.title.contains("移到"))
            XCTAssertFalse(item.title.contains("迁移"))
        }
        XCTAssertFalse(
            presentation.sections.contains { $0.title == "整理" }
        )
    }

    func testPanelMetricsStayCompactAndFitTheNarrowestWindow() {
        let narrowestWindowWidth: CGFloat = 340
        let minimumHorizontalBreathingRoom: CGFloat = 32

        XCTAssertEqual(ShortcutReferencePanelMetrics.width, 260)
        XCTAssertLessThanOrEqual(ShortcutReferencePanelMetrics.width, 280)
        XCTAssertLessThanOrEqual(
            ShortcutReferencePanelMetrics.width,
            narrowestWindowWidth - minimumHorizontalBreathingRoom
        )
        XCTAssertEqual(ShortcutReferencePanelMetrics.rowHeight, 28)
        XCTAssertGreaterThanOrEqual(ShortcutReferencePanelMetrics.rowHeight, 28)
    }

    func testLightDarkAndSystemPanelsRenderAtFixedWidthWithOpaqueBackground() throws {
        let cases: [(theme: NoteThemeID, appearance: NSAppearance.Name)] = [
            (.warmPaper, .aqua),
            (.midnightIndigo, .darkAqua),
            (.systemOriginal, .aqua),
            (.systemOriginal, .darkAqua),
        ]

        for item in cases {
            let hostingView = makeHostingView(
                theme: item.theme,
                appearance: item.appearance
            )

            XCTAssertEqual(
                hostingView.fittingSize.width,
                ShortcutReferencePanelMetrics.width,
                accuracy: 0.5,
                "\(item.theme.rawValue) \(item.appearance.rawValue)"
            )
            XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
            XCTAssertLessThanOrEqual(
                hostingView.fittingSize.width,
                280,
                "\(item.theme.rawValue) \(item.appearance.rawValue)"
            )

            let bitmap = try render(hostingView)
            let inset = max(1, min(bitmap.pixelsWide, bitmap.pixelsHigh) / 24)
            for x in stride(
                from: inset,
                to: bitmap.pixelsWide - inset,
                by: max(1, bitmap.pixelsWide / 13)
            ) {
                for y in stride(
                    from: inset,
                    to: bitmap.pixelsHigh - inset,
                    by: max(1, bitmap.pixelsHigh / 13)
                ) {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y))
                    XCTAssertEqual(
                        color.alphaComponent,
                        1,
                        accuracy: 0.001,
                        "transparent pixel at \(x),\(y) for "
                            + "\(item.theme.rawValue) \(item.appearance.rawValue)"
                    )
                }
            }
        }
    }

    func testPanelViewContainsNoButtonControlForReferenceRows() {
        let panel = ShortcutReferencePanel(
            presentation: .standard,
            palette: NoteThemeID.warmPaper.palette
        )
        let storedProperties = Set(
            Mirror(reflecting: panel).children.compactMap(\.label)
        )
        let bodyType = String(reflecting: type(of: panel.body))

        XCTAssertEqual(
            storedProperties,
            ["presentation", "palette", "languageRevision"]
        )
        XCTAssertFalse(bodyType.contains("SwiftUI.Button<"))
        XCTAssertFalse(bodyType.contains("SwiftUI.Toggle<"))
        XCTAssertFalse(bodyType.contains("Gesture"))
    }

    func testEscapePolicyOnlyAcceptsPlainEscapeKeyDown() throws {
        let escapeKeyCode = ShortcutReferenceEscapeKeyPolicy.escapeKeyCode
        let plainEscape = try makeKeyEvent(keyCode: escapeKeyCode)
        let commandEscape = try makeKeyEvent(
            keyCode: escapeKeyCode,
            modifiers: .command
        )
        let returnKey = try makeKeyEvent(keyCode: 36)
        let escapeKeyUp = try makeKeyEvent(
            keyCode: escapeKeyCode,
            type: .keyUp
        )

        XCTAssertTrue(
            ShortcutReferenceEscapeKeyPolicy.shouldDismiss(for: plainEscape)
        )
        XCTAssertFalse(
            ShortcutReferenceEscapeKeyPolicy.shouldDismiss(for: commandEscape)
        )
        XCTAssertFalse(
            ShortcutReferenceEscapeKeyPolicy.shouldDismiss(for: returnKey)
        )
        XCTAssertFalse(
            ShortcutReferenceEscapeKeyPolicy.shouldDismiss(for: escapeKeyUp)
        )
    }

    func testEscapeMonitorClosesOnceWithoutChangingEditorSelectionOrFocus() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let editor = NSTextView(frame: window.contentView?.bounds ?? .zero)
        editor.string = "selection stays here"
        editor.setSelectedRange(NSRange(location: 3, length: 9))
        window.contentView = editor
        XCTAssertTrue(window.makeFirstResponder(editor))

        var dismissalCount = 0
        let monitor = ShortcutReferenceEscapeMonitorController()
        monitor.update(isPresented: true) {
            dismissalCount += 1
        }

        let firstEscape = try makeKeyEvent(
            keyCode: ShortcutReferenceEscapeKeyPolicy.escapeKeyCode
        )
        XCTAssertNil(monitor.handle(firstEscape))
        XCTAssertEqual(dismissalCount, 1)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 9))

        // The controller marks itself closed before invoking the SwiftUI
        // binding, so another Escape passes through and never reopens it.
        let secondEscape = try makeKeyEvent(
            keyCode: ShortcutReferenceEscapeKeyPolicy.escapeKeyCode
        )
        XCTAssertTrue(monitor.handle(secondEscape) === secondEscape)
        XCTAssertEqual(dismissalCount, 1)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 3, length: 9))

        monitor.invalidate()
    }

    func testInstalledMonitorReceivesApplicationEscapeEvent() throws {
        _ = NSApplication.shared
        var dismissalCount = 0
        let monitor = ShortcutReferenceEscapeMonitorController()
        monitor.update(isPresented: true) {
            dismissalCount += 1
        }
        defer { monitor.invalidate() }

        NSApp.sendEvent(
            try makeKeyEvent(
                keyCode: ShortcutReferenceEscapeKeyPolicy.escapeKeyCode
            )
        )

        XCTAssertEqual(dismissalCount, 1)
    }

    private func makeHostingView(
        theme: NoteThemeID,
        appearance: NSAppearance.Name
    ) -> NSHostingView<AnyView> {
        let panel = ShortcutReferencePanel(
            presentation: .standard,
            palette: theme.palette
        )
        let rootView = AnyView(
            panel.environment(
                \.colorScheme,
                appearance == .darkAqua ? .dark : .light
            )
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: appearance)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(
            origin: .zero,
            size: CGSize(
                width: ShortcutReferencePanelMetrics.width,
                height: fittingSize.height
            )
        )
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    private func render(
        _ view: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(
            view.bitmapImageRepForCachingDisplay(in: view.bounds),
            file: file,
            line: line
        )
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        type: NSEvent.EventType = .keyDown,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        let characters = keyCode
            == ShortcutReferenceEscapeKeyPolicy.escapeKeyCode ? "\u{1b}" : "\r"
        return try XCTUnwrap(
            NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}
