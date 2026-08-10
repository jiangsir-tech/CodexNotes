import XCTest
@testable import CodexNotesCore

final class MarkdownChecklistTests: XCTestCase {
    func testParsesSupportedCheckboxes() {
        let text = """
        # 下一步
        - [ ] 未完成
        - [x] 已完成
          * [X] 缩进完成
        普通文字 [ ] 不处理
        """

        let lines = MarkdownChecklist.lines(in: text)

        XCTAssertEqual(lines.filter(\.isCheckbox).count, 3)
        XCTAssertFalse(lines[1].isChecked)
        XCTAssertTrue(lines[2].isChecked)
        XCTAssertTrue(lines[3].isChecked)
        XCTAssertFalse(lines[4].isCheckbox)
    }

    func testLargeChecklistParsingKeepsAllMatchesAndProgress() throws {
        let lines = (0..<1_000).map { index in
            guard index < 300 else { return "普通正文 \(index)" }
            let indentation = index.isMultiple(of: 3) ? "\t" : "  "
            let marker = index.isMultiple(of: 2) ? "x" : " "
            return "\(indentation)- [\(marker)] 待办 \(index)"
        }
        let text = lines.joined(separator: "\n")

        let matches = MarkdownChecklist.checkboxMatches(in: text)

        XCTAssertEqual(matches.count, 300)
        XCTAssertEqual(
            MarkdownChecklist.progress(in: text),
            MarkdownChecklistProgress(completed: 150, total: 300)
        )
        let source = text as NSString
        XCTAssertEqual(
            source.substring(with: try XCTUnwrap(matches.first?.contentRange)),
            "待办 0"
        )
        XCTAssertEqual(
            source.substring(with: try XCTUnwrap(matches.last?.contentRange)),
            "待办 299"
        )
        XCTAssertTrue(zip(matches, matches.dropFirst()).allSatisfy {
            $0.lineRange.location < $1.lineRange.location
        })
    }

    func testToggleChangesOnlySelectedDuplicateLine() {
        let original = "- [ ] 相同文字\n- [ ] 相同文字\n"
        let toggled = MarkdownChecklist.toggle(line: 1, in: original)

        XCTAssertEqual(toggled, "- [ ] 相同文字\n- [x] 相同文字\n")
    }

    func testDoubleToggleReturnsToOriginalText() {
        let original = "- [ ] 下一步"
        let once = MarkdownChecklist.toggle(line: 0, in: original)
        let twice = MarkdownChecklist.toggle(line: 0, in: once)

        XCTAssertEqual(twice, original)
    }

    func testNonCheckboxLineIsUnchanged() {
        let original = "普通 [ ] 文本"
        XCTAssertEqual(MarkdownChecklist.toggle(line: 0, in: original), original)
    }

    func testParserUsesStrictMarkdownAndAbsoluteUTF16Ranges() {
        let text = "前言\r\n  + [X] 完成😀\r\n- [ ]foo"
        let matches = MarkdownChecklist.checkboxMatches(in: text)

        XCTAssertEqual(matches.count, 1)
        let match = try! XCTUnwrap(matches.first)
        let source = text as NSString
        XCTAssertEqual(source.substring(with: match.tokenRange), "[X]")
        XCTAssertEqual(source.substring(with: match.markerRange), "X")
        XCTAssertEqual(source.substring(with: match.contentRange), "完成😀")
        XCTAssertEqual(source.substring(with: match.prefixRange), "+ [X] ")
        XCTAssertTrue(match.isChecked)
    }

    func testConvertsCaretLineAndPreservesEmojiCaretPosition() throws {
        let original = "前言\n😀写文案\n结尾"
        let caret = (original as NSString).range(of: "文").location
        let plan = try XCTUnwrap(
            MarkdownChecklist.toggleTodoFormat(
                in: original,
                selection: NSRange(location: caret, length: 0)
            )
        )

        XCTAssertEqual(plan.applying(to: original), "前言\n- [ ] 😀写文案\n结尾")
        XCTAssertEqual(plan.resultingSelection, NSRange(location: caret + 6, length: 0))
    }

