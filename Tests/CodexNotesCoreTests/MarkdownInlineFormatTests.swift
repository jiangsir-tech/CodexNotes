import XCTest
@testable import CodexNotesCore

final class MarkdownInlineFormatTests: XCTestCase {
    func testBoldWrapPlanUsesOneReplacementAndKeepsInnerSelection() throws {
        let text = "前缀 正文 后缀"
        let selection = range(of: "正文", in: text)

        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: selection),
            .inactive
        )
        let plan = try XCTUnwrap(
            MarkdownInlineFormat.bold.togglePlan(in: text, selection: selection)
        )

        XCTAssertEqual(plan.replacementRange, selection)
        XCTAssertEqual(plan.replacementString, "**正文**")
        XCTAssertEqual(plan.applying(to: text), "前缀 **正文** 后缀")
        XCTAssertEqual(
            plan.resultingSelection,
            NSRange(location: selection.location + 2, length: selection.length)
        )
    }

    func testHighlightWrapPreservesChineseEmojiUTF16Range() throws {
        let text = "前缀 中文😀片段 后缀"
        let selection = range(of: "中文😀片段", in: text)
        let plan = try XCTUnwrap(
            MarkdownInlineFormat.highlight.togglePlan(in: text, selection: selection)
        )

        let result = try XCTUnwrap(plan.applying(to: text))
        XCTAssertEqual(result, "前缀 ==中文😀片段== 后缀")
        XCTAssertEqual(
            (result as NSString).substring(with: plan.resultingSelection),
            "中文😀片段"
        )
    }

    func testWrapTrimsHorizontalWhitespaceWithoutDeletingIt() throws {
        let text = "前  正文\t 后"
        let selection = range(of: "  正文\t", in: text)
        let plan = try XCTUnwrap(
            MarkdownInlineFormat.bold.togglePlan(in: text, selection: selection)
        )

        XCTAssertEqual(plan.applying(to: text), "前  **正文**\t 后")
        XCTAssertEqual(plan.replacementString, "**正文**")
    }

    func testExactContentAndWholeTokenBothUnwrap() throws {
        let text = "前 **正文** 后"
        let content = range(of: "正文", in: text)
        let token = range(of: "**正文**", in: text)

        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: content),
            .active
        )
        let contentPlan = try XCTUnwrap(
            MarkdownInlineFormat.bold.togglePlan(in: text, selection: content)
        )
        XCTAssertEqual(contentPlan.applying(to: text), "前 正文 后")
        XCTAssertEqual(
            contentPlan.resultingSelection,
            NSRange(location: token.location, length: content.length)
        )

        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: token),
            .active
        )
        let tokenPlan = try XCTUnwrap(
            MarkdownInlineFormat.bold.togglePlan(in: text, selection: token)
        )
        XCTAssertEqual(tokenPlan.applying(to: text), "前 正文 后")
        XCTAssertEqual(
            tokenPlan.resultingSelection,
            NSRange(location: token.location, length: content.length)
        )
    }

    func testSelectionAroundTokenTrimsWhitespaceBeforeUnwrap() throws {
        let text = "前 **正文** 后"
        let selection = range(of: " **正文** ", in: text)

        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: selection),
            .active
        )
        let plan = try XCTUnwrap(
            MarkdownInlineFormat.bold.togglePlan(in: text, selection: selection)
        )
        XCTAssertEqual(plan.applying(to: text), "前 正文 后")
    }

    func testDifferentFormatsCanNestAndEachReportsActiveForVisibleContent() throws {
        let original = "**中文😀**"
        let visible = range(of: "中文😀", in: original)
        let addHighlight = try XCTUnwrap(
            MarkdownInlineFormat.highlight.togglePlan(in: original, selection: visible)
        )
        let nested = try XCTUnwrap(addHighlight.applying(to: original))
        XCTAssertEqual(nested, "**==中文😀==**")

        let nestedVisible = range(of: "中文😀", in: nested)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: nested, selection: nestedVisible),
            .active
        )
        XCTAssertEqual(
            MarkdownInlineFormat.highlight.selectionState(in: nested, selection: nestedVisible),
            .active
        )

        let removeBold = try XCTUnwrap(
            MarkdownInlineFormat.bold.togglePlan(in: nested, selection: nestedVisible)
        )
        let boldRemoved = try XCTUnwrap(removeBold.applying(to: nested))
        XCTAssertEqual(boldRemoved, "==中文😀==")
        XCTAssertEqual(
            (boldRemoved as NSString).substring(with: removeBold.resultingSelection),
            "中文😀"
        )

        let removeHighlight = try XCTUnwrap(
            MarkdownInlineFormat.highlight.togglePlan(in: nested, selection: nestedVisible)
        )
        let highlightRemoved = try XCTUnwrap(removeHighlight.applying(to: nested))
        XCTAssertEqual(highlightRemoved, "**中文😀**")
        XCTAssertEqual(
            (highlightRemoved as NSString).substring(with: removeHighlight.resultingSelection),
            "中文😀"
        )
    }

    func testMatchesExposeNestedUTF16TokenAndDelimiterRanges() throws {
        let text = "前 **==中😀文==** 后"
        let matches = MarkdownInlineFormat.matches(in: text)
        XCTAssertEqual(matches.count, 2)

        let bold = try XCTUnwrap(matches.first(where: { $0.format == .bold }))
        let highlight = try XCTUnwrap(matches.first(where: { $0.format == .highlight }))
        XCTAssertEqual((text as NSString).substring(with: bold.tokenRange), "**==中😀文==**")
        XCTAssertEqual((text as NSString).substring(with: bold.contentRange), "==中😀文==")
        XCTAssertEqual((text as NSString).substring(with: highlight.contentRange), "中😀文")
        XCTAssertEqual(bold.openingDelimiterRange.length, 2)
        XCTAssertEqual(bold.closingDelimiterRange.length, 2)
    }

    func testPartialFormattedContentAndHalfDelimiterAreUnavailable() {
        let text = "前 **abcdef** 后"
        let partialContent = range(of: "cd", in: text)
        let halfDelimiter = NSRange(
            location: range(of: "abcdef", in: text).location,
            length: "abcdef**".utf16.count
        )

        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: partialContent),
            .unavailable
        )
        XCTAssertNil(MarkdownInlineFormat.bold.togglePlan(in: text, selection: partialContent))
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: halfDelimiter),
            .unavailable
        )
        XCTAssertNil(MarkdownInlineFormat.bold.togglePlan(in: text, selection: halfDelimiter))
    }

    func testUnbalancedDelimiterInsideSelectionIsUnavailable() {
        let text = "前 foo ** bar 后"
        let selection = range(of: "foo ** bar", in: text)

        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: selection),
            .unavailable
        )
        XCTAssertNil(MarkdownInlineFormat.bold.togglePlan(in: text, selection: selection))
    }

    func testInlineCodeIsProtectedAndNotScannedForFormats() {
        let text = "前 `**code** ==mark==` **real** 后"
        let code = range(of: "code", in: text)
        let matches = MarkdownInlineFormat.matches(in: text)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.format, .bold)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: code),
            .unavailable
        )
        XCTAssertNil(MarkdownInlineFormat.highlight.togglePlan(in: text, selection: code))
    }

    func testFencedCodeIsProtectedAndRealFormatAfterFenceStillScans() {
        let text = "```swift\n**code**\n==mark==\n```\n**real**"
        let code = range(of: "code", in: text)
        let matches = MarkdownInlineFormat.matches(in: text)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual((text as NSString).substring(with: matches[0].contentRange), "real")
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: code),
            .unavailable
        )
    }

    func testBareOpeningFenceAlsoProtectsUntilClosingFence() {
        let text = "```\n**code**\n```\n==real=="
        let matches = MarkdownInlineFormat.matches(in: text)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.format, .highlight)
        XCTAssertEqual((text as NSString).substring(with: matches[0].contentRange), "real")
    }

    func testUnclosedFenceProtectsRemainderOfDocument() {
        let text = "前文\n~~~text\n**code**\n==mark=="
        let matches = MarkdownInlineFormat.matches(in: text)
        let code = range(of: "code", in: text)

        XCTAssertTrue(matches.isEmpty)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: code),
            .unavailable
        )
    }

    func testImageTokenAndCheckboxPrefixAreProtectedButTodoContentIsAllowed() throws {
        let image = "![图片](../Assets/image-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png)"
        let text = image + "\n- [ ] 可格式化内容"
        let imageSelection = range(of: "图片", in: text)
        let prefix = try XCTUnwrap(MarkdownChecklist.checkboxMatches(in: text).first?.prefixRange)
        let content = range(of: "可格式化内容", in: text)

        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: imageSelection),
            .unavailable
        )
        XCTAssertEqual(
            MarkdownInlineFormat.highlight.selectionState(in: text, selection: prefix),
            .unavailable
        )
        XCTAssertEqual(
            MarkdownInlineFormat.highlight.selectionState(in: text, selection: content),
            .inactive
        )
        let plan = try XCTUnwrap(
            MarkdownInlineFormat.highlight.togglePlan(in: text, selection: content)
        )
        XCTAssertEqual(
            plan.applying(to: text),
            image + "\n- [ ] ==可格式化内容=="
        )
    }

    func testLinkLabelCanBeFormattedWithoutScanningOrRewritingDestination() throws {
        let destination = "https://example.com/a_(b)?q=**raw**"
        let autolink = "<https://example.com/**path**>"
        let text = "[中文😀](\(destination)) \(autolink)"
        let label = range(of: "中文😀", in: text)
        let destinationRange = range(of: destination, in: text)
        let autolinkContents = range(of: "https://example.com/**path**", in: text)
        let structuralBoundary = range(of: "](", in: text)

        XCTAssertTrue(MarkdownInlineFormat.matches(in: text).isEmpty)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: label),
            .inactive
        )
        let plan = try XCTUnwrap(
            MarkdownInlineFormat.bold.togglePlan(in: text, selection: label)
        )
        XCTAssertEqual(
            plan.applying(to: text),
            "[**中文😀**](\(destination)) \(autolink)"
        )

        for protectedRange in [destinationRange, autolinkContents, structuralBoundary] {
            XCTAssertEqual(
                MarkdownInlineFormat.bold.selectionState(
                    in: text,
                    selection: protectedRange
                ),
                .unavailable
            )
            XCTAssertNil(
                MarkdownInlineFormat.highlight.togglePlan(
                    in: text,
                    selection: protectedRange
                )
            )
        }
    }

    func testExistingFormatInsideUTF16LinkLabelCanBeRemovedSafely() throws {
        let text = #"[**中文😀**](https://example.com/a\(b\))"#
        let visibleLabel = range(of: "中文😀", in: text)
        let matches = MarkdownInlineFormat.matches(in: text)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.format, .bold)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(
                in: text,
                selection: visibleLabel
            ),
            .active
        )
        let plan = try XCTUnwrap(
            MarkdownInlineFormat.bold.togglePlan(
                in: text,
                selection: visibleLabel
            )
        )
        let result = try XCTUnwrap(plan.applying(to: text))
        XCTAssertEqual(result, #"[中文😀](https://example.com/a\(b\))"#)
        XCTAssertEqual(
            (result as NSString).substring(with: plan.resultingSelection),
            "中文😀"
        )
    }

    func testEscapedAndIncompleteLinkBoundariesAreHandledConservatively() throws {
        let escaped = #"\[literal](https://example.com)"#
        let escapedDestination = range(of: "https://example.com", in: escaped)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(
                in: escaped,
                selection: escapedDestination
            ),
            .inactive
        )
        XCTAssertEqual(
            MarkdownInlineFormat.bold.togglePlan(
                in: escaped,
                selection: escapedDestination
            )?.applying(to: escaped),
            #"\[literal](**https://example.com**)"#
        )

        let incomplete = "[label](https://example.com/a_(b"
        let incompleteDestination = range(of: "https://example.com/a_(b", in: incomplete)
        XCTAssertEqual(
            MarkdownInlineFormat.highlight.selectionState(
                in: incomplete,
                selection: incompleteDestination
            ),
            .unavailable
        )
        XCTAssertNil(
            MarkdownInlineFormat.highlight.togglePlan(
                in: incomplete,
                selection: incompleteDestination
            )
        )

        let label = range(of: "label", in: incomplete)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.togglePlan(
                in: incomplete,
                selection: label
            )?.applying(to: incomplete),
            "[**label**](https://example.com/a_(b"
        )
    }

    func testEmailAndUnclosedURIAutolinksAreProtected() {
        let email = "<user@example.com>"
        let emailContents = range(of: "user@example.com", in: email)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(
                in: email,
                selection: emailContents
            ),
            .unavailable
        )

        let unclosedURI = "<https://example.com/**path**"
        let uriContents = range(of: "https://example.com/**path**", in: unclosedURI)
        XCTAssertTrue(MarkdownInlineFormat.matches(in: unclosedURI).isEmpty)
        XCTAssertEqual(
            MarkdownInlineFormat.highlight.selectionState(
                in: unclosedURI,
                selection: uriContents
            ),
            .unavailable
        )
    }

    func testMultilineCRLFWhitespaceAndInvalidRangesAreUnavailable() {
        let multiline = "第一行\r\n第二行"
        let full = NSRange(location: 0, length: (multiline as NSString).length)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: multiline, selection: full),
            .unavailable
        )
        XCTAssertNil(MarkdownInlineFormat.bold.togglePlan(in: multiline, selection: full))

        XCTAssertEqual(
            MarkdownInlineFormat.highlight.selectionState(
                in: " \t ",
                selection: NSRange(location: 0, length: 3)
            ),
            .unavailable
        )
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(
                in: "正文",
                selection: NSRange(location: 99, length: 1)
            ),
            .unavailable
        )
    }

    func testSelectionSplittingEmojiSurrogatePairIsUnavailable() {
        let text = "A😀B"
        let splitSurrogate = NSRange(location: 1, length: 1)

        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(in: text, selection: splitSurrogate),
            .unavailable
        )
        XCTAssertNil(MarkdownInlineFormat.bold.togglePlan(in: text, selection: splitSurrogate))
    }

    func testEscapedDelimitersAreNotParsedAsFormatting() throws {
        let text = #"\**literal\** and \==mark\== then plain"#
        let matches = MarkdownInlineFormat.matches(in: text)
        XCTAssertTrue(matches.isEmpty)

        let plain = range(of: "plain", in: text)
        let plan = try XCTUnwrap(
            MarkdownInlineFormat.bold.togglePlan(in: text, selection: plain)
        )
        XCTAssertEqual(
            plan.applying(to: text),
            #"\**literal\** and \==mark\== then **plain**"#
        )
    }

    func testTripleAndLongerDelimiterRunsAreConservativelyUnavailable() {
        for (text, format) in [
            ("***text***", MarkdownInlineFormat.bold),
            ("****text****", MarkdownInlineFormat.bold),
            ("===text===", MarkdownInlineFormat.highlight)
        ] {
            XCTAssertTrue(MarkdownInlineFormat.matches(in: text).isEmpty)
            let selection = NSRange(location: 0, length: (text as NSString).length)
            XCTAssertEqual(
                format.selectionState(in: text, selection: selection),
                .unavailable
            )
            XCTAssertNil(format.togglePlan(in: text, selection: selection))

            let visible = range(of: "text", in: text)
            XCTAssertEqual(
                format.selectionState(in: text, selection: visible),
                .unavailable
            )
            XCTAssertNil(format.togglePlan(in: text, selection: visible))
        }
    }

    func testVisibleTextBesideUnclosedOrUnsupportedDelimiterIsUnavailable() {
        for (text, substring, format) in [
            ("foo **bar", "bar", MarkdownInlineFormat.bold),
            ("**bar***", "bar", MarkdownInlineFormat.bold),
            ("foo ==bar", "bar", MarkdownInlineFormat.highlight),
            ("==bar===", "bar", MarkdownInlineFormat.highlight)
        ] {
            let selection = range(of: substring, in: text)
            XCTAssertEqual(
                format.selectionState(in: text, selection: selection),
                .unavailable
            )
            XCTAssertNil(format.togglePlan(in: text, selection: selection))
        }
    }

    func testFormattingBesideSameFormatMergesIntoOneCanonicalToken() throws {
        for format in MarkdownInlineFormat.allCases {
            let delimiter = format.delimiter

            let leftText = "\(delimiter)甲\(delimiter)乙"
            let leftPlan = try XCTUnwrap(
                format.togglePlan(
                    in: leftText,
                    selection: range(of: "乙", in: leftText)
                )
            )
            let leftResult = try XCTUnwrap(leftPlan.applying(to: leftText))
            XCTAssertEqual(leftResult, "\(delimiter)甲乙\(delimiter)")
            XCTAssertEqual(
                (leftResult as NSString).substring(with: leftPlan.resultingSelection),
                "乙"
            )

            let rightText = "甲\(delimiter)乙\(delimiter)"
            let rightPlan = try XCTUnwrap(
                format.togglePlan(
                    in: rightText,
                    selection: range(of: "甲", in: rightText)
                )
            )
            XCTAssertEqual(
                rightPlan.applying(to: rightText),
                "\(delimiter)甲乙\(delimiter)"
            )

            let bothText = "\(delimiter)甲\(delimiter)乙\(delimiter)丙\(delimiter)"
            let bothPlan = try XCTUnwrap(
                format.togglePlan(
                    in: bothText,
                    selection: range(of: "乙", in: bothText)
                )
            )
            let bothResult = try XCTUnwrap(bothPlan.applying(to: bothText))
            XCTAssertEqual(bothResult, "\(delimiter)甲乙丙\(delimiter)")
            XCTAssertEqual(
                (bothResult as NSString).substring(with: bothPlan.resultingSelection),
                "乙"
            )
        }
    }

    func testScannerRecognizesLegacyAdjacentSameFormatTokens() throws {
        for (text, format, contents) in [
            ("**甲****乙**", MarkdownInlineFormat.bold, ["甲", "乙"]),
            ("==甲====乙==", MarkdownInlineFormat.highlight, ["甲", "乙"])
        ] {
            let matches = MarkdownInlineFormat.matches(in: text)
            XCTAssertEqual(matches.count, 2)
            XCTAssertEqual(matches.map(\.format), [format, format])
            XCTAssertEqual(
                matches.map { (text as NSString).substring(with: $0.contentRange) },
                contents
            )

            let second = try XCTUnwrap(matches.last)
            let plan = try XCTUnwrap(
                format.togglePlan(in: text, selection: second.contentRange)
            )
            XCTAssertEqual(
                plan.applying(to: text),
                format == .bold ? "**甲**乙" : "==甲==乙"
            )
        }
    }

    func testScannerRejectsMultilineAndUnsupportedRunsInsideOtherwisePairedToken() {
        let values = [
            "**first\nsecond**",
            "==first\r\nsecond=="
        ]

        for text in values {
            XCTAssertTrue(
                MarkdownInlineFormat.matches(in: text).isEmpty,
                "Unexpected match in: \(text)"
            )
        }
    }

    private func range(of substring: String, in text: String) -> NSRange {
        let range = (text as NSString).range(of: substring)
        XCTAssertNotEqual(range.location, NSNotFound, "Missing test substring: \(substring)")
        return range
    }
}
