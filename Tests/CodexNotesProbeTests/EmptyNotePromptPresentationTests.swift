import CodexNotesCore
@testable import CodexNotesProbe
import XCTest

final class EmptyNotePromptPresentationTests: XCTestCase {
    func testTaskCopyChangesWithoutLeakingIntoProjectNotes() {
        let taskPrompt = EmptyNotePromptPresentation(.task)
        XCTAssertEqual(taskPrompt.title, L10n.text(.emptyNoteTaskPrompt))
        XCTAssertEqual(taskPrompt.shortcutHint, L10n.text(.emptyNoteTaskShortcutHint))

        let projectPrompt = EmptyNotePromptPresentation(.project)
        XCTAssertEqual(projectPrompt.title, L10n.text(.emptyNoteProjectPrompt))
        XCTAssertEqual(projectPrompt.shortcutHint, L10n.text(.emptyNoteProjectTodoExample))
    }
}