    func testConvertsCollapsedEmptyLineButSkipsBlankLinesInMultiSelection() throws {
        let original = "上\n\n下"
        let emptyLinePlan = try XCTUnwrap(
            MarkdownChecklist.toggleTodoFormat(
                in: original,
                selection: NSRange(location: 2, length: 0)
            )
        )
        XCTAssertEqual(emptyLinePlan.applying(to: original), "上\n- [ ] \n下")
        XCTAssertEqual(emptyLinePlan.resultingSelection, NSRange(location: 8, length: 0))

        let multiPlan = try XCTUnwrap(
            MarkdownChecklist.toggleTodoFormat(
                in: original,
                selection: NSRange(location: 0, length: (original as NSString).length)
            )
        )
        XCTAssertEqual(multiPlan.applying(to: original), "- [ ] 上\n\n- [ ] 下")
    }

    func testConvertsExistingBulletsWithoutDuplicatingThem() throws {
        let original = "  * 做事\n\t+ 另一件事"
        let plan = try XCTUnwrap(
            MarkdownChecklist.toggleTodoFormat(
                in: original,
                selection: NSRange(location: 0, length: (original as NSString).length)
            )
        )

        XCTAssertEqual(plan.applying(to: original), "  - [ ] 做事\n\t- [ ] 另一件事")
    }

    func testMixedSelectionKeepsExistingStateAndAllTodoSelectionRemovesFormat() throws {
        let mixed = "普通\n- [x] 已完成\n* 新项目"
        let mixedPlan = try XCTUnwrap(
            MarkdownChecklist.toggleTodoFormat(
                in: mixed,
                selection: NSRange(location: 0, length: (mixed as NSString).length)
            )
        )
        XCTAssertEqual(
            mixedPlan.applying(to: mixed),
            "- [ ] 普通\n- [x] 已完成\n- [ ] 新项目"
        )

        let todos = "  - [ ] 一\r\n- [x] 二"
        let removalPlan = try XCTUnwrap(
            MarkdownChecklist.toggleTodoFormat(
                in: todos,
                selection: NSRange(location: 0, length: (todos as NSString).length)
            )
        )
        XCTAssertEqual(removalPlan.applying(to: todos), "  一\r\n二")
    }

    func testSelectionEndingAtNextLineStartDoesNotTouchNextLine() throws {
        let original = "一\n二"
        let plan = try XCTUnwrap(
            MarkdownChecklist.toggleTodoFormat(
                in: original,
                selection: NSRange(location: 0, length: 2)
            )
        )
        XCTAssertEqual(plan.applying(to: original), "- [ ] 一\n二")
    }

    func testTransformsPreserveMixedLineEndingsByteForByte() throws {
        let original = "一\r\n二\r三\n四"
        let plan = try XCTUnwrap(
            MarkdownChecklist.toggleTodoFormat(
                in: original,
                selection: NSRange(location: 0, length: (original as NSString).length)
            )
        )
        XCTAssertEqual(
            plan.applying(to: original),
            "- [ ] 一\r\n- [ ] 二\r- [ ] 三\n- [ ] 四"
        )
    }

    func testCycleTodoStateTraversesAllThreeStatesAndRestoresSelection() throws {
        let original = "前言\r\n  写😀文案\r\n后续"
        let originalSelection = (original as NSString).range(of: "😀文")

        let uncheckedPlan = try XCTUnwrap(
            MarkdownChecklist.cycleTodoState(
                in: original,
                selection: originalSelection
            )
        )
        let unchecked = try XCTUnwrap(uncheckedPlan.applying(to: original))
        XCTAssertEqual(unchecked, "前言\r\n  - [ ] 写😀文案\r\n后续")
        XCTAssertEqual(
            uncheckedPlan.resultingSelection,
            NSRange(
                location: originalSelection.location + 6,
                length: originalSelection.length
            )
        )

        let checkedPlan = try XCTUnwrap(
            MarkdownChecklist.cycleTodoState(
                in: unchecked,
                selection: uncheckedPlan.resultingSelection
            )
        )
        let checked = try XCTUnwrap(checkedPlan.applying(to: unchecked))
        XCTAssertEqual(checked, "前言\r\n  - [x] 写😀文案\r\n后续")
        XCTAssertEqual(checkedPlan.replacementRange.length, 1)
        XCTAssertEqual(checkedPlan.replacementString, "x")
        XCTAssertEqual(checkedPlan.resultingSelection, uncheckedPlan.resultingSelection)

        let ordinaryPlan = try XCTUnwrap(
            MarkdownChecklist.cycleTodoState(
                in: checked,
                selection: checkedPlan.resultingSelection
            )
        )
        XCTAssertEqual(ordinaryPlan.applying(to: checked), original)
        XCTAssertEqual(ordinaryPlan.resultingSelection, originalSelection)
    }

