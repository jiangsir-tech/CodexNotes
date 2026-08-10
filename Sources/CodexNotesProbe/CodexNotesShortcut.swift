import SwiftUI

struct CodexNotesShortcutSpec {
    let shortcut: KeyboardShortcut
    let displayName: String
}

enum CodexNotesShortcut {
    static let cycleTodo = CodexNotesShortcutSpec(
        shortcut: KeyboardShortcut(.return, modifiers: .command),
        displayName: "⌘↩"
    )
    static let taskNote = CodexNotesShortcutSpec(
        shortcut: KeyboardShortcut("1", modifiers: .command),
        displayName: "⌘1"
    )
    static let projectNote = CodexNotesShortcutSpec(
        shortcut: KeyboardShortcut("2", modifiers: .command),
        displayName: "⌘2"
    )
}
