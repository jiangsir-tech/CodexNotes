import SwiftUI
import XCTest
@testable import CodexNotesProbe

final class CodexNotesShortcutTests: XCTestCase {
    func testOnlyApprovedFirstRoundShortcutSpecs() {
        XCTAssertEqual(CodexNotesShortcut.cycleTodo.shortcut.key, .return)
        XCTAssertEqual(CodexNotesShortcut.cycleTodo.shortcut.modifiers, .command)
        XCTAssertEqual(CodexNotesShortcut.cycleTodo.displayName, "⌘↩")

        XCTAssertEqual(CodexNotesShortcut.taskNote.shortcut.key, "1")
        XCTAssertEqual(CodexNotesShortcut.taskNote.shortcut.modifiers, .command)
        XCTAssertEqual(CodexNotesShortcut.taskNote.displayName, "⌘1")

        XCTAssertEqual(CodexNotesShortcut.projectNote.shortcut.key, "2")
        XCTAssertEqual(CodexNotesShortcut.projectNote.shortcut.modifiers, .command)
        XCTAssertEqual(CodexNotesShortcut.projectNote.displayName, "⌘2")
    }
}