    func testCycleTodoStatePreservesExistingTodoSyntaxUntilRemoval() throws {
        let unchecked = "前\r\n\t+ [ ]\t正文  \r\n后"
        let selection = (unchecked as NSString).range(of: "正文")
        let match = try XCTUnwrap(
            MarkdownChecklist.checkboxMatches(in: unchecked).first
        )

        let checkedPlan = try XCTUnwrap(
            MarkdownChecklist.cycleTodoState(
                in: unchecked,
                selection: selection
            )
        )
        let checked = try XCTUnwrap(checkedPlan.applying(to: unchecked))
        XCTAssertEqual(checked, "前\r\n\t+ [x]\t正文  \r\n后")
        XCTAssertEqual(checkedPlan.replacementRange, match.markerRange)

        let ordinaryPlan = try XCTUnwrap(
            MarkdownChecklist.cycleTodoState(
                in: checked,
                selection: checkedPlan.resultingSelection
            )
        )
        XCTAssertEqual(ordinaryPlan.applying(to: checked), "前\r\n\t正文  \r\n后")
        XCTAssertEqual(ordinaryPlan.replacementRange, match.prefixRange)
        XCTAssertEqual(ordinaryPlan.replacementString, "")
    }

    func testCycleTodoStateUsesExistingEmptyLineAndBulletSemantics() throws {
        let emptyLine = "上\r\n\r\n下"
        let emptyPlan = try XCTUnwrap(
            MarkdownChecklist.cycleTodoState(
                in: emptyLine,
                selection: NSRange(location: 3, length: 0)
            )
        )
        XCTAssertEqual(emptyPlan.applying(to: emptyLine), "上\r\n- [ ] \r\n下")

        let bullet = "  * 保留正文"
        let bulletPlan = try XCTUnwrap(
            MarkdownChecklist.cycleTodoState(
                in: bullet,
                selection: NSRange(location: 5, length: 0)
            )
        )
        XCTAssertEqual(bulletPlan.applying(to: bullet), "  - [ ] 保留正文")
        XCTAssertEqual(bulletPlan.replacementRange, NSRange(location: 2, length: 2))
    }

    func testCycleTodoStateRejectsMultilineSelection() {
        let original = "第一行\r\n第二行"
        let source = original as NSString
        let first = source.range(of: "一")
        let second = source.range(of: "二")
        let multilineSelection = NSRange(
            location: first.location,
            length: NSMaxRange(second) - first.location
        )

        XCTAssertNil(
            MarkdownChecklist.cycleTodoState(
                in: original,
                selection: multilineSelection
            )
        )
        XCTAssertNil(
            MarkdownChecklist.todoCycleState(
                in: original,
                selection: multilineSelection
            )
        )
    }

    func testTodoCycleStateReportsCurrentSingleLineState() {
        let selection = NSRange(location: 7, length: 0)

        XCTAssertEqual(
            MarkdownChecklist.todoCycleState(
                in: "  普通正文",
                selection: NSRange(location: 3, length: 0)
            ),
            .plain
        )
        XCTAssertEqual(
            MarkdownChecklist.todoCycleState(
                in: "- [ ] 待办",
                selection: selection
            ),
            .incomplete
        )
        XCTAssertEqual(
            MarkdownChecklist.todoCycleState(
                in: "+ [X]\t完成",
                selection: selection
            ),
            .complete
        )
    }

    func testClickToggleUsesTokenHitRangeAndPreservesCRLF() throws {
        let original = "- [ ] 相同\r\n- [ ] 相同\r\n"
        let matches = MarkdownChecklist.checkboxMatches(in: original)
        let second = try XCTUnwrap(matches.last)
        let plan = try XCTUnwrap(
            MarkdownChecklist.toggleCheckbox(
                in: original,
                clickUTF16Offset: second.tokenRange.location + 1
            )
        )

        XCTAssertEqual(plan.applying(to: original), "- [ ] 相同\r\n- [x] 相同\r\n")
        XCTAssertNil(
            MarkdownChecklist.toggleCheckbox(
                in: original,
                clickUTF16Offset: second.prefixRange.location
            )
        )
        XCTAssertNil(
            MarkdownChecklist.toggleCheckbox(
                in: original,
                clickUTF16Offset: NSMaxRange(second.tokenRange)
            )
        )
    }

    func testCheckedRangesAndProgressExcludeSyntaxAndLineEndings() throws {
        let text = "- [ ] 未完成\n  * [X] 完成😀\r\n- [x] \n"
        let progress = MarkdownChecklist.progress(in: text)
        let ranges = MarkdownChecklist.checkedContentRanges(in: text)

        XCTAssertEqual(progress, MarkdownChecklistProgress(completed: 2, total: 3))
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual((text as NSString).substring(with: try XCTUnwrap(ranges.first)), "完成😀")
    }

    func testReturnCreatesNextTodoUsingExistingNewlineStyle() throws {
        let original = "- [ ] 第一项\r\n下一行"
        let caret = NSMaxRange((original as NSString).range(of: "第一项"))
        let plan = try XCTUnwrap(
            MarkdownChecklist.returnPlan(
                in: original,
                selection: NSRange(location: caret, length: 0)
            )
        )

        XCTAssertEqual(plan.action, .insertNextTodo)
        XCTAssertEqual(plan.edit.applying(to: original), "- [ ] 第一项\r\n- [ ] \r\n下一行")
    }

    func testReturnAtVisualLineEndKeepsTrailingSpacesOnPreviousTodo() throws {
        let original = "- [ ] 第一项  "
        let visualLineEnd = NSMaxRange((original as NSString).range(of: "第一项"))
        let plan = try XCTUnwrap(
            MarkdownChecklist.returnPlan(
                in: original,
                selection: NSRange(location: visualLineEnd, length: 0)
            )
        )

        XCTAssertEqual(plan.action, .insertNextTodo)
        XCTAssertEqual(plan.edit.replacementRange, NSRange(location: 11, length: 0))
        XCTAssertEqual(plan.edit.applying(to: original), original + "\n- [ ] ")
    }

    func testReturnOnEmptyTodoExitsList() throws {
        let original = "  - [ ] \n后续"
        let match = try XCTUnwrap(MarkdownChecklist.checkboxMatches(in: original).first)
        let plan = try XCTUnwrap(
            MarkdownChecklist.returnPlan(
                in: original,
                selection: NSRange(location: match.contentRange.location, length: 0)
            )
        )

        XCTAssertEqual(plan.action, .exitTodoList)
        XCTAssertEqual(plan.edit.applying(to: original), "  \n后续")
        XCTAssertEqual(plan.edit.resultingSelection.location, 2)
    }

    func testDeleteBackwardAtContentStartRemovesTodoPrefixOnce() throws {
        for original in ["- [ ] ", "  - [ ] 正文", "\t- [x] 已完成"] {
            let match = try XCTUnwrap(
                MarkdownChecklist.checkboxMatches(in: original).first
            )
            let plan = try XCTUnwrap(
                MarkdownChecklist.deleteBackwardPlan(
                    in: original,
                    selection: NSRange(
                        location: match.contentRange.location,
                        length: 0
                    )
                )
            )
            let expected = (original as NSString).replacingCharacters(
                in: match.prefixRange,
                with: ""
            )

            XCTAssertEqual(plan.applying(to: original), expected)
            XCTAssertEqual(
                plan.resultingSelection,
                NSRange(location: match.prefixRange.location, length: 0)
            )
        }
    }

    func testDeleteBackwardInsideHiddenSeparatorWhitespaceRemovesTodoPrefix() throws {
        let original = "- [ ]   "
        let match = try XCTUnwrap(
            MarkdownChecklist.checkboxMatches(in: original).first
        )
        let hiddenPrefixCarets = [
            match.prefixRange.location,
            match.prefixRange.location + 1,
            NSMaxRange(match.tokenRange) + 1,
            match.contentRange.location
        ]

        for caret in hiddenPrefixCarets {
            let plan = try XCTUnwrap(
                MarkdownChecklist.deleteBackwardPlan(
                    in: original,
                    selection: NSRange(location: caret, length: 0)
                )
            )

            XCTAssertEqual(plan.applying(to: original), "")
            XCTAssertEqual(plan.resultingSelection, NSRange(location: 0, length: 0))
        }
    }

    func testReturnThenDeleteBackwardExitsFreshTodoInOneStep() throws {
        let original = "  - [ ] 当前任务"
        let returnPlan = try XCTUnwrap(
            MarkdownChecklist.returnPlan(
                in: original,
                selection: NSRange(location: (original as NSString).length, length: 0)
            )
        )
        let withNextTodo = try XCTUnwrap(returnPlan.edit.applying(to: original))
        let deletePlan = try XCTUnwrap(
            MarkdownChecklist.deleteBackwardPlan(
                in: withNextTodo,
                selection: returnPlan.edit.resultingSelection
            )
        )

        XCTAssertEqual(withNextTodo, "  - [ ] 当前任务\n  - [ ] ")
        XCTAssertEqual(deletePlan.applying(to: withNextTodo), original + "\n  ")
        XCTAssertEqual(deletePlan.resultingSelection.location, (original as NSString).length + 3)
    }

    func testDeleteBackwardPreservesCRLFOutsideCurrentTodoLine() throws {
        let original = "前一行\r\n\t- [x] 已完成\r\n后一行"
        let match = try XCTUnwrap(
            MarkdownChecklist.checkboxMatches(in: original).first
        )
        let plan = try XCTUnwrap(
            MarkdownChecklist.deleteBackwardPlan(
                in: original,
                selection: NSRange(location: match.contentRange.location, length: 0)
            )
        )

        XCTAssertEqual(plan.applying(to: original), "前一行\r\n\t已完成\r\n后一行")
        XCTAssertEqual(plan.resultingSelection, NSRange(location: 6, length: 0))
    }

    func testDeleteBackwardOnlyInterceptsCollapsedCaretAtContentStart() throws {
        let original = "- [ ] 正文"
        let match = try XCTUnwrap(MarkdownChecklist.checkboxMatches(in: original).first)

        XCTAssertNil(
            MarkdownChecklist.deleteBackwardPlan(
                in: original,
                selection: NSRange(
                    location: match.contentRange.location + 1,
                    length: 0
                )
            )
        )
        XCTAssertNil(
            MarkdownChecklist.deleteBackwardPlan(
                in: original,
                selection: NSRange(location: match.contentRange.location, length: 1)
            )
        )
        XCTAssertNil(
            MarkdownChecklist.deleteBackwardPlan(
                in: "普通正文",
                selection: NSRange(location: 0, length: 0)
            )
        )
    }

    func testEmptyDocumentAndTrailingEmptyLineCanBecomeTodo() throws {
        let emptyPlan = try XCTUnwrap(
            MarkdownChecklist.toggleTodoFormat(
                in: "",
                selection: NSRange(location: 0, length: 0)
            )
        )
        XCTAssertEqual(emptyPlan.applying(to: ""), "- [ ] ")

        for ending in ["\n", "\r\n", "\r"] {
            let original = "上一行" + ending
            let caret = (original as NSString).length
            let plan = try XCTUnwrap(
                MarkdownChecklist.toggleTodoFormat(
                    in: original,
                    selection: NSRange(location: caret, length: 0)
                )
            )
            XCTAssertEqual(plan.applying(to: original), original + "- [ ] ")
        }
    }

    func testRejectsInvalidRanges() {
        let negativeLocation = NSRange(location: -1, length: 0)
        let negativeLength = NSRange(location: 0, length: -1)

        XCTAssertNil(
            MarkdownChecklist.toggleTodoFormat(
                in: "文字",
                selection: negativeLocation
            )
        )
        XCTAssertNil(
            MarkdownChecklist.toggleTodoFormat(
                in: "文字",
                selection: negativeLength
            )
        )
        XCTAssertNil(
            MarkdownTextEditPlan(
                replacementRange: negativeLocation,
                replacementString: "",
                resultingSelection: NSRange(location: 0, length: 0)
            ).applying(to: "文字")
        )
    }
}
