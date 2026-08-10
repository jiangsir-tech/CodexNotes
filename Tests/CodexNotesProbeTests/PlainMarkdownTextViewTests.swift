import AppKit
import SwiftUI
import XCTest
@testable import CodexNotesCore
@testable import CodexNotesProbe

@MainActor
final class PlainMarkdownTextViewTests: XCTestCase {
    func testDocumentIdentityChangeClearsUndoAndRedoWhenMarkdownMatches() throws {
        let text = "两份笔记的正文完全相同"
        let firstDocument = makeDocument(scope: .task, stableKey: "task-a")
        let harness = makeHarness(
            text: text,
            textWidth: 320,
            documentIdentity: MarkdownEditorDocumentIdentity(document: firstDocument)
        )
        let undoManager = try XCTUnwrap(harness.textView.undoManager)
        let probe = UndoProbe()

        undoManager.removeAllActions()
        undoManager.registerUndo(withTarget: probe) { target in
            target.didUndo = true
        }
        XCTAssertTrue(undoManager.canUndo)

        let stableKeyChanged = makeDocument(scope: .task, stableKey: "task-b")
        XCTAssertTrue(
            harness.coordinator.transitionDocumentIfNeeded(
                to: MarkdownEditorDocumentIdentity(document: stableKeyChanged),
                text: text,
                controller: harness.controller,
                in: harness.textView
            )
        )
        XCTAssertEqual(harness.textView.string, text)
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertFalse(undoManager.canRedo)

        undoManager.registerUndo(withTarget: probe) { target in
            undoManager.registerUndo(withTarget: target) { redoTarget in
                redoTarget.didUndo = false
            }
            target.didUndo = true
        }
        undoManager.undo()
        XCTAssertTrue(undoManager.canRedo)

        let fileURLChanged = NoteDocument(
            scope: .task,
            stableKey: stableKeyChanged.stableKey,
            displayName: stableKeyChanged.displayName,
            context: stableKeyChanged.context,
            fileURL: URL(fileURLWithPath: "/tmp/codex-notes-selection-test-other-file.md")
        )
        XCTAssertTrue(
            harness.coordinator.transitionDocumentIfNeeded(
                to: MarkdownEditorDocumentIdentity(document: fileURLChanged),
                text: text,
                controller: harness.controller,
                in: harness.textView
            )
        )
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertFalse(undoManager.canRedo)

        undoManager.registerUndo(withTarget: probe) { target in
            target.didUndo = true
        }
        XCTAssertTrue(undoManager.canUndo)
        harness.textView.isEditable = false
        let scopeChanged = NoteDocument(
            scope: .project,
            stableKey: fileURLChanged.stableKey,
            displayName: fileURLChanged.displayName,
            context: fileURLChanged.context,
            fileURL: fileURLChanged.fileURL
        )
        XCTAssertTrue(
            harness.coordinator.transitionDocumentIfNeeded(
                to: MarkdownEditorDocumentIdentity(document: scopeChanged),
                text: text,
                controller: harness.controller,
                in: harness.textView
            )
        )
        XCTAssertFalse(undoManager.canUndo)
        XCTAssertFalse(undoManager.canRedo)
        XCTAssertFalse(harness.textView.isEditable)
    }

    func testDocumentIdentityChangeEndsMarkedTextWithoutBindingItToNewDocument() throws {
        let oldText = "旧笔记"
        let newText = "新笔记"
        let bindingProbe = TextBindingProbe(oldText)
        let firstDocument = makeDocument(scope: .task, stableKey: "task-ime")
        let harness = makeHarness(
            text: oldText,
            textWidth: 320,
            documentIdentity: MarkdownEditorDocumentIdentity(document: firstDocument),
            textBinding: Binding(
                get: { bindingProbe.value },
                set: { bindingProbe.record($0) }
            )
        )
        let textView = harness.textView
        let oldLength = (oldText as NSString).length
        textView.setSelectedRange(NSRange(location: oldLength, length: 0))
        textView.setMarkedText(
            "pin",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: oldLength, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        bindingProbe.reset(to: newText)

        let nextDocument = makeDocument(scope: .project, stableKey: "project-ime")
        XCTAssertTrue(
            harness.coordinator.transitionDocumentIfNeeded(
                to: MarkdownEditorDocumentIdentity(document: nextDocument),
                text: newText,
                controller: harness.controller,
                in: textView
            )
        )

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(textView.string, newText)
        XCTAssertEqual(bindingProbe.value, newText)
        XCTAssertTrue(bindingProbe.recordedWrites.isEmpty)
        XCTAssertFalse(try XCTUnwrap(textView.undoManager).canUndo)
        XCTAssertFalse(try XCTUnwrap(textView.undoManager).canRedo)
    }

    func testManagedImagePreviewUsesDerivedGlyphsAndPreservesEditorState() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let asset = try store.importImage(data: makePNGData(width: 32, height: 16))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "preview")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let text = "预览前\n\(asset.markdown)\n- [ ] 预览后待办"
        let bindingProbe = TextBindingProbe(text)
        let harness = makeHarness(
            text: text,
            textWidth: 360,
            viewportHeight: 120,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            ),
            textBinding: Binding(
                get: { bindingProbe.value },
                set: { bindingProbe.record($0) }
            )
        )
        let textView = harness.textView
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let imageMatch = try XCTUnwrap(MarkdownImage.matches(in: text).first)
        let selection = NSRange(location: 1, length: 2)
        textView.setSelectedRange(selection)
        harness.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 20))
        harness.scrollView.reflectScrolledClipView(harness.scrollView.contentView)
        let scrollOrigin = harness.scrollView.contentView.bounds.origin

        let undoManager = try XCTUnwrap(textView.undoManager)
        let undoProbe = UndoProbe()
        undoManager.removeAllActions()
        undoManager.registerUndo(withTarget: undoProbe) { target in
            target.didUndo = true
        }
        bindingProbe.reset(to: text)
        textView.refreshChecklistPresentation(forceLayout: true)
        layoutManager.ensureLayout(for: textContainer)

        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(bindingProbe.value, text)
        XCTAssertTrue(bindingProbe.recordedWrites.isEmpty)
        XCTAssertEqual(textView.selectedRange(), selection)
        XCTAssertEqual(harness.scrollView.contentView.bounds.origin, scrollOrigin)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertEqual(textView.managedImageMatches, [imageMatch])

        let firstGlyph = layoutManager.glyphIndexForCharacter(
            at: imageMatch.tokenRange.location
        )
        let secondGlyph = layoutManager.glyphIndexForCharacter(
            at: imageMatch.tokenRange.location + 1
        )
        XCTAssertTrue(
            layoutManager.propertyForGlyph(at: firstGlyph).contains(.controlCharacter)
        )
        XCTAssertTrue(layoutManager.propertyForGlyph(at: secondGlyph).contains(.null))
        let imageLineRect = layoutManager.lineFragmentRect(
            forGlyphAt: firstGlyph,
            effectiveRange: nil
        )
        XCTAssertGreaterThan(imageLineRect.height, 72)

        let previewRect = try XCTUnwrap(
            textView.managedImagePreviewRect(
                atUTF16Offset: imageMatch.tokenRange.location
            )
        )
        XCTAssertGreaterThan(previewRect.width, 96)
        XCTAssertGreaterThan(previewRect.height, 60)
    }

    func testManagedImagePreviewUsesDecodedNaturalAspectRatio() throws {
        struct PreviewCase {
            let name: String
            let pixelWidth: Int
            let pixelHeight: Int
            let textWidth: CGFloat
        }

        let cases = [
            PreviewCase(
                name: "panoramic",
                pixelWidth: 100,
                pixelHeight: 5,
                textWidth: 700
            ),
            PreviewCase(
                name: "portrait",
                pixelWidth: 20,
                pixelHeight: 40,
                textWidth: 320
            ),
            PreviewCase(
                name: "square",
                pixelWidth: 20,
                pixelHeight: 20,
                textWidth: 360
            ),
        ]

        for previewCase in cases {
            let rootURL = makeTemporaryImageRoot()
            defer { try? FileManager.default.removeItem(at: rootURL) }
            let store = NoteImageStore(rootURL: rootURL)
            let asset = try store.importImage(
                data: makePNGData(
                    width: previewCase.pixelWidth,
                    height: previewCase.pixelHeight
                )
            )
            let document = makeImageDocument(
                rootURL: rootURL,
                stableKey: "natural-ratio-\(previewCase.name)"
            )
            let identity = MarkdownEditorDocumentIdentity(document: document)
            let harness = makeHarness(
                text: asset.markdown,
                textWidth: previewCase.textWidth,
                viewportHeight: 900,
                documentIdentity: identity,
                imageConfiguration: EditorImageConfiguration(
                    documentIdentity: identity,
                    store: store,
                    isEnabled: true
                )
            )
            let textView = harness.textView
            let match = try XCTUnwrap(MarkdownImage.matches(in: textView.string).first)

            prepareForPixelRendering(harness)
            _ = renderedPixels(of: textView)

            let expectedRatio = CGFloat(previewCase.pixelHeight)
                / CGFloat(previewCase.pixelWidth)
            XCTAssertTrue(
                waitUntil {
                    if let textContainer = textView.textContainer {
                        textView.layoutManager?.ensureLayout(for: textContainer)
                    }
                    guard let rect = textView.managedImagePreviewRect(
                        atUTF16Offset: match.tokenRange.location
                    ) else { return false }
                    return abs(rect.height - rect.width * expectedRatio) < 0.5
                },
                "decoded preview did not adopt the \(previewCase.name) aspect ratio"
            )

            let previewRect = try XCTUnwrap(
                textView.managedImagePreviewRect(
                    atUTF16Offset: match.tokenRange.location
                )
            )
            XCTAssertEqual(
                previewRect.height,
                previewRect.width * expectedRatio,
                accuracy: 0.5,
                previewCase.name
            )
            if previewCase.name == "panoramic" {
                XCTAssertEqual(previewRect.width, 480, accuracy: 0.1)
                XCTAssertLessThan(previewRect.height, 60)
            }
            XCTAssertEqual(textView.string, asset.markdown)
        }
    }

    func testManagedImageLayoutRetainsNaturalRatioAfterBitmapCacheEviction() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let assets = try (0...64).map { index in
            try store.importImage(
                data: makePNGData(width: 100 + index, height: 5)
            )
        }
        let text = assets.map(\.markdown).joined(separator: "\n")
        let document = makeImageDocument(
            rootURL: rootURL,
            stableKey: "preview-bitmap-eviction"
        )
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let harness = makeHarness(
            text: text,
            textWidth: 700,
            viewportHeight: 900,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let textView = harness.textView
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let matches = MarkdownImage.matches(in: text)
        XCTAssertEqual(matches.count, 65)

        layoutManager.ensureLayout(for: textContainer)
        let initialUsedRect = layoutManager.usedRect(for: textContainer)
        textView.setFrameSize(
            NSSize(
                width: textView.frame.width,
                height: max(textView.frame.height, ceil(initialUsedRect.maxY + 24))
            )
        )

        for (index, pair) in zip(matches, assets).enumerated() {
            let (match, asset) = pair
            layoutManager.ensureLayout(for: textContainer)
            let placeholderRect = try XCTUnwrap(
                textView.managedImagePreviewRect(
                    atUTF16Offset: match.tokenRange.location
                )
            )
            cacheDisplayOnly(
                of: textView,
                in: placeholderRect.insetBy(dx: -2, dy: -2)
            )

            let expectedRatio = CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth)
            XCTAssertTrue(
                waitUntil {
                    layoutManager.ensureLayout(for: textContainer)
                    guard let rect = textView.managedImagePreviewRect(
                        atUTF16Offset: match.tokenRange.location
                    ) else { return false }
                    return abs(rect.height - rect.width * expectedRatio) < 0.5
                },
                "image \(index) did not finish decoding at its natural aspect ratio"
            )
        }

        layoutManager.ensureLayout(for: textContainer)
        for (index, pair) in zip(matches, assets).enumerated() {
            let (match, asset) = pair
            let rect = try XCTUnwrap(
                textView.managedImagePreviewRect(
                    atUTF16Offset: match.tokenRange.location
                )
            )
            let expectedHeight = rect.width
                * CGFloat(asset.pixelHeight)
                / CGFloat(asset.pixelWidth)
            XCTAssertEqual(
                rect.height,
                expectedHeight,
                accuracy: 0.5,
                "image \(index) reverted to the placeholder ratio after bitmap eviction"
            )
        }
        XCTAssertEqual(textView.string, text)
    }

    func testManagedImageAssetRemainsResolvedWhileMarkedTextAboveMovesToken() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let asset = try store.importImage(data: makePNGData(width: 32, height: 16))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "preview-ime")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let original = "图片上方\n\(asset.markdown)\n图片下方"
        let harness = makeHarness(
            text: original,
            textWidth: 360,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let textView = harness.textView
        textView.refreshChecklistPresentation(forceLayout: true)
        let initialMatch = try XCTUnwrap(MarkdownImage.matches(in: original).first)
        let expectedURL = try XCTUnwrap(
            store.resolveManagedAsset(
                markdownDestination: initialMatch.markdownDestination,
                relativeTo: document.fileURL
            )
        )
        XCTAssertEqual(
            textView.managedImageResolvedAssetURL(
                atUTF16Offset: initialMatch.tokenRange.location
            ),
            expectedURL
        )

        let insertionRange = NSRange(location: 2, length: 0)
        textView.setSelectedRange(insertionRange)
        textView.setMarkedText(
            NSAttributedString(string: "ce"),
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: insertionRange
        )
        XCTAssertTrue(textView.hasMarkedText())

        var movedMatch = try XCTUnwrap(MarkdownImage.matches(in: textView.string).first)
        XCTAssertGreaterThan(
            movedMatch.tokenRange.location,
            initialMatch.tokenRange.location
        )
        XCTAssertEqual(textView.managedImageMatches, [movedMatch])
        XCTAssertEqual(
            textView.managedImageResolvedAssetURL(
                atUTF16Offset: movedMatch.tokenRange.location
            ),
            expectedURL
        )

        textView.setMarkedText(
            NSAttributedString(string: "ceshi"),
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        movedMatch = try XCTUnwrap(MarkdownImage.matches(in: textView.string).first)
        XCTAssertEqual(textView.managedImageMatches, [movedMatch])
        XCTAssertEqual(
            textView.managedImageResolvedAssetURL(
                atUTF16Offset: movedMatch.tokenRange.location
            ),
            expectedURL
        )

        textView.unmarkText()
        movedMatch = try XCTUnwrap(MarkdownImage.matches(in: textView.string).first)
        XCTAssertEqual(MarkdownImage.matches(in: textView.string).count, 1)
        XCTAssertEqual(
            textView.managedImageResolvedAssetURL(
                atUTF16Offset: movedMatch.tokenRange.location
            ),
            expectedURL
        )
    }

    func testImagePasteCommitsThenInsertsOneUndoableMarkdownEdit() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let document = makeImageDocument(rootURL: rootURL, stableKey: "paste")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let original = "前\n后"
        let bindingProbe = TextBindingProbe(original)
        let errorProbe = ImageErrorProbe()
        let harness = makeHarness(
            text: original,
            textWidth: 320,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true,
                reportError: { errorProbe.messages.append($0) }
            ),
            textBinding: Binding(
                get: { bindingProbe.value },
                set: { bindingProbe.record($0) }
            )
        )
        let textView = harness.textView
        let insertionRange = NSRange(location: 2, length: 0)
        textView.setSelectedRange(insertionRange)
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.removeAllActions()
        bindingProbe.reset(to: original)
        let pboard = makePasteboard()
        defer { pboard.releaseGlobally() }
        pboard.declareTypes([.png], owner: nil)
        pboard.setData(makePNGData(width: 20, height: 10), forType: .png)

        XCTAssertTrue(
            textView.pasteContents(from: pboard)
        )
        XCTAssertTrue(
            waitUntil {
                !MarkdownImage.matches(in: bindingProbe.value).isEmpty
            }
        )

        XCTAssertTrue(errorProbe.messages.isEmpty)
        XCTAssertEqual(textView.string, bindingProbe.value)
        let match = try XCTUnwrap(MarkdownImage.matches(in: bindingProbe.value).first)
        let resolvedURL = try XCTUnwrap(
            store.resolveManagedAsset(
                markdownDestination: match.markdownDestination,
                relativeTo: document.fileURL
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedURL.path))
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        runMainLoop()
        XCTAssertEqual(textView.string, original)
        XCTAssertEqual(bindingProbe.value, original)
        XCTAssertTrue(undoManager.canRedo)

        undoManager.redo()
        runMainLoop()
        XCTAssertEqual(textView.string, bindingProbe.value)
        XCTAssertEqual(MarkdownImage.matches(in: bindingProbe.value).count, 1)
    }

    func testImagePasteAtDocumentEndLeavesCaretOnFollowingLine() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let document = makeImageDocument(rootURL: rootURL, stableKey: "paste-at-end")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let harness = makeHarness(
            text: "",
            textWidth: 320,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let textView = harness.textView
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.removeAllActions()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let pboard = makePasteboard()
        defer { pboard.releaseGlobally() }
        pboard.declareTypes([.png], owner: nil)
        pboard.setData(makePNGData(width: 20, height: 10), forType: .png)

        XCTAssertTrue(textView.pasteContents(from: pboard))
        XCTAssertTrue(waitUntil {
            MarkdownImage.matches(in: textView.string).count == 1
                && textView.string.hasSuffix("\n")
        })

        let pastedText = textView.string
        // The image import completes on the main queue. Let AppKit close that
        // event's undo group before simulating the user's next typing event.
        runMainLoop()
        XCTAssertEqual(textView.selectedRange(), NSRange(
            location: (pastedText as NSString).length,
            length: 0
        ))
        textView.insertText("测试", replacementRange: textView.selectedRange())
        XCTAssertEqual(MarkdownImage.matches(in: textView.string).count, 1)
        XCTAssertTrue(textView.string.hasSuffix("\n测试"))

        undoManager.undo()
        XCTAssertEqual(textView.string, pastedText)
        undoManager.undo()
        XCTAssertEqual(textView.string, "")
    }

    func testClickImmediatelyBelowImageStartsFollowingEmptyLine() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let asset = try store.importImage(data: makePNGData(width: 20, height: 10))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "click-below-image")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let original = asset.markdown + "\n"
        let harness = makeHarness(
            text: original,
            textWidth: 320,
            viewportHeight: 360,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let textView = harness.textView
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let match = try XCTUnwrap(MarkdownImage.matches(in: original).first)
        let previewRect = try XCTUnwrap(
            textView.managedImagePreviewRect(
                atUTF16Offset: match.tokenRange.location
            )
        )
        var imageLineGlyphRange = NSRange()
        var newlineLineGlyphRange = NSRange()
        let imageGlyph = layoutManager.glyphIndexForCharacter(
            at: match.tokenRange.location
        )
        let newlineGlyph = layoutManager.glyphIndexForCharacter(
            at: NSMaxRange(match.tokenRange)
        )
        _ = layoutManager.lineFragmentRect(
            forGlyphAt: imageGlyph,
            effectiveRange: &imageLineGlyphRange
        )
        _ = layoutManager.lineFragmentRect(
            forGlyphAt: newlineGlyph,
            effectiveRange: &newlineLineGlyphRange
        )
        XCTAssertEqual(imageLineGlyphRange, newlineLineGlyphRange)

        let clickPoint = NSPoint(x: previewRect.midX, y: previewRect.maxY + 3)
        try clickTextView(at: clickPoint, in: harness)

        let expectedInsertion = NSRange(
            location: (original as NSString).length,
            length: 0
        )
        XCTAssertEqual(textView.selectedRange(), expectedInsertion)
        textView.insertText("测试", replacementRange: textView.selectedRange())
        XCTAssertEqual(textView.string, asset.markdown + "\n测试")
        XCTAssertEqual(MarkdownImage.matches(in: textView.string).count, 1)
    }

    func testClickBetweenAdjacentImagesInsertsTextWithoutBreakingEitherPreview() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let first = try store.importImage(data: makePNGData(width: 20, height: 10))
        let second = try store.importImage(data: makePNGData(width: 18, height: 12))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "click-between-images")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let original = first.markdown + "\n" + second.markdown + "\n"
        let harness = makeHarness(
            text: original,
            textWidth: 320,
            viewportHeight: 560,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let firstMatch = try XCTUnwrap(MarkdownImage.matches(in: original).first)
        let firstPreviewRect = try XCTUnwrap(
            harness.textView.managedImagePreviewRect(
                atUTF16Offset: firstMatch.tokenRange.location
            )
        )
        try clickTextView(
            at: NSPoint(x: firstPreviewRect.midX, y: firstPreviewRect.maxY + 3),
            in: harness
        )

        harness.textView.insertText(
            "中间",
            replacementRange: harness.textView.selectedRange()
        )

        XCTAssertEqual(
            harness.textView.string,
            first.markdown + "\n中间\n" + second.markdown + "\n"
        )
        XCTAssertEqual(MarkdownImage.matches(in: harness.textView.string).count, 2)
    }

    func testClickBelowImageWithFollowingTextStartsThatTextLine() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let asset = try store.importImage(data: makePNGData(width: 20, height: 10))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "click-before-image-text")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let original = asset.markdown + "\n你 df测试"
        let harness = makeHarness(
            text: original,
            textWidth: 320,
            viewportHeight: 360,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let textView = harness.textView
        let match = try XCTUnwrap(MarkdownImage.matches(in: original).first)
        let previewRect = try XCTUnwrap(
            textView.managedImagePreviewRect(
                atUTF16Offset: match.tokenRange.location
            )
        )
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.removeAllActions()
        try clickTextView(
            at: NSPoint(x: previewRect.midX, y: previewRect.maxY + 3),
            in: harness
        )

        let followingLineStart = NSMaxRange(match.lineRange)
        XCTAssertEqual(
            textView.selectedRange(),
            NSRange(location: followingLineStart, length: 0)
        )
        textView.insertText("新", replacementRange: textView.selectedRange())
        XCTAssertEqual(textView.string, asset.markdown + "\n新你 df测试")
        XCTAssertEqual(MarkdownImage.matches(in: textView.string).count, 1)
        undoManager.undo()
        XCTAssertEqual(textView.string, original)
    }

    func testCommittedTextAtLegacyImageEOFStartsOnNewLineAtomically() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let asset = try store.importImage(data: makePNGData(width: 20, height: 10))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "legacy-image-eof")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let harness = makeHarness(
            text: asset.markdown,
            textWidth: 320,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let textView = harness.textView
        let tokenEnd = (asset.markdown as NSString).length
        textView.setSelectedRange(NSRange(location: tokenEnd, length: 0))
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.removeAllActions()

        textView.insertText("测试", replacementRange: textView.selectedRange())

        XCTAssertEqual(textView.string, asset.markdown + "\n测试")
        XCTAssertEqual(MarkdownImage.matches(in: textView.string).count, 1)
        undoManager.undo()
        XCTAssertEqual(textView.string, asset.markdown)
        XCTAssertTrue(undoManager.canRedo)
        undoManager.redo()
        XCTAssertEqual(textView.string, asset.markdown + "\n测试")
    }

    func testMarkedTextAtLegacyImageEOFKeepsPreviewAndUndoesAtomically() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let asset = try store.importImage(data: makePNGData(width: 20, height: 10))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "legacy-image-ime")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let harness = makeHarness(
            text: asset.markdown,
            textWidth: 320,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let textView = harness.textView
        let tokenEnd = (asset.markdown as NSString).length
        textView.setSelectedRange(NSRange(location: tokenEnd, length: 0))
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.removeAllActions()

        textView.setMarkedText(
            NSAttributedString(string: "ce"),
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: textView.selectedRange()
        )
        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(textView.string, asset.markdown + "\nce")
        XCTAssertEqual(MarkdownImage.matches(in: textView.string).count, 1)

        textView.setMarkedText(
            NSAttributedString(string: "ceshi"),
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        textView.insertText(
            "测试",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(textView.string, asset.markdown + "\n测试")
        XCTAssertEqual(MarkdownImage.matches(in: textView.string).count, 1)
        undoManager.undo()
        XCTAssertEqual(textView.string, asset.markdown)
    }

    func testLegacyImageEOFMarkedTextCannotWriteAcrossDocumentIdentity() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let asset = try store.importImage(data: makePNGData(width: 20, height: 10))
        let firstDocument = makeImageDocument(rootURL: rootURL, stableKey: "legacy-ime-a")
        let firstIdentity = MarkdownEditorDocumentIdentity(document: firstDocument)
        let bindingProbe = TextBindingProbe(asset.markdown)
        let harness = makeHarness(
            text: asset.markdown,
            textWidth: 320,
            documentIdentity: firstIdentity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: firstIdentity,
                store: store,
                isEnabled: true
            ),
            textBinding: Binding(
                get: { bindingProbe.value },
                set: { bindingProbe.record($0) }
            )
        )
        let textView = harness.textView
        let tokenEnd = (asset.markdown as NSString).length
        textView.setSelectedRange(NSRange(location: tokenEnd, length: 0))
        textView.setMarkedText(
            "ceshi",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: textView.selectedRange()
        )
        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertEqual(MarkdownImage.matches(in: textView.string).count, 1)

        let nextText = "另一份笔记"
        bindingProbe.reset(to: nextText)
        let nextDocument = makeImageDocument(rootURL: rootURL, stableKey: "legacy-ime-b")
        XCTAssertTrue(
            harness.coordinator.transitionDocumentIfNeeded(
                to: MarkdownEditorDocumentIdentity(document: nextDocument),
                text: nextText,
                controller: harness.controller,
                in: textView
            )
        )

        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(textView.string, nextText)
        XCTAssertEqual(bindingProbe.value, nextText)
        XCTAssertTrue(bindingProbe.recordedWrites.isEmpty)
    }

    func testTextAndMarkedTextAtImageEndMoveAfterExistingCRLF() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let asset = try store.importImage(data: makePNGData(width: 20, height: 10))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "image-crlf")
        let identity = MarkdownEditorDocumentIdentity(document: document)

        func makeImageHarness() -> EditorHarness {
            makeHarness(
                text: asset.markdown + "\r\n",
                textWidth: 320,
                documentIdentity: identity,
                imageConfiguration: EditorImageConfiguration(
                    documentIdentity: identity,
                    store: store,
                    isEnabled: true
                )
            )
        }

        let committedHarness = makeImageHarness()
        let tokenEnd = (asset.markdown as NSString).length
        committedHarness.textView.setSelectedRange(NSRange(location: tokenEnd, length: 0))
        committedHarness.textView.insertText(
            "测试",
            replacementRange: committedHarness.textView.selectedRange()
        )
        XCTAssertEqual(committedHarness.textView.string, asset.markdown + "\r\n测试")
        XCTAssertEqual(MarkdownImage.matches(in: committedHarness.textView.string).count, 1)

        let markedHarness = makeImageHarness()
        markedHarness.textView.setSelectedRange(NSRange(location: tokenEnd, length: 0))
        markedHarness.textView.setMarkedText(
            "ceshi",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: markedHarness.textView.selectedRange()
        )
        XCTAssertTrue(markedHarness.textView.hasMarkedText())
        XCTAssertEqual(markedHarness.textView.string, asset.markdown + "\r\nceshi")
        XCTAssertEqual(MarkdownImage.matches(in: markedHarness.textView.string).count, 1)
        markedHarness.textView.setMarkedText(
            "ceshizhong",
            selectedRange: NSRange(location: 10, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        markedHarness.textView.unmarkText()
        XCTAssertEqual(markedHarness.textView.string, asset.markdown + "\r\nceshizhong")
        XCTAssertEqual(MarkdownImage.matches(in: markedHarness.textView.string).count, 1)
    }

    func testPastingSecondImageAtFirstTokenEndKeepsTwoBlockImageLines() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let firstAsset = try store.importImage(data: makePNGData(width: 20, height: 10))
        let original = firstAsset.markdown + "\n"
        let document = makeImageDocument(rootURL: rootURL, stableKey: "two-images")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let harness = makeHarness(
            text: original,
            textWidth: 320,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let tokenEnd = (firstAsset.markdown as NSString).length
        harness.textView.setSelectedRange(NSRange(location: tokenEnd, length: 0))
        let pboard = makePasteboard()
        defer { pboard.releaseGlobally() }
        pboard.declareTypes([.png], owner: nil)
        pboard.setData(makePNGData(width: 18, height: 12), forType: .png)

        XCTAssertTrue(harness.textView.pasteContents(from: pboard))
        XCTAssertTrue(waitUntil {
            MarkdownImage.matches(in: harness.textView.string).count == 2
        })

        XCTAssertEqual(harness.textView.string.components(separatedBy: "\n").count, 3)
        XCTAssertTrue(harness.textView.string.hasSuffix("\n"))
    }

    func testTextAndMarkedTextBetweenAdjacentImagesKeepBothPreviews() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let first = try store.importImage(data: makePNGData(width: 20, height: 10))
        let second = try store.importImage(data: makePNGData(width: 18, height: 12))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "adjacent-images")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let original = first.markdown + "\r\n" + second.markdown + "\r\n"
        let expectedCommitted = first.markdown
            + "\r\n测试\r\n"
            + second.markdown
            + "\r\n"

        func makeImageHarness() -> EditorHarness {
            makeHarness(
                text: original,
                textWidth: 320,
                documentIdentity: identity,
                imageConfiguration: EditorImageConfiguration(
                    documentIdentity: identity,
                    store: store,
                    isEnabled: true
                )
            )
        }

        let tokenEnd = (first.markdown as NSString).length
        let committedHarness = makeImageHarness()
        let committedUndo = try XCTUnwrap(committedHarness.textView.undoManager)
        committedUndo.removeAllActions()
        committedHarness.textView.setSelectedRange(NSRange(location: tokenEnd, length: 0))
        committedHarness.textView.insertText(
            "测试",
            replacementRange: committedHarness.textView.selectedRange()
        )
        XCTAssertEqual(committedHarness.textView.string, expectedCommitted)
        XCTAssertEqual(MarkdownImage.matches(in: committedHarness.textView.string).count, 2)
        committedUndo.undo()
        XCTAssertEqual(committedHarness.textView.string, original)

        let markedHarness = makeImageHarness()
        markedHarness.textView.setSelectedRange(NSRange(location: tokenEnd, length: 0))
        markedHarness.textView.setMarkedText(
            "ce",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: markedHarness.textView.selectedRange()
        )
        XCTAssertTrue(markedHarness.textView.hasMarkedText())
        XCTAssertEqual(MarkdownImage.matches(in: markedHarness.textView.string).count, 2)
        markedHarness.textView.setMarkedText(
            NSAttributedString(string: "ceshi"),
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        markedHarness.textView.unmarkText()
        XCTAssertEqual(
            markedHarness.textView.string,
            first.markdown + "\r\nceshi\r\n" + second.markdown + "\r\n"
        )
        XCTAssertEqual(MarkdownImage.matches(in: markedHarness.textView.string).count, 2)
        XCTAssertEqual(
            markedHarness.textView.selectedRange(),
            NSRange(
                location: ((first.markdown + "\r\nceshi") as NSString).length,
                length: 0
            )
        )
        markedHarness.textView.insertText(
            "后",
            replacementRange: markedHarness.textView.selectedRange()
        )
        XCTAssertEqual(
            markedHarness.textView.string,
            first.markdown + "\r\nceshi后\r\n" + second.markdown + "\r\n"
        )
        XCTAssertEqual(MarkdownImage.matches(in: markedHarness.textView.string).count, 2)

        let finalCommitHarness = makeImageHarness()
        let finalCommitUndo = try XCTUnwrap(finalCommitHarness.textView.undoManager)
        finalCommitUndo.removeAllActions()
        finalCommitHarness.textView.setSelectedRange(
            NSRange(location: tokenEnd, length: 0)
        )
        finalCommitHarness.textView.setMarkedText(
            "ce",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: finalCommitHarness.textView.selectedRange()
        )
        finalCommitHarness.textView.setMarkedText(
            NSAttributedString(string: "ceshi"),
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        finalCommitHarness.textView.insertText(
            "测试",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let finalCommittedText = first.markdown
            + "\r\n测试\r\n"
            + second.markdown
            + "\r\n"
        XCTAssertEqual(finalCommitHarness.textView.string, finalCommittedText)
        XCTAssertEqual(
            finalCommitHarness.textView.selectedRange(),
            NSRange(
                location: ((first.markdown + "\r\n测试") as NSString).length,
                length: 0
            )
        )
        XCTAssertEqual(MarkdownImage.matches(in: finalCommittedText).count, 2)
        finalCommitUndo.undo()
        XCTAssertEqual(finalCommitHarness.textView.string, original)

        let continuationHarness = makeImageHarness()
        continuationHarness.textView.setSelectedRange(
            NSRange(location: tokenEnd, length: 0)
        )
        continuationHarness.textView.setMarkedText(
            "ceshi",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: continuationHarness.textView.selectedRange()
        )
        continuationHarness.textView.insertText(
            "测试",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        continuationHarness.textView.insertText(
            "后",
            replacementRange: continuationHarness.textView.selectedRange()
        )
        XCTAssertEqual(
            continuationHarness.textView.string,
            first.markdown + "\r\n测试后\r\n" + second.markdown + "\r\n"
        )
        XCTAssertEqual(
            MarkdownImage.matches(in: continuationHarness.textView.string).count,
            2
        )
    }

    func testCancellingImageBoundaryCompositionLeavesMarkdownUnchanged() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let first = try store.importImage(data: makePNGData(width: 20, height: 10))
        let second = try store.importImage(data: makePNGData(width: 18, height: 12))
        let document = makeImageDocument(rootURL: rootURL, stableKey: "cancel-image-ime")
        let identity = MarkdownEditorDocumentIdentity(document: document)

        func makeImageHarness(_ text: String) -> EditorHarness {
            makeHarness(
                text: text,
                textWidth: 320,
                documentIdentity: identity,
                imageConfiguration: EditorImageConfiguration(
                    documentIdentity: identity,
                    store: store,
                    isEnabled: true
                )
            )
        }

        let legacyOriginal = first.markdown
        let legacyHarness = makeImageHarness(legacyOriginal)
        let legacyEnd = (legacyOriginal as NSString).length
        legacyHarness.textView.setSelectedRange(NSRange(location: legacyEnd, length: 0))
        legacyHarness.textView.setMarkedText(
            "ce",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: legacyHarness.textView.selectedRange()
        )
        legacyHarness.textView.setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertFalse(legacyHarness.textView.hasMarkedText())
        XCTAssertEqual(legacyHarness.textView.string, legacyOriginal)
        XCTAssertEqual(MarkdownImage.matches(in: legacyHarness.textView.string).count, 1)

        let adjacentOriginal = first.markdown + "\r\n" + second.markdown + "\r\n"
        let adjacentHarness = makeImageHarness(adjacentOriginal)
        adjacentHarness.textView.setSelectedRange(NSRange(location: legacyEnd, length: 0))
        adjacentHarness.textView.setMarkedText(
            "ce",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: adjacentHarness.textView.selectedRange()
        )
        adjacentHarness.textView.setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertFalse(adjacentHarness.textView.hasMarkedText())
        XCTAssertEqual(adjacentHarness.textView.string, adjacentOriginal)
        XCTAssertEqual(MarkdownImage.matches(in: adjacentHarness.textView.string).count, 2)
    }

    func testReadOnlyAndMarkedTextRejectImagesBeforeAnyAssetWrite() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let document = makeImageDocument(rootURL: rootURL, stableKey: "readonly")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let original = "只读正文"
        let bindingProbe = TextBindingProbe(original)
        let harness = makeHarness(
            text: original,
            textWidth: 320,
            isEditable: false,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: false
            ),
            textBinding: Binding(
                get: { bindingProbe.value },
                set: { bindingProbe.record($0) }
            )
        )
        let pboard = makePasteboard()
        defer { pboard.releaseGlobally() }
        pboard.declareTypes([.png], owner: nil)
        pboard.setData(makePNGData(width: 12, height: 12), forType: .png)

        XCTAssertTrue(
            harness.textView.importImages(
                from: pboard,
                replacementRange: NSRange(location: 0, length: 0),
                requiresSelectionMatch: true
            )
        )
        runMainLoop(for: 0.1)
        XCTAssertEqual(harness.textView.string, original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetRootURL.path))

        harness.textView.isEditable = true
        harness.textView.imageConfiguration = EditorImageConfiguration(
            documentIdentity: identity,
            store: store,
            isEnabled: true
        )
        let end = (harness.textView.string as NSString).length
        harness.textView.setSelectedRange(NSRange(location: end, length: 0))
        harness.textView.setMarkedText(
            "pin",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: end, length: 0)
        )
        XCTAssertTrue(harness.textView.hasMarkedText())
        XCTAssertTrue(
            harness.textView.importImages(
                from: pboard,
                replacementRange: harness.textView.selectedRange(),
                requiresSelectionMatch: true
            )
        )
        runMainLoop(for: 0.1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetRootURL.path))
    }

    func testImageImportCompletionIsDiscardedAfterIdentityChangeAndTextFilesFallThrough() {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let firstDocument = makeImageDocument(rootURL: rootURL, stableKey: "first")
        let firstIdentity = MarkdownEditorDocumentIdentity(document: firstDocument)
        let harness = makeHarness(
            text: "原文",
            textWidth: 320,
            documentIdentity: firstIdentity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: firstIdentity,
                store: store,
                isEnabled: true
            )
        )
        let imagePasteboard = makePasteboard()
        defer { imagePasteboard.releaseGlobally() }
        imagePasteboard.declareTypes([.png], owner: nil)
        imagePasteboard.setData(makePNGData(width: 1_000, height: 1_000), forType: .png)
        let range = NSRange(location: 0, length: 0)
        harness.textView.setSelectedRange(range)
        XCTAssertTrue(
            harness.textView.importImages(
                from: imagePasteboard,
                replacementRange: range,
                requiresSelectionMatch: true
            )
        )

        let secondDocument = makeImageDocument(rootURL: rootURL, stableKey: "second")
        harness.textView.imageConfiguration = EditorImageConfiguration(
            documentIdentity: MarkdownEditorDocumentIdentity(document: secondDocument),
            store: store,
            isEnabled: true
        )
        runMainLoop(for: 0.5)
        XCTAssertEqual(harness.textView.string, "原文")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetRootURL.path))

        let textFileURL = rootURL.appendingPathComponent("ordinary.txt")
        try? "普通文本".write(to: textFileURL, atomically: true, encoding: .utf8)
        let filePasteboard = makePasteboard()
        defer { filePasteboard.releaseGlobally() }
        filePasteboard.writeObjects([textFileURL as NSURL])
        XCTAssertFalse(
            harness.textView.importImages(
                from: filePasteboard,
                replacementRange: range,
                requiresSelectionMatch: true
            )
        )
    }

    func testOrdinaryPastePreservesMeaningfulTextWhenPasteboardAlsoContainsImage() {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let document = makeImageDocument(rootURL: rootURL, stableKey: "services-string")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let harness = makeHarness(
            text: "原文",
            textWidth: 320,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let pboard = makePasteboard()
        defer { pboard.releaseGlobally() }
        pboard.declareTypes([.string, .png], owner: nil)
        pboard.setString("服务文字", forType: .string)
        pboard.setData(makePNGData(width: 12, height: 12), forType: .png)
        let end = (harness.textView.string as NSString).length
        harness.textView.setSelectedRange(NSRange(location: end, length: 0))

        XCTAssertTrue(harness.textView.pasteContents(from: pboard))
        XCTAssertEqual(harness.textView.string, "原文服务文字")
        runMainLoop(for: 0.1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.assetRootURL.path))
    }

    func testOrdinaryPasteTreatsImageFileURLAndItsPathStringAsImage() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let document = makeImageDocument(rootURL: rootURL, stableKey: "file-url-paste")
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let harness = makeHarness(
            text: "",
            textWidth: 320,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        let sourceURL = rootURL.appendingPathComponent("screenshot.png")
        try makePNGData(width: 16, height: 9).write(to: sourceURL, options: .atomic)
        let pboard = makePasteboard()
        defer { pboard.releaseGlobally() }
        pboard.declareTypes([.fileURL, .string], owner: nil)
        pboard.setString(sourceURL.absoluteString, forType: .fileURL)
        pboard.setString(sourceURL.path, forType: .string)
        harness.textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(harness.textView.pasteContents(from: pboard))
        XCTAssertTrue(waitUntil {
            MarkdownImage.matches(in: harness.textView.string).count == 1
        })
        XCTAssertFalse(harness.textView.string.contains(sourceURL.path))
    }

    func testLargeNoteRefreshStaysResponsive() {
        let lines = (0..<1_000).map { index in
            if index < 300 {
                return "- [ ] 待办 \(index) 这是一条用来触发布局的较长文本内容。"
            }
            return "普通正文 \(index) 这是一条用来触发布局的较长文本内容。"
        }
        let text = lines.joined(separator: "\n")
        let harness = makeHarness(text: text, textWidth: 420)
        let textView = harness.textView

        let parseStart = CFAbsoluteTimeGetCurrent()
        let parsedMatches = MarkdownChecklist.checkboxMatches(in: textView.string)
        let parseMilliseconds = (CFAbsoluteTimeGetCurrent() - parseStart) * 1_000
        XCTAssertEqual(parsedMatches.count, 300)

        let refreshStart = CFAbsoluteTimeGetCurrent()
        textView.refreshChecklistPresentation(forceLayout: true)
        let refreshMilliseconds = (CFAbsoluteTimeGetCurrent() - refreshStart) * 1_000

        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        let inputStart = CFAbsoluteTimeGetCurrent()
        textView.insertText("字", replacementRange: NSRange(location: end, length: 0))
        let inputMilliseconds = (CFAbsoluteTimeGetCurrent() - inputStart) * 1_000
        XCTAssertLessThan(refreshMilliseconds, 1_000)
        XCTAssertLessThan(inputMilliseconds, 1_000)
        print(
            "TEXTKIT_BENCHMARK parse_ms=\(parseMilliseconds) "
                + "refresh_ms=\(refreshMilliseconds) input_ms=\(inputMilliseconds)"
        )
    }

    func testLargeNoteMarkedTextUpdatesStayResponsive() {
        let lines = (0..<1_000).map { index in
            if index < 300 {
                return "- [ ] 待办 \(index) 这是一条用来触发布局的较长文本内容。"
            }
            return "普通正文 \(index) 这是一条用来触发布局的较长文本内容。"
        }
        let text = lines.joined(separator: "\n")
        let harness = makeHarness(text: text, textWidth: 420)
        let textView = harness.textView
        let insertionLocation = (lines[0] as NSString).length
        textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))

        let lengths = Array(1...12) + Array((1...11).reversed())
        let updateStart = CFAbsoluteTimeGetCurrent()
        for (index, length) in lengths.enumerated() {
            let markedText = String(repeating: "n", count: length)
            textView.setMarkedText(
                markedText,
                selectedRange: NSRange(location: length, length: 0),
                replacementRange: index == 0
                    ? NSRange(location: insertionLocation, length: 0)
                    : NSRange(location: NSNotFound, length: 0)
            )
        }
        let updateMilliseconds = (CFAbsoluteTimeGetCurrent() - updateStart) * 1_000

        XCTAssertTrue(textView.hasMarkedText())
        XCTAssertLessThan(updateMilliseconds, 1_000)
        textView.unmarkText()
        print("TEXTKIT_IME_BENCHMARK updates_ms=\(updateMilliseconds)")
    }

    func testChecklistLayoutAcrossFontSpacingAndCompletionMatrix() throws {
        for fontSize in [CGFloat(12), 18, 24] {
            for isChecked in [false, true] {
                let baseLineHeight = try assertChecklistLayout(
                    fontSize: fontSize,
                    lineSpacing: 0,
                    isChecked: isChecked
                )
                for lineSpacing in [CGFloat(7), 12] {
                    let lineHeight = try assertChecklistLayout(
                        fontSize: fontSize,
                        lineSpacing: lineSpacing,
                        isChecked: isChecked
                    )
                    XCTAssertEqual(
                        lineHeight - baseLineHeight,
                        lineSpacing,
                        accuracy: 0.5,
                        "font=\(fontSize), spacing=\(lineSpacing), checked=\(isChecked)"
                    )
                }
            }
        }
    }

    func testChecklistWrappedLinesAlignWithContentForSpacesAndTabs() throws {
        let indents = ["", "  ", "\t", " \t", "\t\t"]

        for indent in indents {
            let text = indent
                + "- [ ] 这是一条足够长的待办内容，用来验证换行后仍然与首行正文对齐。"
            let harness = makeHarness(text: text, textWidth: 190)
            let textView = harness.textView
            let layoutManager = try XCTUnwrap(textView.layoutManager)
            let textContainer = try XCTUnwrap(textView.textContainer)
            let match = try XCTUnwrap(MarkdownChecklist.checkboxMatches(in: text).first)

            layoutManager.ensureLayout(for: textContainer)
            let firstContentGlyph = layoutManager.glyphIndexForCharacter(
                at: match.contentRange.location
            )
            var firstLineGlyphRange = NSRange()
            _ = layoutManager.lineFragmentRect(
                forGlyphAt: firstContentGlyph,
                effectiveRange: &firstLineGlyphRange
            )
            let continuationGlyph = NSMaxRange(firstLineGlyphRange)
            XCTAssertLessThan(
                continuationGlyph,
                layoutManager.numberOfGlyphs,
                "Test text must wrap for indent \(indent.debugDescription)"
            )

            let firstContentX = glyphX(
                firstContentGlyph,
                layoutManager: layoutManager
            )
            let continuationX = glyphX(
                continuationGlyph,
                layoutManager: layoutManager
            )
            XCTAssertEqual(
                continuationX,
                firstContentX,
                accuracy: 0.5,
                "Wrapped content should align for indent \(indent.debugDescription)"
            )

            let paragraphStyle = try XCTUnwrap(
                textView.textStorage?.attribute(
                    .paragraphStyle,
                    at: match.lineRange.location,
                    effectiveRange: nil
                ) as? NSParagraphStyle
            )
            XCTAssertEqual(paragraphStyle.firstLineHeadIndent, 0, accuracy: 0.001)
            XCTAssertEqual(
                paragraphStyle.headIndent + textContainer.lineFragmentPadding,
                firstContentX,
                accuracy: 0.5
            )
            XCTAssertEqual(paragraphStyle.lineSpacing, 0, accuracy: 0.001)
            XCTAssertEqual(textView.string, text)
        }
    }

    func testPresentationPreservesMarkdownSelectionScrollAndUndo() throws {
        let todo = "- [ ] 这是一条足够长的待办内容，需要在窄窗口中换行。"
        let text = ([todo] + (0..<50).map { "普通正文 \($0)" }).joined(separator: "\n")
        let harness = makeHarness(text: text, textWidth: 200, viewportHeight: 100)
        let textView = harness.textView
        let scrollView = harness.scrollView
        let undoManager = try XCTUnwrap(textView.undoManager)
        let selection = NSRange(location: 8, length: 7)
        textView.setSelectedRange(selection)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 80))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let scrollOrigin = scrollView.contentView.bounds.origin

        let undoProbe = UndoProbe()
        undoManager.removeAllActions()
        undoManager.registerUndo(withTarget: undoProbe) { target in
            target.didUndo = true
        }
        XCTAssertTrue(undoManager.canUndo)

        textView.refreshChecklistPresentation(forceLayout: true)

        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(textView.selectedRange(), selection)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, scrollOrigin.x, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, scrollOrigin.y, accuracy: 0.001)
        XCTAssertTrue(undoManager.canUndo)

        undoManager.undo()
        XCTAssertTrue(undoProbe.didUndo)
        XCTAssertEqual(textView.string, text)
    }

    func testPresentationWaitsUntilMarkedTextIsCommitted() throws {
        let text = "- [ ] 这是一条需要换行的待办内容。"
        let harness = makeHarness(text: text, textWidth: 170, refresh: false)
        let textView = harness.textView
        let sourceLength = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: sourceLength, length: 0))
        textView.setMarkedText(
            "拼",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: sourceLength, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())

        textView.refreshChecklistPresentation(forceLayout: true)

        let styleDuringComposition = textView.textStorage?.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle
        XCTAssertTrue(styleDuringComposition == nil || styleDuringComposition?.headIndent == 0)

        textView.unmarkText()
        XCTAssertFalse(textView.hasMarkedText())

        let styleAfterCommit = try XCTUnwrap(
            textView.textStorage?.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        XCTAssertGreaterThan(styleAfterCommit.headIndent, 0)
        XCTAssertEqual(textView.string, text + "拼")
    }

    func testMarkedTextKeepsFollowingCheckboxPrefixAtItsCurrentRange() throws {
        let firstTodo = "- [x] 第一条已完成待办"
        let secondTodo = "- [x] 第二条已完成待办"
        let text = firstTodo + "\n" + secondTodo
        let harness = makeHarness(text: text, textWidth: 260)
        let textView = harness.textView
        XCTAssertTrue(textView.textStorage?.delegate === textView)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        let baselineSecondMatch = try XCTUnwrap(
            MarkdownChecklist.checkboxMatches(in: text).last
        )
        layoutManager.ensureLayout(for: textContainer)
        let baselineContentGlyph = layoutManager.glyphIndexForCharacter(
            at: baselineSecondMatch.contentRange.location
        )
        let baselineContentX = glyphX(
            baselineContentGlyph,
            layoutManager: layoutManager
        )
        let baselineLineY = layoutManager.lineFragmentRect(
            forGlyphAt: baselineContentGlyph,
            effectiveRange: nil
        ).minY
        // Isolate the pre-layout NSTextStorage hook. The normal NSTextView
        // delegate refresh happens later and must not be required for stability.
        textView.delegate = nil
        defer { textView.delegate = harness.coordinator }
        let insertionLocation = (firstTodo as NSString).length
        textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))

        func assertCurrentFollowingCheckboxIsStable() throws {
            let matches = MarkdownChecklist.checkboxMatches(in: textView.string)
            XCTAssertEqual(matches.count, 2)
            let currentSecondMatch = matches[1]
            let currentSecondPrefix = currentSecondMatch.prefixRange
            layoutManager.ensureLayout(for: textContainer)
            let prefixGlyph = layoutManager.glyphIndexForCharacter(
                at: currentSecondPrefix.location
            )
            XCTAssertTrue(
                layoutManager.propertyForGlyph(at: prefixGlyph).contains(.controlCharacter),
                "The next checkbox must stay attached to its current Markdown prefix while composing"
            )

            for offset in 1..<currentSecondPrefix.length {
                let glyph = layoutManager.glyphIndexForCharacter(
                    at: currentSecondPrefix.location + offset
                )
                XCTAssertTrue(
                    layoutManager.propertyForGlyph(at: glyph).contains(.null),
                    "Only the synthetic checkbox width should remain visible"
                )
            }

            let contentGlyph = layoutManager.glyphIndexForCharacter(
                at: currentSecondMatch.contentRange.location
            )
            XCTAssertEqual(
                glyphX(contentGlyph, layoutManager: layoutManager),
                baselineContentX,
                accuracy: 0.5
            )
            XCTAssertEqual(
                layoutManager.lineFragmentRect(
                    forGlyphAt: contentGlyph,
                    effectiveRange: nil
                ).minY,
                baselineLineY,
                accuracy: 0.5
            )
        }

        textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: insertionLocation, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        try assertCurrentFollowingCheckboxIsStable()

        textView.setMarkedText(
            NSAttributedString(string: "nihcw"),
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        try assertCurrentFollowingCheckboxIsStable()

        textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        try assertCurrentFollowingCheckboxIsStable()

        let finalMarkedText = "nihcwma"
        textView.setMarkedText(
            finalMarkedText,
            selectedRange: NSRange(location: 7, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        try assertCurrentFollowingCheckboxIsStable()

        textView.unmarkText()
        XCTAssertEqual(textView.string, firstTodo + finalMarkedText + "\n" + secondTodo)
    }

    func testRemovingTodoRestoresOrdinaryParagraphIndent() throws {
        let harness = makeHarness(
            text: "- [ ] 需要变回普通文本的长待办内容。",
            textWidth: 170
        )
        let textView = harness.textView
        let originalStyle = try XCTUnwrap(
            textView.textStorage?.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        XCTAssertGreaterThan(originalStyle.headIndent, 0)

        let ordinaryText = "需要变回普通文本的长内容。"
        textView.string = ordinaryText
        textView.refreshChecklistPresentation(forceLayout: true)

        let ordinaryStyle = try XCTUnwrap(
            textView.textStorage?.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        XCTAssertEqual(ordinaryStyle.firstLineHeadIndent, 0, accuracy: 0.001)
        XCTAssertEqual(ordinaryStyle.headIndent, 0, accuracy: 0.001)
        XCTAssertEqual(textView.string, ordinaryText)
    }

    func testTodoSelectionStateIgnoresBlankLinesLikeToggleAction() {
        let allTodos = "- [ ] 第一项\n\n- [x] 第二项"
        let allTodosView = makeHarness(text: allTodos, textWidth: 420).textView
        allTodosView.setSelectedRange(
            NSRange(location: 0, length: (allTodos as NSString).length)
        )
        XCTAssertTrue(allTodosView.selectionIsEntirelyTodo)

        let mixed = "- [ ] 第一项\n\n普通文字"
        let mixedView = makeHarness(text: mixed, textWidth: 420).textView
        mixedView.setSelectedRange(
            NSRange(location: 0, length: (mixed as NSString).length)
        )
        XCTAssertFalse(mixedView.selectionIsEntirelyTodo)
    }

    func testDeleteBackwardRemovesTodoPrefixAsOneUndoableEdit() throws {
        let original = "  - [ ] 新待办"
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        let match = try XCTUnwrap(MarkdownChecklist.checkboxMatches(in: original).first)
        textView.setSelectedRange(
            NSRange(location: match.contentRange.location, length: 0)
        )

        textView.deleteBackward(nil)

        XCTAssertEqual(textView.string, "  新待办")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertEqual(MarkdownChecklist.progress(in: textView.string).total, 0)

        XCTAssertTrue(textView.undoManager?.canUndo == true)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, original)

        XCTAssertTrue(textView.undoManager?.canRedo == true)
        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "  新待办")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testReturnThenDeleteBackwardExitsFreshTodoInOneStep() {
        let original = "- [ ] 第一项"
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        textView.setSelectedRange(
            NSRange(location: (original as NSString).length, length: 0)
        )

        textView.insertNewline(nil)
        XCTAssertEqual(textView.string, original + "\n- [ ] ")

        textView.deleteBackward(nil)
        XCTAssertEqual(textView.string, original + "\n")
        XCTAssertEqual(
            textView.selectedRange(),
            NSRange(location: (original as NSString).length + 1, length: 0)
        )

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, original)
    }

    func testReturnBeforeTrailingSpacesCreatesCleanTodoThatDeletesInOneStep() {
        let original = "- [ ] 第一项  "
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        let visualLineEnd = NSMaxRange((original as NSString).range(of: "第一项"))
        textView.setSelectedRange(NSRange(location: visualLineEnd, length: 0))

        textView.insertNewline(nil)
        XCTAssertEqual(textView.string, original + "\n- [ ] ")

        textView.deleteBackward(nil)
        XCTAssertEqual(textView.string, original + "\n")
        XCTAssertEqual(MarkdownChecklist.progress(in: textView.string).total, 1)
    }

    func testDeleteBackwardFromCollapsedPrefixCaretRemovesEmptyTodo() throws {
        let original = "- [ ]  "
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        let match = try XCTUnwrap(MarkdownChecklist.checkboxMatches(in: original).first)
        textView.setSelectedRange(
            NSRange(location: match.prefixRange.location + 1, length: 0)
        )

        textView.deleteBackward(nil)

        XCTAssertEqual(textView.string, "")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, original)
    }

    func testDeleteBackwardWithSelectionUsesNormalSelectionDeletion() throws {
        let original = "- [ ] 正文"
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        let match = try XCTUnwrap(MarkdownChecklist.checkboxMatches(in: original).first)
        textView.setSelectedRange(match.contentRange)

        textView.deleteBackward(nil)

        XCTAssertEqual(textView.string, "- [ ] ")
        XCTAssertEqual(MarkdownChecklist.progress(in: textView.string).total, 1)
    }

    func testDeleteBackwardDuringMarkedTextDoesNotRemoveTodoPrefix() throws {
        let original = "- [ ] "
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        let match = try XCTUnwrap(MarkdownChecklist.checkboxMatches(in: original).first)
        textView.setSelectedRange(
            NSRange(location: match.contentRange.location, length: 0)
        )
        textView.setMarkedText(
            "pin",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: match.contentRange.location, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())

        textView.deleteBackward(nil)

        XCTAssertTrue(textView.string.hasPrefix("- [ ] "))
        XCTAssertEqual(MarkdownChecklist.progress(in: textView.string).total, 1)
    }

    func testCycleTodoStateAdvancesExactlyOneStatePerInvocationAndIsUndoable() {
        let original = "写下下一步"
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        textView.setSelectedRange(
            NSRange(location: (original as NSString).length, length: 0)
        )

        textView.cycleTodoState()
        XCTAssertEqual(textView.string, "- [ ] 写下下一步")

        textView.cycleTodoState()
        XCTAssertEqual(textView.string, "- [x] 写下下一步")

        textView.cycleTodoState()
        XCTAssertEqual(textView.string, original)

        let undoHarness = makeHarness(text: original, textWidth: 420)
        let undoTextView = undoHarness.textView
        undoTextView.setSelectedRange(
            NSRange(location: (original as NSString).length, length: 0)
        )
        undoTextView.cycleTodoState()
        XCTAssertEqual(undoTextView.string, "- [ ] 写下下一步")
        XCTAssertTrue(undoTextView.undoManager?.canUndo == true)
        undoTextView.undoManager?.undo()
        XCTAssertEqual(undoTextView.string, original)
    }

    func testCycleTodoStateDoesNothingDuringMarkedTextComposition() {
        let original = "写任务"
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        let insertionLocation = (original as NSString).length
        textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
        textView.setMarkedText(
            "ren",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: insertionLocation, length: 0)
        )
        let composingText = textView.string
        XCTAssertTrue(textView.hasMarkedText())

        textView.cycleTodoState()

        XCTAssertEqual(textView.string, composingText)
        XCTAssertEqual(MarkdownChecklist.progress(in: textView.string).total, 0)
    }

    func testCommandReturnKeyEquivalentAdvancesExactlyOneTodoState() throws {
        let original = "快捷键测试"
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        textView.setSelectedRange(
            NSRange(location: (original as NSString).length, length: 0)
        )
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )
        )

        XCTAssertTrue(textView.performKeyEquivalent(with: event))
        XCTAssertEqual(textView.string, "- [ ] 快捷键测试")
        XCTAssertTrue(textView.performKeyEquivalent(with: event))
        XCTAssertEqual(textView.string, "- [x] 快捷键测试")
        XCTAssertTrue(textView.performKeyEquivalent(with: event))
        XCTAssertEqual(textView.string, original)
    }

    func testSelectionSnapshotPreservesChineseAndEmojiUTF16Range() throws {
        let text = "前缀 中文😀片段 后缀"
        let selectedRange = (text as NSString).range(of: "中文😀片段")
        let document = makeDocument(scope: .task)
        var movedSnapshot: EditorSelectionSnapshot?
        let configuration = EditorSelectionMoveConfiguration(
            sourceDocument: document,
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记末尾",
            isEnabled: true,
            action: { movedSnapshot = $0 }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 420,
            selectionMoveConfiguration: configuration
        )

        harness.textView.setSelectedRange(selectedRange)

        XCTAssertTrue(harness.controller.hasTextSelection)
        let snapshot = try XCTUnwrap(harness.controller.currentSelectionSnapshot())
        XCTAssertEqual(snapshot.document, document)
        XCTAssertEqual(snapshot.destinationDocument, makeDocument(scope: .project))
        XCTAssertEqual(snapshot.selectionStableKey, "selection-a")
        XCTAssertEqual(snapshot.sourceText, text)
        XCTAssertEqual(snapshot.range, selectedRange)
        XCTAssertEqual(snapshot.selectedText, "中文😀片段")

        harness.controller.moveCurrentSelection()
        XCTAssertEqual(movedSnapshot, snapshot)
    }

    func testEmptySelectionHasNoSnapshotOrMovePillAndContextMenuStaysNative() throws {
        let text = "没有选中的正文"
        let configuration = EditorSelectionMoveConfiguration(
            sourceDocument: makeDocument(scope: .task),
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: { _ in XCTFail("空选区不应触发移动") }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 420,
            selectionMoveConfiguration: configuration
        )
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange(NSRange(location: 2, length: 0))
        runMainLoop()

        XCTAssertFalse(harness.controller.hasTextSelection)
        XCTAssertNil(harness.controller.currentSelectionSnapshot())
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
        let menu = harness.textView.menu(for: try rightMouseEvent(in: harness.window))
        XCTAssertNil(menu?.item(withTitle: configuration.title))

        harness.textView.setSelectedRange((text as NSString).range(of: "选中"))
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
        let selectedTextMenu = try XCTUnwrap(
            harness.textView.menu(for: try rightMouseEvent(in: harness.window))
        )
        XCTAssertNil(selectedTextMenu.item(withTitle: configuration.title))
        XCTAssertNotNil(
            selectedTextMenu.items.firstIndex(where: {
                $0.action == NSSelectorFromString("copy:")
            })
        )
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
    }

    func testSelectionMovePillAppearsNearUTF16SelectionAndConsumesClickOnce() throws {
        let text = "第一行\n移动中文😀片段\n最后一行"
        let range = (text as NSString).range(of: "中文😀片段")
        let document = makeDocument(scope: .task)
        var moveCount = 0
        var movedSnapshot: EditorSelectionSnapshot?
        let configuration = EditorSelectionMoveConfiguration(
            sourceDocument: document,
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: {
                moveCount += 1
                movedSnapshot = $0
            }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 420,
            selectionMoveConfiguration: configuration
        )
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange(range)
        runMainLoop()

        let snapshot = try XCTUnwrap(harness.controller.currentSelectionSnapshot())
        let toolbar = try XCTUnwrap(harness.textView.visibleSelectionToolbar)
        let pill = try XCTUnwrap(harness.textView.visibleSelectionMovePill)
        XCTAssertEqual(pill.title, configuration.title)
        XCTAssertNotNil(pill.image)
        XCTAssertEqual(toolbar.frame.height, 34)
        XCTAssertTrue(toolbar.frame.intersects(harness.textView.visibleRect))
        XCTAssertTrue(
            harness.textView.visibleRect.insetBy(dx: 7, dy: 7).contains(toolbar.frame)
        )
        XCTAssertTrue(harness.window.firstResponder === harness.textView)

        pill.performClick(nil)
        pill.performClick(nil)

        XCTAssertEqual(moveCount, 1)
        XCTAssertEqual(movedSnapshot, snapshot)
        XCTAssertNil(harness.textView.visibleSelectionToolbar)
        XCTAssertTrue(harness.window.firstResponder === harness.textView)
    }

    func testSelectionOrMoveIdentityChangeInvalidatesOldPillAction() throws {
        let text = "先移动😀这一段，再选择别处"
        let firstRange = (text as NSString).range(of: "移动😀这一段")
        let laterRange = (text as NSString).range(of: "别处")
        let document = makeDocument(scope: .task)
        var moveCount = 0
        let enabledConfiguration = EditorSelectionMoveConfiguration(
            sourceDocument: document,
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: { _ in moveCount += 1 }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 420,
            selectionMoveConfiguration: enabledConfiguration
        )
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange(firstRange)
        runMainLoop()
        let staleSelectionPill = try XCTUnwrap(
            harness.textView.visibleSelectionMovePill
        )

        harness.textView.setSelectedRange(laterRange)
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
        staleSelectionPill.performClick(nil)
        XCTAssertEqual(moveCount, 0)
        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        let staleIdentityPill = try XCTUnwrap(
            harness.textView.visibleSelectionMovePill
        )
        harness.textView.selectionMoveConfiguration = EditorSelectionMoveConfiguration(
            sourceDocument: document,
            destinationDocument: enabledConfiguration.destinationDocument,
            selectionStableKey: "selection-b",
            title: enabledConfiguration.title,
            isEnabled: true,
            action: { _ in moveCount += 1 }
        )
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
        staleIdentityPill.performClick(nil)
        XCTAssertEqual(moveCount, 0)

        harness.textView.selectionMoveConfiguration = enabledConfiguration
        harness.textView.setSelectedRange(firstRange)
        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        let staleDestinationPill = try XCTUnwrap(
            harness.textView.visibleSelectionMovePill
        )
        harness.textView.selectionMoveConfiguration = EditorSelectionMoveConfiguration(
            sourceDocument: document,
            destinationDocument: makeDocument(
                scope: .project,
                stableKey: "project-b"
            ),
            selectionStableKey: "selection-a",
            title: enabledConfiguration.title,
            isEnabled: true,
            action: { _ in moveCount += 1 }
        )
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
        staleDestinationPill.performClick(nil)
        XCTAssertEqual(moveCount, 0)
    }

    func testMovePillDoesNotAppearWhenDisabledReadOnlyOrUsingIME() throws {
        let original = "输入法正文"
        let document = makeDocument(scope: .task)
        let disabledConfiguration = EditorSelectionMoveConfiguration(
            sourceDocument: document,
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: false,
            disabledReason: "当前项目笔记不可写",
            action: { _ in XCTFail("不可用胶囊不应触发移动") }
        )
        let enabledConfiguration = EditorSelectionMoveConfiguration(
            sourceDocument: document,
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: { _ in XCTFail("本测试不应触发移动") }
        )
        let harness = makeHarness(
            text: original,
            textWidth: 420,
            selectionMoveConfiguration: disabledConfiguration
        )
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange((original as NSString).range(of: "正文"))
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionToolbar)
        XCTAssertFalse(
            try XCTUnwrap(harness.textView.visibleSelectionMovePill).isEnabled
        )
        XCTAssertEqual(
            try XCTUnwrap(
                harness.textView.visibleSelectionMovePill
            ).accessibilityLabel(),
            "移到项目笔记: 当前项目笔记不可写"
        )
        XCTAssertTrue(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarBoldButton).isEnabled
        )

        harness.textView.selectionMoveConfiguration = enabledConfiguration
        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
        harness.textView.isEditable = false
        XCTAssertNil(harness.textView.visibleSelectionMovePill)

        harness.textView.isEditable = true
        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
        harness.textView.insertText(
            "字",
            replacementRange: NSRange(location: (original as NSString).length, length: 0)
        )
        XCTAssertNil(harness.textView.visibleSelectionMovePill)

        let replacementRange = (harness.textView.string as NSString).range(of: "正文")
        harness.textView.setSelectedRange(replacementRange)
        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
        harness.textView.setMarkedText(
            "zhengwen",
            selectedRange: NSRange(location: 0, length: 3),
            replacementRange: replacementRange
        )
        XCTAssertTrue(harness.textView.hasMarkedText())
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
    }

    func testMovePillDismissesOnEscapeScrollFocusLossAndExternalSelectionUpdate() throws {
        let text = (0..<40).map { "第\($0)行 选择正文" }.joined(separator: "\n")
        let range = (text as NSString).range(of: "选择正文")
        let configuration = EditorSelectionMoveConfiguration(
            sourceDocument: makeDocument(scope: .task),
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: { _ in XCTFail("消失行为不应触发移动") }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 300,
            viewportHeight: 100,
            selectionMoveConfiguration: configuration
        )
        harness.textView.selectionMovePresentationDelay = 0

        harness.textView.setSelectedRange(range)
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
        harness.textView.cancelOperation(nil)
        XCTAssertNil(harness.textView.visibleSelectionMovePill)

        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
        harness.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 40))
        harness.scrollView.reflectScrolledClipView(harness.scrollView.contentView)
        XCTAssertNil(harness.textView.visibleSelectionMovePill)

        harness.scrollView.contentView.scroll(to: .zero)
        harness.scrollView.reflectScrolledClipView(harness.scrollView.contentView)
        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
        harness.coordinator.isApplyingExternalText = true
        harness.textView.setSelectedRange(
            NSRange(location: range.location + 1, length: range.length - 1)
        )
        harness.coordinator.isApplyingExternalText = false
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
        runMainLoop()
        XCTAssertNil(harness.textView.visibleSelectionMovePill)

        harness.textView.setSelectedRange(range)
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
        NotificationCenter.default.post(
            name: NSWindow.didResignKeyNotification,
            object: harness.window
        )
        XCTAssertNil(harness.textView.visibleSelectionMovePill)

        harness.window.reportsKeyWindow = false
        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
        harness.textView.setSelectedRange(
            NSRange(location: range.location + 1, length: range.length - 1)
        )
        runMainLoop()
        XCTAssertNil(harness.textView.visibleSelectionMovePill)

        harness.window.reportsKeyWindow = true
        harness.textView.selectionDidChangeForMovePill()
        runMainLoop()
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
        XCTAssertTrue(harness.window.makeFirstResponder(nil))
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
    }

    func testMovePillUsesDebouncedDefaultDelay() {
        let text = "延迟显示胶囊"
        let configuration = EditorSelectionMoveConfiguration(
            sourceDocument: makeDocument(scope: .task),
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: { _ in }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 300,
            selectionMoveConfiguration: configuration
        )
        XCTAssertEqual(harness.textView.selectionMovePresentationDelay, 0.14)
        harness.textView.setSelectedRange((text as NSString).range(of: "显示"))
        runMainLoop(for: 0.05)
        XCTAssertNil(harness.textView.visibleSelectionMovePill)
        runMainLoop(for: 0.15)
        XCTAssertNotNil(harness.textView.visibleSelectionMovePill)
    }

    func testSelectionToolbarUsesCompactLayoutAndAccessibleActions() throws {
        let text = "第一行 选择正文"
        let configuration = EditorSelectionMoveConfiguration(
            sourceDocument: makeDocument(scope: .task),
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: { _ in }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 420,
            selectionMoveConfiguration: configuration
        )
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange((text as NSString).range(of: "选择正文"))
        runMainLoop()

        let toolbar = try XCTUnwrap(harness.textView.visibleSelectionToolbar)
        let bold = try XCTUnwrap(harness.textView.visibleSelectionToolbarBoldButton)
        let highlight = try XCTUnwrap(
            harness.textView.visibleSelectionToolbarHighlightButton
        )
        let move = try XCTUnwrap(harness.textView.visibleSelectionToolbarMoveButton)

        XCTAssertEqual(toolbar.frame.height, 34)
        XCTAssertGreaterThanOrEqual(toolbar.frame.width, 190)
        XCTAssertLessThanOrEqual(toolbar.frame.width, 205)
        XCTAssertEqual(bold.frame.size, NSSize(width: 28, height: 28))
        XCTAssertEqual(highlight.frame.size, NSSize(width: 28, height: 28))
        XCTAssertEqual(move.frame.height, 28)
        XCTAssertEqual(bold.identifier?.rawValue, "selection-toolbar-bold")
        XCTAssertEqual(
            highlight.identifier?.rawValue,
            "selection-toolbar-highlight"
        )
        XCTAssertEqual(move.identifier?.rawValue, "selection-toolbar-move")
        XCTAssertEqual(
            bold.accessibilityLabel(),
            L10n.text(.editorSelectionToolbarBoldLabel)
        )
        XCTAssertEqual(
            highlight.accessibilityLabel(),
            L10n.text(.editorSelectionToolbarHighlightLabel)
        )
        XCTAssertEqual(highlight.title, "")
        XCTAssertEqual(highlight.imagePosition, .imageOnly)
        XCTAssertEqual(move.accessibilityLabel(), configuration.title)
        XCTAssertTrue(harness.window.firstResponder === harness.textView)
    }

    func testLanguageChangeRebuildsOnlyVisibleSelectionToolbar() throws {
        let text = "First line with selected text"
        let selectedRange = (text as NSString).range(of: "selected text")
        let sourceDocument = makeDocument(scope: .task)
        let destinationDocument = makeDocument(scope: .project)
        let initialConfiguration = EditorSelectionMoveConfiguration(
            sourceDocument: sourceDocument,
            destinationDocument: destinationDocument,
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: { _ in }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 420,
            selectionMoveConfiguration: initialConfiguration
        )
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange(selectedRange)
        runMainLoop()

        let originalToolbar = try XCTUnwrap(
            harness.textView.visibleSelectionToolbar
        )
        let undoManager = try XCTUnwrap(harness.textView.undoManager)
        let undoProbe = UndoProbe()
        undoManager.removeAllActions()
        undoManager.registerUndo(withTarget: undoProbe) { target in
            target.didUndo = true
        }
        XCTAssertTrue(undoManager.canUndo)

        harness.textView.selectionMoveConfiguration = EditorSelectionMoveConfiguration(
            sourceDocument: sourceDocument,
            destinationDocument: destinationDocument,
            selectionStableKey: "selection-a",
            title: "Move to Project Note",
            isEnabled: true,
            action: { _ in }
        )
        harness.textView.rebuildVisibleSelectionToolbarForLanguageChange()

        let rebuiltToolbar = try XCTUnwrap(
            harness.textView.visibleSelectionToolbar
        )
        XCTAssertFalse(originalToolbar === rebuiltToolbar)
        XCTAssertNil(originalToolbar.superview)
        XCTAssertEqual(
            try XCTUnwrap(
                harness.textView.visibleSelectionToolbarMoveButton
            ).title,
            "Move to Project Note"
        )
        XCTAssertEqual(harness.textView.string, text)
        XCTAssertEqual(harness.textView.selectedRange(), selectedRange)
        XCTAssertTrue(harness.window.firstResponder === harness.textView)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertTrue(
            harness.textView.visibleRect.insetBy(dx: 7, dy: 7).contains(
                rebuiltToolbar.frame
            )
        )

        undoManager.undo()
        XCTAssertTrue(undoProbe.didUndo)
        XCTAssertEqual(harness.textView.string, text)
        XCTAssertEqual(harness.textView.selectedRange(), selectedRange)
    }

    func testSelectionToolbarFormatGlyphsRenderInWholeToolbarAcrossAppearancesAndStates() throws {
        let cases: [(
            appearance: NSAppearance.Name,
            background: NSColor,
            foreground: NSColor,
            isSelected: Bool,
            expectsLightGlyphs: Bool
        )] = [
            (.aqua, .white, .black, false, false),
            (.aqua, .white, .black, true, false),
            (.darkAqua, .black, .white, false, true),
            (.darkAqua, .black, .white, true, true)
        ]

        for item in cases {
            let text = item.isSelected ? "**==正文==**" : "正文"
            let selection = item.isSelected
                ? NSRange(location: 4, length: 2)
                : NSRange(location: 0, length: 2)
            let harness = makeHarness(text: text, textWidth: 360)
            harness.window.appearance = NSAppearance(named: item.appearance)
            harness.textView.selectionMovePresentationDelay = 0
            harness.textView.updateSelectionToolbarStyle(
                backgroundColor: item.background,
                foregroundColor: item.foreground,
                accentColor: item.foreground,
                hoverColor: item.foreground,
                selectionColor: item.foreground,
                borderColor: .clear
            )
            harness.textView.setSelectedRange(selection)
            runMainLoop()

            let toolbar = try XCTUnwrap(harness.textView.visibleSelectionToolbar)
            let bold = try XCTUnwrap(
                harness.textView.visibleSelectionToolbarBoldButton
            )
            let highlight = try XCTUnwrap(
                harness.textView.visibleSelectionToolbarHighlightButton
            )
            XCTAssertEqual(toolbar.frame.size, NSSize(width: 64, height: 34))
            XCTAssertEqual(bold.state, item.isSelected ? .on : .off)
            XCTAssertEqual(highlight.state, item.isSelected ? .on : .off)

            // The compact glyphs must be rendered by the role-driven button,
            // not by NSButtonCell. Borderless layer-backed cells can lose their
            // title/image when the toolbar is composited inside NSTextView.
            bold.title = ""
            bold.attributedTitle = NSAttributedString()
            highlight.image = nil
            bold.needsDisplay = true
            highlight.needsDisplay = true
            toolbar.needsDisplay = true

            let pixels = renderedPixels(of: toolbar)
            let pixelWidth = max(1, Int(toolbar.bounds.width.rounded(.up)))
            let pixelHeight = max(1, Int(toolbar.bounds.height.rounded(.up)))
            let boldPixels = highContrastPixelCount(
                pixels,
                width: pixelWidth,
                height: pixelHeight,
                rect: bold.frame.insetBy(dx: 6, dy: 5),
                expectsLightPixels: item.expectsLightGlyphs
            )
            let highlightPixels = highContrastPixelCount(
                pixels,
                width: pixelWidth,
                height: pixelHeight,
                rect: highlight.frame.insetBy(dx: 5, dy: 5),
                expectsLightPixels: item.expectsLightGlyphs
            )
            XCTAssertGreaterThan(
                boldPixels,
                8,
                "B glyph missing for \(item.appearance.rawValue), selected=\(item.isSelected)"
            )
            XCTAssertGreaterThan(
                highlightPixels,
                8,
                "highlighter glyph missing for \(item.appearance.rawValue), selected=\(item.isSelected)"
            )
        }
    }

    func testSelectionToolbarSystemSurfaceAndBorderAreOpaqueInBothAppearances() throws {
        let cases: [(
            appearance: NSAppearance.Name,
            surface: CGFloat,
            border: CGFloat,
            shadowOpacity: Float
        )] = [
            (.aqua, 0xE6 / 255, 0xCF / 255, 0.20),
            (.darkAqua, 0x34 / 255, 0x48 / 255, 0.42)
        ]

        for item in cases {
            let harness = makeHarness(text: "正文", textWidth: 360)
            harness.window.appearance = NSAppearance(named: item.appearance)
            harness.textView.backgroundColor = .textBackgroundColor
            harness.textView.selectionMovePresentationDelay = 0
            harness.textView.updateSelectionToolbarStyle(
                backgroundColor: .quaternaryLabelColor,
                foregroundColor: .labelColor,
                accentColor: .controlAccentColor,
                hoverColor: .controlBackgroundColor,
                selectionColor: .selectedTextBackgroundColor,
                borderColor: .separatorColor
            )
            harness.textView.setSelectedRange(NSRange(location: 0, length: 2))
            runMainLoop()

            let toolbar = try XCTUnwrap(harness.textView.visibleSelectionToolbar)
            let surface = try XCTUnwrap(colorComponents(of: toolbar.layer?.backgroundColor))
            let border = try XCTUnwrap(colorComponents(of: toolbar.layer?.borderColor))
            XCTAssertEqual(surface.alpha, 1, accuracy: 0.001)
            XCTAssertEqual(border.alpha, 1, accuracy: 0.001)
            XCTAssertEqual(surface.red, item.surface, accuracy: 0.055)
            XCTAssertEqual(surface.green, item.surface, accuracy: 0.055)
            XCTAssertEqual(surface.blue, item.surface, accuracy: 0.055)
            XCTAssertEqual(border.red, item.border, accuracy: 0.065)
            XCTAssertEqual(border.green, item.border, accuracy: 0.065)
            XCTAssertEqual(border.blue, item.border, accuracy: 0.065)
            XCTAssertEqual(toolbar.layer?.borderWidth, 0.5)
            XCTAssertEqual(toolbar.layer?.shadowOpacity, item.shadowOpacity)
            XCTAssertEqual(toolbar.layer?.shadowRadius, 8)
            XCTAssertEqual(toolbar.layer?.shadowOffset, NSSize(width: 0, height: -2))
        }
    }

    func testSelectionToolbarPreservesOpaqueCustomThemeColors() throws {
        let surfaceColor = NSColor(
            srgbRed: 0.18,
            green: 0.27,
            blue: 0.39,
            alpha: 1
        )
        let borderColor = NSColor(
            srgbRed: 0.31,
            green: 0.43,
            blue: 0.57,
            alpha: 1
        )
        let harness = makeHarness(text: "正文", textWidth: 360)
        harness.window.appearance = NSAppearance(named: .darkAqua)
        harness.textView.backgroundColor = NSColor(
            srgbRed: 0.04,
            green: 0.06,
            blue: 0.09,
            alpha: 1
        )
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.updateSelectionToolbarStyle(
            backgroundColor: surfaceColor,
            foregroundColor: .white,
            accentColor: .systemBlue,
            hoverColor: .white,
            selectionColor: .systemBlue,
            borderColor: borderColor
        )
        harness.textView.setSelectedRange(NSRange(location: 0, length: 2))
        runMainLoop()

        let toolbar = try XCTUnwrap(harness.textView.visibleSelectionToolbar)
        let surface = try XCTUnwrap(colorComponents(of: toolbar.layer?.backgroundColor))
        let border = try XCTUnwrap(colorComponents(of: toolbar.layer?.borderColor))
        XCTAssertEqual(surface.red, 0.18, accuracy: 0.002)
        XCTAssertEqual(surface.green, 0.27, accuracy: 0.002)
        XCTAssertEqual(surface.blue, 0.39, accuracy: 0.002)
        XCTAssertEqual(surface.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(border.red, 0.31, accuracy: 0.002)
        XCTAssertEqual(border.green, 0.43, accuracy: 0.002)
        XCTAssertEqual(border.blue, 0.57, accuracy: 0.002)
        XCTAssertEqual(border.alpha, 1, accuracy: 0.001)
    }

    func testSelectionToolbarDefaultAndSelectedButtonSurfacesUseCompactStateOverlays() throws {
        let cases: [(
            appearance: NSAppearance.Name,
            markdown: String,
            selection: NSRange,
            boldAlpha: CGFloat,
            highlightAlpha: CGFloat
        )] = [
            (.aqua, "**正文**", NSRange(location: 2, length: 2), 0.18, 0),
            (.aqua, "==正文==", NSRange(location: 2, length: 2), 0, 0.34),
            (.darkAqua, "**正文**", NSRange(location: 2, length: 2), 0.24, 0),
            (.darkAqua, "==正文==", NSRange(location: 2, length: 2), 0, 0.38)
        ]

        for item in cases {
            let configuration = EditorSelectionMoveConfiguration(
                sourceDocument: makeDocument(scope: .task),
                destinationDocument: makeDocument(scope: .project),
                selectionStableKey: "selection-a",
                title: "移到项目笔记",
                isEnabled: true,
                action: { _ in }
            )
            let harness = makeHarness(
                text: item.markdown,
                textWidth: 360,
                selectionMoveConfiguration: configuration
            )
            harness.window.appearance = NSAppearance(named: item.appearance)
            harness.textView.selectionMovePresentationDelay = 0
            harness.textView.updateSelectionToolbarStyle(
                backgroundColor: .quaternaryLabelColor,
                foregroundColor: .labelColor,
                accentColor: .controlAccentColor,
                hoverColor: .controlBackgroundColor,
                selectionColor: .selectedTextBackgroundColor,
                borderColor: .separatorColor
            )
            harness.textView.setSelectedRange(item.selection)
            runMainLoop()

            let bold = try XCTUnwrap(harness.textView.visibleSelectionToolbarBoldButton)
            let highlight = try XCTUnwrap(
                harness.textView.visibleSelectionToolbarHighlightButton
            )
            let move = try XCTUnwrap(harness.textView.visibleSelectionToolbarMoveButton)
            XCTAssertEqual(
                try XCTUnwrap(colorComponents(of: bold.layer?.backgroundColor)).alpha,
                item.boldAlpha,
                accuracy: 0.015
            )
            XCTAssertEqual(
                try XCTUnwrap(colorComponents(of: highlight.layer?.backgroundColor)).alpha,
                item.highlightAlpha,
                accuracy: 0.015
            )
            XCTAssertEqual(
                try XCTUnwrap(colorComponents(of: move.layer?.backgroundColor)).alpha,
                0,
                accuracy: 0.001
            )
        }
    }

    func testSelectionToolbarOpaqueInteriorDoesNotRevealContrastingBacking() throws {
        let harness = makeHarness(text: "对比正文", textWidth: 360)
        harness.window.appearance = NSAppearance(named: .aqua)
        harness.textView.backgroundColor = .white
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.updateSelectionToolbarStyle(
            backgroundColor: .quaternaryLabelColor,
            foregroundColor: .black,
            accentColor: .systemBlue,
            hoverColor: .controlBackgroundColor,
            selectionColor: .selectedTextBackgroundColor,
            borderColor: .separatorColor
        )
        harness.textView.setSelectedRange(NSRange(location: 0, length: 2))
        runMainLoop()

        let toolbar = try XCTUnwrap(harness.textView.visibleSelectionToolbar)
        XCTAssertEqual(toolbar.frame.size, NSSize(width: 64, height: 34))
        toolbar.removeFromSuperview()
        let canvas = NSView(frame: NSRect(origin: .zero, size: toolbar.frame.size))
        canvas.wantsLayer = true
        toolbar.frame = canvas.bounds
        canvas.addSubview(toolbar)
        // Reapply after reparenting so this exercises the actual layer that is
        // composited above the contrasting backing.
        harness.textView.updateSelectionToolbarStyle(
            backgroundColor: .quaternaryLabelColor,
            foregroundColor: .black,
            accentColor: .systemBlue,
            hoverColor: .controlBackgroundColor,
            selectionColor: .selectedTextBackgroundColor,
            borderColor: .separatorColor
        )

        let blankInterior = NSRect(x: 31, y: 10, width: 2, height: 14)
        canvas.layer?.backgroundColor = NSColor.white.cgColor
        canvas.needsDisplay = true
        let overBlank = renderedPixels(of: canvas, in: blankInterior)
        canvas.layer?.backgroundColor = NSColor.black.cgColor
        canvas.needsDisplay = true
        let overDarkContent = renderedPixels(of: canvas, in: blankInterior)
        XCTAssertEqual(
            overBlank,
            overDarkContent,
            "opaque toolbar interior must fully isolate text beneath it"
        )
    }

    func testVisibleSelectionToolbarReResolvesWhenEffectiveAppearanceChanges() throws {
        let harness = makeHarness(text: "正文", textWidth: 360)
        harness.window.appearance = NSAppearance(named: .aqua)
        harness.textView.backgroundColor = .textBackgroundColor
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.updateSelectionToolbarStyle(
            backgroundColor: .quaternaryLabelColor,
            foregroundColor: .labelColor,
            accentColor: .controlAccentColor,
            hoverColor: .controlBackgroundColor,
            selectionColor: .selectedTextBackgroundColor,
            borderColor: .separatorColor
        )
        harness.textView.setSelectedRange(NSRange(location: 0, length: 2))
        runMainLoop()

        let toolbar = try XCTUnwrap(harness.textView.visibleSelectionToolbar)
        let lightSurface = try XCTUnwrap(
            colorComponents(of: toolbar.layer?.backgroundColor)
        )
        XCTAssertGreaterThan(lightSurface.red, 0.80)
        XCTAssertEqual(lightSurface.alpha, 1, accuracy: 0.001)

        harness.window.appearance = NSAppearance(named: .darkAqua)
        runMainLoop()
        let darkSurface = try XCTUnwrap(
            colorComponents(of: toolbar.layer?.backgroundColor)
        )
        XCTAssertLessThan(darkSurface.red, 0.30)
        XCTAssertEqual(darkSurface.alpha, 1, accuracy: 0.001)
        XCTAssertEqual(toolbar.layer?.shadowOpacity, 0.42)

        harness.window.appearance = NSAppearance(named: .aqua)
        runMainLoop()
        let restoredLightSurface = try XCTUnwrap(
            colorComponents(of: toolbar.layer?.backgroundColor)
        )
        XCTAssertEqual(restoredLightSurface.red, lightSurface.red, accuracy: 0.01)
        XCTAssertEqual(toolbar.layer?.shadowOpacity, 0.20)
    }

    func testSelectionToolbarClampsMoveButtonInsideNarrowViewport() throws {
        let text = "窄窗口选择"
        let configuration = EditorSelectionMoveConfiguration(
            sourceDocument: makeDocument(scope: .task),
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: { _ in }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 150,
            selectionMoveConfiguration: configuration
        )
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange((text as NSString).range(of: "选择"))
        runMainLoop()

        let toolbar = try XCTUnwrap(harness.textView.visibleSelectionToolbar)
        let move = try XCTUnwrap(harness.textView.visibleSelectionToolbarMoveButton)
        XCTAssertLessThan(toolbar.frame.width, 190)
        XCTAssertLessThanOrEqual(move.frame.maxX, toolbar.bounds.maxX)
        XCTAssertGreaterThanOrEqual(move.frame.minX, toolbar.bounds.minX)
        XCTAssertLessThan(move.frame.width, move.attributedTitle.size().width + 40)
        XCTAssertEqual(move.cell?.lineBreakMode, .byTruncatingMiddle)
    }

    func testSelectionToolbarFormattingDoesNotDependOnMoveAvailability() throws {
        let text = "没有项目也可以格式化"
        let range = (text as NSString).range(of: "可以格式化")
        let harness = makeHarness(text: text, textWidth: 360)
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange(range)
        runMainLoop()

        let toolbar = try XCTUnwrap(harness.textView.visibleSelectionToolbar)
        XCTAssertEqual(toolbar.frame.size, NSSize(width: 64, height: 34))
        XCTAssertNotNil(harness.textView.visibleSelectionToolbarBoldButton)
        XCTAssertNotNil(harness.textView.visibleSelectionToolbarHighlightButton)
        XCTAssertNil(harness.textView.visibleSelectionToolbarMoveButton)
    }

    func testSelectionToolbarBoldAndHighlightTogglePreserveSelectionAndToolbar() throws {
        let original = "前缀 重点文字 后缀"
        let originalRange = (original as NSString).range(of: "重点文字")
        let harness = makeHarness(text: original, textWidth: 420)
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange(originalRange)
        runMainLoop()

        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarBoldButton
        ).performClick(nil)

        XCTAssertEqual(harness.textView.string, "前缀 **重点文字** 后缀")
        XCTAssertEqual(
            harness.textView.selectedRange(),
            (harness.textView.string as NSString).range(of: "重点文字")
        )
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarBoldButton).state,
            .on
        )
        XCTAssertNotNil(harness.textView.visibleSelectionToolbar)
        XCTAssertTrue(harness.window.firstResponder === harness.textView)

        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarBoldButton
        ).performClick(nil)
        XCTAssertEqual(harness.textView.string, original)
        XCTAssertEqual(harness.textView.selectedRange(), originalRange)
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarBoldButton).state,
            .off
        )

        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarHighlightButton
        ).performClick(nil)
        XCTAssertEqual(harness.textView.string, "前缀 ==重点文字== 后缀")
        XCTAssertEqual(
            harness.textView.selectedRange(),
            (harness.textView.string as NSString).range(of: "重点文字")
        )
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarHighlightButton).state,
            .on
        )
        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarHighlightButton
        ).performClick(nil)
        XCTAssertEqual(harness.textView.string, original)
        XCTAssertEqual(harness.textView.selectedRange(), originalRange)
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarHighlightButton).state,
            .off
        )
        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarHighlightButton
        ).performClick(nil)
        XCTAssertEqual(harness.textView.string, "前缀 ==重点文字== 后缀")
        XCTAssertTrue(harness.textView.undoManager?.canUndo == true)
        harness.textView.undoManager?.undo()
        XCTAssertEqual(harness.textView.string, original)
        XCTAssertTrue(harness.textView.undoManager?.canRedo == true)
        harness.textView.undoManager?.redo()
        XCTAssertEqual(harness.textView.string, "前缀 ==重点文字== 后缀")
    }

    func testSelectionToolbarNestedFormatsCanBeCancelledIndependently() throws {
        let original = "组合格式"
        let harness = makeHarness(text: original, textWidth: 360)
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange((original as NSString).range(of: "格式"))
        runMainLoop()

        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarBoldButton
        ).performClick(nil)
        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarHighlightButton
        ).performClick(nil)
        XCTAssertEqual(harness.textView.string, "组合**==格式==**")
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarBoldButton).state,
            .on
        )
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarHighlightButton).state,
            .on
        )

        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarHighlightButton
        ).performClick(nil)
        XCTAssertEqual(harness.textView.string, "组合**格式**")
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarBoldButton).state,
            .on
        )
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarHighlightButton).state,
            .off
        )

        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarHighlightButton
        ).performClick(nil)
        try XCTUnwrap(
            harness.textView.visibleSelectionToolbarBoldButton
        ).performClick(nil)
        XCTAssertEqual(harness.textView.string, "组合==格式==")
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarBoldButton).state,
            .off
        )
        XCTAssertEqual(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarHighlightButton).state,
            .on
        )
    }

    func testSelectionToolbarDisablesInlineFormatsForMultilineSelection() throws {
        let text = "第一行\n第二行"
        var moveCount = 0
        let configuration = EditorSelectionMoveConfiguration(
            sourceDocument: makeDocument(scope: .task),
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "selection-a",
            title: "移到项目笔记",
            isEnabled: true,
            action: { _ in moveCount += 1 }
        )
        let harness = makeHarness(
            text: text,
            textWidth: 360,
            selectionMoveConfiguration: configuration
        )
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange(
            NSRange(location: 0, length: (text as NSString).length)
        )
        runMainLoop()

        let bold = try XCTUnwrap(harness.textView.visibleSelectionToolbarBoldButton)
        let highlight = try XCTUnwrap(
            harness.textView.visibleSelectionToolbarHighlightButton
        )
        XCTAssertFalse(bold.isEnabled)
        XCTAssertFalse(highlight.isEnabled)
        XCTAssertTrue(
            try XCTUnwrap(harness.textView.visibleSelectionToolbarMoveButton).isEnabled
        )
        bold.performClick(nil)
        highlight.performClick(nil)
        XCTAssertEqual(harness.textView.string, text)
        XCTAssertEqual(moveCount, 0)
    }

    func testSelectionToolbarProtectsCodeImageAndCheckboxSyntaxButKeepsMove() throws {
        let cases: [(text: String, range: NSRange)] = [
            (
                text: "`代码内容`",
                range: ("`代码内容`" as NSString).range(of: "代码内容")
            ),
            (
                text: "![图片](../Assets/example.png)",
                range: ("![图片](../Assets/example.png)" as NSString).range(of: "图片")
            ),
            (
                text: "- [ ] 待办内容",
                range: try XCTUnwrap(
                    MarkdownChecklist.checkboxMatches(in: "- [ ] 待办内容").first
                ).prefixRange
            )
        ]

        for (index, item) in cases.enumerated() {
            var moveCount = 0
            let configuration = EditorSelectionMoveConfiguration(
                sourceDocument: makeDocument(scope: .task),
                destinationDocument: makeDocument(
                    scope: .project,
                    stableKey: "project-\(index)"
                ),
                selectionStableKey: "selection-\(index)",
                title: "移到项目笔记",
                isEnabled: true,
                action: { _ in moveCount += 1 }
            )
            let harness = makeHarness(
                text: item.text,
                textWidth: 420,
                selectionMoveConfiguration: configuration
            )
            harness.textView.selectionMovePresentationDelay = 0
            harness.textView.setSelectedRange(item.range)
            runMainLoop()

            XCTAssertFalse(
                try XCTUnwrap(
                    harness.textView.visibleSelectionToolbarBoldButton
                ).isEnabled,
                "case \(index) bold"
            )
            XCTAssertFalse(
                try XCTUnwrap(
                    harness.textView.visibleSelectionToolbarHighlightButton
                ).isEnabled,
                "case \(index) highlight"
            )
            let move = try XCTUnwrap(
                harness.textView.visibleSelectionToolbarMoveButton
            )
            XCTAssertTrue(move.isEnabled)
            move.performClick(nil)
            XCTAssertEqual(moveCount, 1)
            XCTAssertNil(harness.textView.visibleSelectionToolbar)
        }
    }

    func testInlineFormatKeyboardShortcutsAndCompositionSafety() throws {
        let original = "快捷格式"
        let harness = makeHarness(text: original, textWidth: 360)
        harness.textView.setSelectedRange((original as NSString).range(of: "格式"))

        let boldEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: .command,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "b",
                charactersIgnoringModifiers: "b",
                isARepeat: false,
                keyCode: 11
            )
        )
        XCTAssertTrue(harness.textView.performKeyEquivalent(with: boldEvent))
        XCTAssertEqual(harness.textView.string, "快捷**格式**")

        let highlightEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .shift],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "H",
                charactersIgnoringModifiers: "h",
                isARepeat: false,
                keyCode: 4
            )
        )
        XCTAssertTrue(harness.textView.performKeyEquivalent(with: highlightEvent))
        XCTAssertEqual(harness.textView.string, "快捷**==格式==**")

        let compositionHarness = makeHarness(text: original, textWidth: 360)
        compositionHarness.textView.setSelectedRange(
            NSRange(location: (original as NSString).length, length: 0)
        )
        compositionHarness.textView.setMarkedText(
            "geshi",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(
                location: (original as NSString).length,
                length: 0
            )
        )
        let composingText = compositionHarness.textView.string
        XCTAssertTrue(
            compositionHarness.textView.performKeyEquivalent(with: boldEvent)
        )
        XCTAssertEqual(compositionHarness.textView.string, composingText)
        XCTAssertTrue(compositionHarness.textView.hasMarkedText())
        XCTAssertNil(compositionHarness.textView.visibleSelectionToolbar)
    }

    func testInlineFormatPresentationStylesContentWithoutMutatingMarkdown() throws {
        let text = "**加粗** 和 ==高亮=="
        let harness = makeHarness(text: text, textWidth: 360)
        harness.textView.refreshChecklistPresentation(forceLayout: true)
        let layoutManager = try XCTUnwrap(harness.textView.layoutManager)
        let matches = MarkdownInlineFormat.matches(in: text)
        let boldMatch = try XCTUnwrap(matches.first(where: { $0.format == .bold }))
        let highlightMatch = try XCTUnwrap(
            matches.first(where: { $0.format == .highlight })
        )

        let boldFont = try XCTUnwrap(
            harness.textView.textStorage?.attribute(
                .font,
                at: boldMatch.contentRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        XCTAssertTrue(
            NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask)
        )
        XCTAssertNil(
            layoutManager.temporaryAttribute(
                .font,
                atCharacterIndex: boldMatch.contentRange.location,
                effectiveRange: nil
            )
        )
        let markerFont = try XCTUnwrap(
            harness.textView.textStorage?.attribute(
                .font,
                at: boldMatch.openingDelimiterRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        XCTAssertFalse(
            NSFontManager.shared.traits(of: markerFont).contains(.boldFontMask)
        )
        let typingFont = try XCTUnwrap(
            harness.textView.typingAttributes[.font] as? NSFont
        )
        XCTAssertFalse(
            NSFontManager.shared.traits(of: typingFont).contains(.boldFontMask)
        )
        XCTAssertNil(
            layoutManager.temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: highlightMatch.contentRange.location,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertEqual(harness.textView.string, text)
    }

    func testHighlightBackgroundUsesGlyphHeightInsteadOfLineSpacingAcrossAppearances() {
        let appearances: [(NSAppearance.Name, NSColor, NSColor)] = [
            (.aqua, .white, .black),
            (.darkAqua, .black, .white)
        ]

        for (appearance, background, foreground) in appearances {
            for fontSize: CGFloat in [12, 18, 24] {
                var heightsBySpacing: [[CGFloat]] = []
                let font = NSFont.monospacedSystemFont(
                    ofSize: fontSize,
                    weight: .regular
                )
                let expectedHeight = font.ascender - font.descender - 2
                for spacing: CGFloat in [0, 7, 12] {
                    let components = renderedHighlightComponents(
                        // Small center glyphs keep the rounded background edge
                        // visible at every font size; CJK/emoji occlusion is
                        // covered separately by the wrapped-content test.
                        text: "==··==\n==··==",
                        textWidth: 280,
                        fontSize: fontSize,
                        lineSpacing: spacing,
                        appearance: appearance,
                        backgroundColor: background,
                        foregroundColor: foreground
                    )
                    XCTAssertEqual(
                        components.count,
                        2,
                        "highlight rows merged for \(appearance.rawValue), font=\(fontSize), spacing=\(spacing)"
                    )
                    guard components.count == 2 else { continue }
                    let heights = components.map(\.rect.height).sorted()
                    XCTAssertLessThanOrEqual(heights[1] - heights[0], 1)
                    XCTAssertTrue(
                        heights.allSatisfy { abs($0 - expectedHeight) <= 2 },
                        "unexpected heights \(heights), expected≈\(expectedHeight), font=\(fontSize)"
                    )
                    XCTAssertEqual(
                        components[0].rect.minX,
                        components[1].rect.minX,
                        accuracy: 1
                    )
                    XCTAssertEqual(
                        components[0].rect.width,
                        components[1].rect.width,
                        accuracy: 1
                    )
                    heightsBySpacing.append(heights)
                }
                if heightsBySpacing.count == 3 {
                    let flattenedHeights = heightsBySpacing.flatMap { $0 }
                    XCTAssertLessThanOrEqual(
                        (flattenedHeights.max() ?? 0)
                            - (flattenedHeights.min() ?? 0),
                        1
                    )
                }
            }
        }
    }

    func testHighlightBackgroundSplitsWrappedNestedBoldCJKAndEmojiByVisualLine() {
        let text = "**==中文🙂高亮内容自动换行测试中文🙂高亮内容自动换行测试==**"
        let components = renderedHighlightComponents(
            text: text,
            textWidth: 150,
            fontSize: 18,
            lineSpacing: 12,
            appearance: .darkAqua,
            backgroundColor: .black,
            foregroundColor: .white,
            minimumComponentWidth: 24
        )

        XCTAssertGreaterThanOrEqual(components.count, 3)
        XCTAssertTrue(components.allSatisfy { $0.rect.height >= 18 && $0.rect.height <= 22 })
        let heights = components.map(\.rect.height)
        XCTAssertLessThanOrEqual(
            (heights.max() ?? 0) - (heights.min() ?? 0),
            1
        )
        XCTAssertEqual(MarkdownInlineFormat.matches(in: text).count, 2)
    }

    func testSelectionBackgroundCenterDoesNotDriftAcrossAppearanceFontAndSpacingMatrix() throws {
        let text = "上一行\n前选区后\n下一行"
        let selection = (text as NSString).range(of: "选区")

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for fontSize: CGFloat in [12, 18, 24] {
                let baseline = try renderedSelectionGeometry(
                    text: text,
                    selection: selection,
                    appearance: appearance,
                    fontSize: fontSize,
                    lineSpacing: 0
                )
                let baselineCenterOffset = baseline.surface.midY - baseline.ink.midY

                for lineSpacing: CGFloat in [7, 12] {
                    let spaced = try renderedSelectionGeometry(
                        text: text,
                        selection: selection,
                        appearance: appearance,
                        fontSize: fontSize,
                        lineSpacing: lineSpacing
                    )
                    let context = "appearance=\(appearance.rawValue), font=\(fontSize), spacing=\(lineSpacing)"
                    XCTAssertEqual(
                        spaced.surface.midY - spaced.ink.midY,
                        baselineCenterOffset,
                        accuracy: 1,
                        "selection center drifted; \(context)"
                    )
                    XCTAssertEqual(
                        spaced.surface.height - baseline.surface.height,
                        lineSpacing,
                        accuracy: 1,
                        "selection must retain the full line height; \(context)"
                    )
                    XCTAssertEqual(
                        spaced.surface.minX,
                        baseline.surface.minX,
                        accuracy: 1,
                        "vertical centering changed the selection start; \(context)"
                    )
                    XCTAssertEqual(
                        spaced.surface.width,
                        baseline.surface.width,
                        accuracy: 1,
                        "vertical centering changed the selection width; \(context)"
                    )
                }
            }
        }
    }

    func testInsertionPointCenterDoesNotDriftAcrossAppearanceFontAndSpacingMatrix() throws {
        let text = "上一行\n前光标后\n下一行"
        let caretLocation = (text as NSString).range(of: "光标").location + 1

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for fontSize: CGFloat in [12, 18, 24] {
                let baseline = try renderedInsertionPointGeometry(
                    text: text,
                    caretLocation: caretLocation,
                    appearance: appearance,
                    fontSize: fontSize,
                    lineSpacing: 0
                )
                let baselineCenterOffset = baseline.surface.midY - baseline.ink.midY

                for lineSpacing: CGFloat in [7, 12] {
                    let spaced = try renderedInsertionPointGeometry(
                        text: text,
                        caretLocation: caretLocation,
                        appearance: appearance,
                        fontSize: fontSize,
                        lineSpacing: lineSpacing
                    )
                    let context = "appearance=\(appearance.rawValue), font=\(fontSize), spacing=\(lineSpacing)"
                    XCTAssertEqual(
                        spaced.surface.midY - spaced.ink.midY,
                        baselineCenterOffset,
                        accuracy: 1,
                        "insertion point center drifted; \(context)"
                    )
                    XCTAssertEqual(
                        spaced.surface.height - baseline.surface.height,
                        lineSpacing,
                        accuracy: 1,
                        "insertion point must retain the full line height; \(context)"
                    )
                    XCTAssertEqual(
                        spaced.surface.minX,
                        baseline.surface.minX,
                        accuracy: 1,
                        "vertical centering changed the insertion x position; \(context)"
                    )
                    XCTAssertEqual(
                        spaced.surface.width,
                        baseline.surface.width,
                        accuracy: 0.5,
                        "vertical centering changed the insertion width; \(context)"
                    )
                }
            }
        }
    }

    func testCheckboxTextViewConstructorsOwnOneSymmetricTextSystemThroughUndo() throws {
        let factories: [(String, () -> CheckboxTextView)] = [
            ("init", { CheckboxTextView() }),
            ("init-frame", {
                CheckboxTextView(
                    frame: NSRect(x: 0, y: 0, width: 280, height: 180)
                )
            })
        ]

        for (name, factory) in factories {
            let textView = factory()
            textView.frame = NSRect(x: 0, y: 0, width: 280, height: 180)
            textView.isRichText = false
            textView.allowsUndo = true
            let window = EditorHarnessWindow(
                contentRect: textView.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = textView
            _ = window.makeFirstResponder(textView)

            var retainedTextStorage = try XCTUnwrap(textView.textStorage, name)
            let weakTextStorage = WeakObjectBox(retainedTextStorage)
            let layoutManager = try XCTUnwrap(textView.layoutManager, name)
            let textContainer = try XCTUnwrap(textView.textContainer, name)
            XCTAssertEqual(
                String(describing: type(of: layoutManager)),
                "SymmetricSelectionLayoutManager",
                name
            )
            XCTAssertEqual(retainedTextStorage.layoutManagers.count, 1, name)
            XCTAssertTrue(retainedTextStorage.layoutManagers[0] === layoutManager, name)
            XCTAssertEqual(layoutManager.textContainers.count, 1, name)
            XCTAssertTrue(layoutManager.textContainers[0] === textContainer, name)
            XCTAssertTrue(textContainer.layoutManager === layoutManager, name)
            XCTAssertTrue(textView.textContainer === textContainer, name)
            retainedTextStorage = NSTextStorage()

            textView.string = "原文"
            textView.setSelectedRange(NSRange(location: 2, length: 0))
            let undoManager = try XCTUnwrap(textView.undoManager, name)
            undoManager.removeAllActions()
            textView.insertText(
                "新增",
                replacementRange: textView.selectedRange()
            )
            XCTAssertEqual(textView.string, "原文新增", name)
            XCTAssertTrue(undoManager.canUndo, name)
            undoManager.undo()
            XCTAssertEqual(textView.string, "原文", name)
            let survivingTextStorage = try XCTUnwrap(weakTextStorage.value, name)
            XCTAssertTrue(textView.textStorage === survivingTextStorage, name)
            XCTAssertTrue(textView.layoutManager === layoutManager, name)
            XCTAssertTrue(textView.textContainer === textContainer, name)
        }
    }

    func testFinalLineEOFAndTrailingNewlineKeepNativeSelectionAndCaretGeometry() throws {
        let finalLineText = "上一行\n前选区后"
        let finalSelection = (finalLineText as NSString).range(of: "选区")

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let selectionBaseline = try renderedSelectionGeometry(
                text: finalLineText,
                selection: finalSelection,
                appearance: appearance,
                fontSize: 18,
                lineSpacing: 0
            )
            let baselineCenterOffset = selectionBaseline.surface.midY
                - selectionBaseline.ink.midY

            for lineSpacing: CGFloat in [7, 12] {
                let selection = try renderedSelectionGeometry(
                    text: finalLineText,
                    selection: finalSelection,
                    appearance: appearance,
                    fontSize: 18,
                    lineSpacing: lineSpacing
                )
                let context = "appearance=\(appearance.rawValue), spacing=\(lineSpacing)"
                XCTAssertEqual(
                    selection.surface.height,
                    selectionBaseline.surface.height,
                    accuracy: 1,
                    "final line must not gain trailing line spacing; \(context)"
                )
                XCTAssertEqual(
                    selection.surface.midY - selection.ink.midY,
                    baselineCenterOffset,
                    accuracy: 1,
                    "final-line selection must stay centered; \(context)"
                )

                let caretCases: [(String, Int, String)] = [
                    (
                        finalLineText,
                        (finalLineText as NSString).range(of: "选区").location + 1,
                        "inside-final-line"
                    ),
                    (
                        finalLineText,
                        (finalLineText as NSString).length,
                        "nonempty-eof"
                    ),
                    (
                        "上一行\n",
                        ("上一行\n" as NSString).length,
                        "trailing-newline-extra-fragment"
                    )
                ]
                for (text, caretLocation, caseName) in caretCases {
                    let harness = makeHarness(
                        text: text,
                        textWidth: 280,
                        fontSize: 18,
                        lineSpacing: lineSpacing
                    )
                    configureAdornmentPixelHarness(
                        harness,
                        appearance: appearance,
                        usesDarkInk: appearance == .aqua
                    )
                    harness.textView.setSelectedRange(
                        NSRange(location: caretLocation, length: 0)
                    )
                    let nativeRect = try nativeInsertionPointRect(
                        in: harness.textView,
                        at: caretLocation
                    )
                    XCTAssertEqual(
                        harness.textView.adjustedInsertionPointRect(nativeRect),
                        nativeRect,
                        "phantom half-spacing at \(caseName); \(context)"
                    )
                    XCTAssertEqual(harness.textView.string, text)
                    XCTAssertEqual(
                        harness.textView.selectedRange(),
                        NSRange(location: caretLocation, length: 0)
                    )
                }
            }
        }
    }

    func testMarkedTextBypassesCenteredCaretWithoutChangingComposition() throws {
        let original = "上一行\n输入位置\n下一行"
        let insertionLocation = (original as NSString).range(of: "输入").location + 1
        let harness = makeHarness(
            text: original,
            textWidth: 280,
            fontSize: 18,
            lineSpacing: 12
        )
        configureAdornmentPixelHarness(
            harness,
            appearance: .aqua,
            usesDarkInk: true
        )
        harness.textView.setSelectedRange(
            NSRange(location: insertionLocation, length: 0)
        )
        harness.textView.setMarkedText(
            "pin",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: insertionLocation, length: 0)
        )
        XCTAssertTrue(harness.textView.hasMarkedText())
        let markedRange = harness.textView.markedRange()
        let selectedRange = harness.textView.selectedRange()
        let composedText = harness.textView.string
        let caretLocation = min(
            selectedRange.location,
            (composedText as NSString).length
        )
        let nativeRect = try nativeInsertionPointRect(
            in: harness.textView,
            at: caretLocation
        )

        XCTAssertEqual(
            harness.textView.adjustedInsertionPointRect(nativeRect),
            nativeRect,
            "IME owns marked-text insertion geometry"
        )
        XCTAssertTrue(harness.textView.hasMarkedText())
        XCTAssertEqual(harness.textView.markedRange(), markedRange)
        XCTAssertEqual(harness.textView.selectedRange(), selectedRange)
        XCTAssertEqual(harness.textView.string, composedText)
    }

    func testManagedImageLineBypassesCenteredGeometryAndPreservesPreviewState() throws {
        let rootURL = makeTemporaryImageRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = NoteImageStore(rootURL: rootURL)
        let asset = try store.importImage(data: makePNGData(width: 32, height: 16))
        let document = makeImageDocument(
            rootURL: rootURL,
            stableKey: "selection-geometry-image"
        )
        let identity = MarkdownEditorDocumentIdentity(document: document)
        let text = "图片上方\n\(asset.markdown)\n图片下方"
        let harness = makeHarness(
            text: text,
            textWidth: 360,
            viewportHeight: 360,
            fontSize: 18,
            lineSpacing: 12,
            documentIdentity: identity,
            imageConfiguration: EditorImageConfiguration(
                documentIdentity: identity,
                store: store,
                isEnabled: true
            )
        )
        configureAdornmentPixelHarness(
            harness,
            appearance: .aqua,
            usesDarkInk: true
        )
        harness.textView.refreshChecklistPresentation(forceLayout: true)
        let match = try XCTUnwrap(MarkdownImage.matches(in: text).first)
        let previewBefore = try XCTUnwrap(
            harness.textView.managedImagePreviewRect(
                atUTF16Offset: match.tokenRange.location
            )
        )
        let undoManager = try XCTUnwrap(harness.textView.undoManager)
        let undoProbe = UndoProbe()
        undoManager.removeAllActions()
        undoManager.registerUndo(withTarget: undoProbe) { $0.didUndo = true }
        harness.textView.setSelectedRange(
            NSRange(location: match.tokenRange.location, length: 0)
        )
        let nativeRect = try nativeInsertionPointRect(
            in: harness.textView,
            at: match.tokenRange.location
        )

        XCTAssertEqual(
            harness.textView.adjustedInsertionPointRect(nativeRect),
            nativeRect,
            "managed-image block height is not ordinary text leading"
        )
        prepareForPixelRendering(harness)
        _ = renderedPixels(of: harness.textView)
        XCTAssertEqual(harness.textView.string, text)
        XCTAssertEqual(harness.textView.managedImageMatches, [match])
        XCTAssertEqual(
            harness.textView.managedImagePreviewRect(
                atUTF16Offset: match.tokenRange.location
            ),
            previewBefore
        )
        XCTAssertTrue(undoManager.canUndo)
    }

    func testInactiveWindowSelectionKeepsCenteredGeometryAndEditorState() throws {
        let text = "上一行\n非活动选区仍需居中\n下一行"
        let selection = (text as NSString).range(of: "选区")

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let baseline = try renderedSelectionGeometry(
                text: text,
                selection: selection,
                appearance: appearance,
                fontSize: 18,
                lineSpacing: 0,
                windowIsKey: false
            )
            let spaced = try renderedSelectionGeometry(
                text: text,
                selection: selection,
                appearance: appearance,
                fontSize: 18,
                lineSpacing: 12,
                windowIsKey: false
            )
            XCTAssertEqual(
                spaced.surface.midY - spaced.ink.midY,
                baseline.surface.midY - baseline.ink.midY,
                accuracy: 1,
                "inactive selection drifted in \(appearance.rawValue)"
            )
            XCTAssertEqual(
                spaced.surface.height - baseline.surface.height,
                12,
                accuracy: 1
            )
            XCTAssertEqual(spaced.surface.minX, baseline.surface.minX, accuracy: 1)
            XCTAssertEqual(spaced.surface.width, baseline.surface.width, accuracy: 1)
        }
    }

    func testMarkedSelectionBackgroundKeepsNativeLineFragmentGeometry() throws {
        let original = "上一行\n输入位置\n下一行"
        let insertionLocation = (original as NSString).range(of: "位置").location

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let harness = makeHarness(
                text: original,
                textWidth: 280,
                fontSize: 18,
                lineSpacing: 12
            )
            let usesDarkInk = appearance == .aqua
            configureAdornmentPixelHarness(
                harness,
                appearance: appearance,
                usesDarkInk: usesDarkInk
            )
            harness.textView.selectedTextAttributes = [
                .backgroundColor: selectionGeometryProbeColor,
                .foregroundColor: usesDarkInk ? NSColor.black : NSColor.white
            ]
            harness.textView.setSelectedRange(
                NSRange(location: insertionLocation, length: 0)
            )
            harness.textView.setMarkedText(
                "pin",
                selectedRange: NSRange(location: 0, length: 3),
                replacementRange: NSRange(location: insertionLocation, length: 0)
            )
            XCTAssertTrue(harness.textView.hasMarkedText())
            let markedRange = harness.textView.markedRange()
            let selectedRange = harness.textView.selectedRange()
            let composedText = harness.textView.string
            prepareForPixelRendering(harness)

            let pixels = renderedPixels(of: harness.textView)
            let width = max(1, Int(harness.textView.bounds.width.rounded(.up)))
            let height = max(1, Int(harness.textView.bounds.height.rounded(.up)))
            let surface = try XCTUnwrap(
                pixelBounds(
                    pixels,
                    width: width,
                    height: height,
                    matches: isSelectionGeometryProbePixel
                )
            )
            let layoutManager = try XCTUnwrap(harness.textView.layoutManager)
            let glyphIndex = layoutManager.glyphIndexForCharacter(
                at: markedRange.location
            )
            let nativeLineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            ).offsetBy(
                dx: harness.textView.textContainerOrigin.x,
                dy: harness.textView.textContainerOrigin.y
            )

            XCTAssertEqual(surface.minY, nativeLineRect.minY, accuracy: 1)
            XCTAssertEqual(surface.height, nativeLineRect.height, accuracy: 1)
            XCTAssertTrue(harness.textView.hasMarkedText())
            XCTAssertEqual(harness.textView.markedRange(), markedRange)
            XCTAssertEqual(harness.textView.selectedRange(), selectedRange)
            XCTAssertEqual(harness.textView.string, composedText)
        }
    }

    func testSelectionBackgroundDrawsAboveHighlightUnderlay() throws {
        let text = "==左侧选择右侧=="
        let harness = makeHarness(
            text: text,
            textWidth: 280,
            fontSize: 18,
            lineSpacing: 12
        )
        harness.window.appearance = NSAppearance(named: .darkAqua)
        harness.scrollView.backgroundColor = .black
        harness.textView.backgroundColor = .black
        harness.textView.textColor = .white
        harness.textView.insertionPointColor = .clear
        harness.textView.selectionMovePresentationDelay = 60
        harness.textView.selectedTextAttributes = [
            .backgroundColor: NSColor(
                srgbRed: 0,
                green: 0.28,
                blue: 1,
                alpha: 1
            ),
            .foregroundColor: NSColor.white
        ]
        harness.textView.refreshChecklistPresentation(forceLayout: true)
        let selectedRange = (text as NSString).range(of: "选择")
        harness.textView.setSelectedRange(selectedRange)
        if let textContainer = harness.textView.textContainer {
            harness.textView.layoutManager?.ensureLayout(for: textContainer)
        }
        harness.scrollView.needsDisplay = true
        harness.textView.needsDisplay = true

        let pixels = renderedPixels(of: harness.scrollView)
        let width = max(1, Int(harness.scrollView.bounds.width.rounded(.up)))
        let height = max(1, Int(harness.scrollView.bounds.height.rounded(.up)))
        let remainingHighlightComponents = yellowPixelComponents(
            pixels,
            width: width,
            height: height
        ).filter { $0.pixelCount > 20 && $0.rect.width > 20 }
        XCTAssertGreaterThanOrEqual(
            remainingHighlightComponents.count,
            2,
            "unselected highlight fragments must remain yellow"
        )
        let layoutManager = try XCTUnwrap(harness.textView.layoutManager)
        let textContainer = try XCTUnwrap(harness.textView.textContainer)
        let selectedGlyphs = layoutManager.glyphRange(
            forCharacterRange: selectedRange,
            actualCharacterRange: nil
        )
        let selectedRect = layoutManager.boundingRect(
            forGlyphRange: selectedGlyphs,
            in: textContainer
        ).offsetBy(
            dx: harness.textView.textContainerOrigin.x,
            dy: harness.textView.textContainerOrigin.y
        )
        let selectedPixels = renderedPixels(
            of: harness.textView,
            in: selectedRect
        )
        let selectedWidth = max(1, Int(selectedRect.width.rounded(.up)))
        let selectedHeight = max(1, Int(selectedRect.height.rounded(.up)))
        XCTAssertGreaterThan(
            blueDominantPixelCount(
                selectedPixels,
                width: selectedWidth,
                height: selectedHeight
            ),
            20
        )
        XCTAssertTrue(
            yellowPixelComponents(
                selectedPixels,
                width: selectedWidth,
                height: selectedHeight
            ).filter { $0.pixelCount > 8 }.isEmpty,
            "selection pixels must cover the yellow underlay"
        )
        XCTAssertEqual(harness.textView.string, text)
        XCTAssertEqual(harness.textView.selectedRange(), selectedRange)
    }

    func testHighlightUnderlayComposesWithCompletedTodoAndBoldWithoutStateMutation() throws {
        let text = "- [x] **==完成任务==**"
        let harness = makeHarness(
            text: text,
            textWidth: 320,
            fontSize: 18,
            lineSpacing: 7
        )
        harness.textView.undoManager?.removeAllActions()
        harness.textView.refreshChecklistPresentation(forceLayout: true)
        let matches = MarkdownInlineFormat.matches(in: text)
        let highlight = try XCTUnwrap(
            matches.first(where: { $0.format == .highlight })
        )
        let font = try XCTUnwrap(
            harness.textView.textStorage?.attribute(
                .font,
                at: highlight.contentRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        XCTAssertTrue(
            NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        )
        XCTAssertNotNil(
            harness.textView.layoutManager?.temporaryAttribute(
                .strikethroughStyle,
                atCharacterIndex: highlight.contentRange.location,
                effectiveRange: nil
            )
        )
        XCTAssertNil(
            harness.textView.layoutManager?.temporaryAttribute(
                .backgroundColor,
                atCharacterIndex: highlight.contentRange.location,
                effectiveRange: nil
            )
        )
        XCTAssertEqual(MarkdownChecklist.checkboxMatches(in: text).count, 1)
        XCTAssertEqual(harness.textView.string, text)
        XCTAssertFalse(harness.textView.undoManager?.canUndo ?? true)
    }

    func testCompletedTodoPresentationComposesWithBoldContent() throws {
        let text = "- [x] **完成任务**"
        let harness = makeHarness(text: text, textWidth: 360)
        harness.textView.refreshChecklistPresentation(forceLayout: true)
        let layoutManager = try XCTUnwrap(harness.textView.layoutManager)
        let boldMatch = try XCTUnwrap(
            MarkdownInlineFormat.matches(in: text).first(where: {
                $0.format == .bold
            })
        )
        let location = boldMatch.contentRange.location
        let boldFont = try XCTUnwrap(
            harness.textView.textStorage?.attribute(
                .font,
                at: location,
                effectiveRange: nil
            ) as? NSFont
        )

        XCTAssertTrue(
            NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask)
        )
        XCTAssertNotNil(
            layoutManager.temporaryAttribute(
                .strikethroughStyle,
                atCharacterIndex: location,
                effectiveRange: nil
            )
        )
        XCTAssertNotNil(
            layoutManager.temporaryAttribute(
                .foregroundColor,
                atCharacterIndex: location,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertEqual(harness.textView.string, text)
    }

    func testInlineFormatDelimitersAreNullGlyphsWithZeroVisualWidth() throws {
        let text = "**粗体** ==高亮== **==嵌套==**"
        let harness = makeHarness(text: text, textWidth: 480)
        let layoutManager = try XCTUnwrap(harness.textView.layoutManager)
        let textContainer = try XCTUnwrap(harness.textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let matches = MarkdownInlineFormat.matches(in: text)
        XCTAssertEqual(matches.count, 4)

        for delimiter in matches.flatMap({
            [$0.openingDelimiterRange, $0.closingDelimiterRange]
        }) {
            for characterIndex in delimiter.location..<NSMaxRange(delimiter) {
                let glyphIndex = layoutManager.glyphIndexForCharacter(
                    at: characterIndex
                )
                XCTAssertTrue(
                    layoutManager.propertyForGlyph(at: glyphIndex).contains(.null),
                    "delimiter UTF-16 offset \(characterIndex) must be folded"
                )
            }
        }

        let bold = try XCTUnwrap(matches.first(where: {
            $0.format == .bold && (text as NSString).substring(with: $0.contentRange) == "粗体"
        }))
        let tokenGlyphs = layoutManager.glyphRange(
            forCharacterRange: bold.tokenRange,
            actualCharacterRange: nil
        )
        let contentGlyphs = layoutManager.glyphRange(
            forCharacterRange: bold.contentRange,
            actualCharacterRange: nil
        )
        let tokenWidth = layoutManager.boundingRect(
            forGlyphRange: tokenGlyphs,
            in: textContainer
        ).width
        let contentWidth = layoutManager.boundingRect(
            forGlyphRange: contentGlyphs,
            in: textContainer
        ).width
        XCTAssertEqual(tokenWidth, contentWidth, accuracy: 0.5)

        let invalid = makeHarness(text: "**未闭合", textWidth: 240)
        let invalidLayout = try XCTUnwrap(invalid.textView.layoutManager)
        let invalidContainer = try XCTUnwrap(invalid.textView.textContainer)
        invalidLayout.ensureLayout(for: invalidContainer)
        for characterIndex in 0..<2 {
            let glyphIndex = invalidLayout.glyphIndexForCharacter(at: characterIndex)
            XCTAssertFalse(
                invalidLayout.propertyForGlyph(at: glyphIndex).contains(.null)
            )
        }
    }

    func testStorageBackedBoldChangesRenderedPixels() throws {
        let text = "**MMMMMMMM**"
        let harness = makeHarness(text: text, textWidth: 300, viewportHeight: 90)
        harness.textView.insertionPointColor = .clear
        harness.window.makeFirstResponder(nil)
        harness.textView.refreshChecklistPresentation(forceLayout: true)
        let formattedPixels = renderedPixels(of: harness.textView)

        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let regular = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        harness.textView.textStorage?.addAttribute(
            .font,
            value: regular,
            range: fullRange
        )
        let layoutManager = try XCTUnwrap(harness.textView.layoutManager)
        layoutManager.invalidateGlyphs(
            forCharacterRange: fullRange,
            changeInLength: 0,
            actualCharacterRange: nil
        )
        layoutManager.invalidateLayout(
            forCharacterRange: fullRange,
            actualCharacterRange: nil
        )
        layoutManager.invalidateDisplay(forCharacterRange: fullRange)
        harness.textView.needsDisplay = true
        if let textContainer = harness.textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        let regularPixels = renderedPixels(of: harness.textView)

        XCTAssertGreaterThan(differingBytes(formattedPixels, regularPixels), 100)
        XCTAssertEqual(harness.textView.string, text)
    }

    func testExternalFontSizeRefreshKeepsBoldAndTypingFontRegular() throws {
        let text = "**字号变化**"
        let harness = makeHarness(text: text, textWidth: 320, fontSize: 15)
        let match = try XCTUnwrap(MarkdownInlineFormat.matches(in: text).first)
        harness.textView.setSelectedRange(match.contentRange)

        XCTAssertFalse(harness.textView.updateBaseFontSizeIfNeeded(15))
        harness.textView.refreshChecklistPresentation()
        var boldFont = try XCTUnwrap(
            harness.textView.textStorage?.attribute(
                .font,
                at: match.contentRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        XCTAssertTrue(harness.textView.updateBaseFontSizeIfNeeded(22))
        harness.textView.updateChecklistStyle(
            fontSize: 22,
            completedTextColor: .secondaryLabelColor,
            successColor: .systemGreen,
            checkmarkColor: .textBackgroundColor,
            accentColor: .controlAccentColor,
            hoverBackgroundColor: .controlBackgroundColor
        )
        harness.textView.refreshChecklistPresentation(forceLayout: true)
        boldFont = try XCTUnwrap(
            harness.textView.textStorage?.attribute(
                .font,
                at: match.contentRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        XCTAssertEqual(boldFont.pointSize, 22, accuracy: 0.01)
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
        let typingFont = try XCTUnwrap(
            harness.textView.typingAttributes[.font] as? NSFont
        )
        XCTAssertEqual(typingFont.pointSize, 22, accuracy: 0.01)
        XCTAssertFalse(
            NSFontManager.shared.traits(of: typingFont).contains(.boldFontMask)
        )
    }

    func testArrowAndShiftArrowSkipHiddenDelimitersWithoutBrokenSelections() {
        let text = "x**ab**y"
        let harness = makeHarness(text: text, textWidth: 320)

        harness.textView.setSelectedRange(NSRange(location: 1, length: 0))
        harness.textView.moveRight(nil)
        XCTAssertEqual(harness.textView.selectedRange().location, 4)
        harness.textView.moveRight(nil)
        XCTAssertEqual(harness.textView.selectedRange().location, 7)
        harness.textView.moveLeft(nil)
        XCTAssertEqual(harness.textView.selectedRange().location, 4)
        harness.textView.setSelectedRange(NSRange(location: 3, length: 0))
        harness.textView.moveLeft(nil)
        XCTAssertEqual(harness.textView.selectedRange().location, 0)

        harness.textView.setSelectedRange(NSRange(location: 0, length: 0))
        harness.textView.moveRightAndModifySelection(nil)
        XCTAssertEqual(selectedSubstring(in: harness.textView), "x")
        harness.textView.moveRightAndModifySelection(nil)
        XCTAssertEqual(selectedSubstring(in: harness.textView), "x**ab**")
        harness.textView.moveLeftAndModifySelection(nil)
        XCTAssertEqual(selectedSubstring(in: harness.textView), "x")
        harness.textView.moveLeftAndModifySelection(nil)
        XCTAssertEqual(harness.textView.selectedRange().length, 0)

        harness.textView.setSelectedRange(NSRange(location: 8, length: 0))
        harness.textView.moveLeftAndModifySelection(nil)
        XCTAssertEqual(selectedSubstring(in: harness.textView), "y")
        harness.textView.moveLeftAndModifySelection(nil)
        XCTAssertEqual(selectedSubstring(in: harness.textView), "**ab**y")
        harness.textView.moveRightAndModifySelection(nil)
        XCTAssertEqual(selectedSubstring(in: harness.textView), "y")
    }

    func testBackspaceDeleteAndFullContentDeletionKeepTokensAtomic() throws {
        let text = "A**BC**Z"
        let match = try XCTUnwrap(MarkdownInlineFormat.matches(in: text).first)

        let backward = makeHarness(text: text, textWidth: 320)
        backward.textView.undoManager?.removeAllActions()
        backward.textView.setSelectedRange(
            NSRange(location: NSMaxRange(match.tokenRange), length: 0)
        )
        backward.textView.deleteBackward(nil)
        XCTAssertEqual(backward.textView.string, "A**B**Z")
        XCTAssertFalse(backward.textView.string.contains("***"))
        backward.textView.undoManager?.undo()
        XCTAssertEqual(backward.textView.string, text)
        backward.textView.undoManager?.redo()
        XCTAssertEqual(backward.textView.string, "A**B**Z")

        let forward = makeHarness(text: text, textWidth: 320)
        forward.textView.setSelectedRange(
            NSRange(location: match.tokenRange.location, length: 0)
        )
        forward.textView.deleteForward(nil)
        XCTAssertEqual(forward.textView.string, "A**C**Z")

        let fullContent = makeHarness(text: text, textWidth: 320)
        fullContent.textView.setSelectedRange(match.contentRange)
        fullContent.textView.deleteBackward(nil)
        XCTAssertEqual(fullContent.textView.string, "AZ")

        let nestedText = "**==中==**"
        let nested = makeHarness(text: nestedText, textWidth: 320)
        nested.textView.setSelectedRange(
            NSRange(location: (nestedText as NSString).length, length: 0)
        )
        nested.textView.deleteBackward(nil)
        XCTAssertEqual(nested.textView.string, "")
    }

    func testBackspaceAtFormattedTodoStartRemovesWholeChecklistPrefix() throws {
        let text = "- [ ] **x**"
        let harness = makeHarness(text: text, textWidth: 320)
        let match = try XCTUnwrap(MarkdownInlineFormat.matches(in: text).first)
        harness.textView.undoManager?.removeAllActions()
        harness.textView.setSelectedRange(
            NSRange(location: match.contentRange.location, length: 0)
        )

        harness.textView.deleteBackward(nil)
        XCTAssertEqual(harness.textView.string, "**x**")
        harness.textView.undoManager?.undo()
        XCTAssertEqual(harness.textView.string, text)
    }

    func testCutAndMoveCanonicalizeFormattedContentWithoutOrphans() throws {
        let text = "A**粗体**Z"
        let match = try XCTUnwrap(MarkdownInlineFormat.matches(in: text).first)
        let cutHarness = makeHarness(text: text, textWidth: 320)
        NSPasteboard.general.clearContents()
        cutHarness.textView.setSelectedRange(match.contentRange)
        cutHarness.textView.cut(nil)
        XCTAssertEqual(cutHarness.textView.string, "AZ")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "**粗体**")

        let nestedText = "A**==嵌套==**Z"
        let nestedMatch = try XCTUnwrap(
            MarkdownInlineFormat.matches(in: nestedText).first(where: {
                $0.format == .bold
            })
        )
        let nestedHarness = makeHarness(text: nestedText, textWidth: 320)
        NSPasteboard.general.clearContents()
        nestedHarness.textView.setSelectedRange(nestedMatch.contentRange)
        nestedHarness.textView.cut(nil)
        XCTAssertEqual(nestedHarness.textView.string, "AZ")
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            "**==嵌套==**"
        )

        var movedSnapshot: EditorSelectionSnapshot?
        let configuration = EditorSelectionMoveConfiguration(
            sourceDocument: makeDocument(scope: .task),
            destinationDocument: makeDocument(scope: .project),
            selectionStableKey: "formatted-move",
            title: "移动",
            isEnabled: true
        ) { snapshot in
            movedSnapshot = snapshot
        }
        let moveHarness = makeHarness(
            text: text,
            textWidth: 360,
            selectionMoveConfiguration: configuration
        )
        moveHarness.textView.selectionMovePresentationDelay = 0
        moveHarness.textView.setSelectedRange(match.contentRange)
        XCTAssertTrue(waitUntil {
            moveHarness.textView.visibleSelectionToolbarMoveButton != nil
        })
        try XCTUnwrap(
            moveHarness.textView.visibleSelectionToolbarMoveButton
        ).performClick(nil)
        let snapshot = try XCTUnwrap(movedSnapshot)
        XCTAssertEqual(snapshot.range, match.tokenRange)
        XCTAssertEqual(snapshot.selectedText, "**粗体**")
        XCTAssertEqual(
            (snapshot.sourceText as NSString).replacingCharacters(
                in: snapshot.range,
                with: ""
            ),
            "AZ"
        )
    }

    func testLegacyAdjacentFormatTokensRemainFullyFolded() throws {
        let text = "**甲****乙** ==丙====丁=="
        let harness = makeHarness(text: text, textWidth: 360)
        let layoutManager = try XCTUnwrap(harness.textView.layoutManager)
        let textContainer = try XCTUnwrap(harness.textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let matches = MarkdownInlineFormat.matches(in: text)
        XCTAssertEqual(matches.count, 4)
        for range in matches.flatMap({
            [$0.openingDelimiterRange, $0.closingDelimiterRange]
        }) {
            for characterIndex in range.location..<NSMaxRange(range) {
                let glyph = layoutManager.glyphIndexForCharacter(at: characterIndex)
                XCTAssertTrue(layoutManager.propertyForGlyph(at: glyph).contains(.null))
            }
        }
    }

    func testReturnSplitsInlineFormatsAndRemovesEmptyWrappers() throws {
        let partialText = "**abc**"
        let partial = makeHarness(text: partialText, textWidth: 320)
        partial.textView.undoManager?.removeAllActions()
        partial.textView.setSelectedRange(NSRange(location: 3, length: 1))
        partial.textView.insertNewline(nil)
        XCTAssertEqual(partial.textView.string, "**a**\n**c**")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: partial.textView.string).count, 2)
        partial.textView.undoManager?.undo()
        XCTAssertEqual(partial.textView.string, partialText)

        let full = makeHarness(text: partialText, textWidth: 320)
        full.textView.setSelectedRange(NSRange(location: 2, length: 3))
        full.textView.insertNewline(nil)
        XCTAssertEqual(full.textView.string, "\n")
        XCTAssertTrue(MarkdownInlineFormat.matches(in: full.textView.string).isEmpty)

        let todoText = "- [ ] **abc**"
        let todo = makeHarness(text: todoText, textWidth: 320)
        todo.textView.undoManager?.removeAllActions()
        todo.textView.setSelectedRange(NSRange(location: 9, length: 1))
        todo.textView.insertNewline(nil)
        XCTAssertEqual(todo.textView.string, "- [ ] **a**\n- [ ] **c**")
        XCTAssertEqual(MarkdownChecklist.checkboxMatches(in: todo.textView.string).count, 2)
        XCTAssertEqual(MarkdownInlineFormat.matches(in: todo.textView.string).count, 2)
        todo.textView.undoManager?.undo()
        XCTAssertEqual(todo.textView.string, todoText)
    }

    func testMultilineInsertionClosesAndReopensBoldHighlightAndCRLF() throws {
        let boldText = "**ab**"
        let bold = makeHarness(text: boldText, textWidth: 320)
        bold.textView.undoManager?.removeAllActions()
        bold.textView.setSelectedRange(NSRange(location: 3, length: 0))
        bold.textView.insertText(
            "X\nY",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(bold.textView.string, "**aX**\n**Yb**")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: bold.textView.string).count, 2)
        bold.textView.undoManager?.undo()
        XCTAssertEqual(bold.textView.string, boldText)
        bold.textView.undoManager?.redo()
        XCTAssertEqual(bold.textView.string, "**aX**\n**Yb**")

        let nestedText = "**==ab==**"
        let nested = makeHarness(text: nestedText, textWidth: 320)
        nested.textView.setSelectedRange(NSRange(location: 5, length: 0))
        nested.textView.insertText(
            "X\r\nY",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(
            nested.textView.string,
            "**==aX==**\r\n**==Yb==**"
        )
        XCTAssertEqual(MarkdownInlineFormat.matches(in: nested.textView.string).count, 4)

        let highlightText = "==ab=="
        let highlight = makeHarness(text: highlightText, textWidth: 320)
        highlight.textView.setSelectedRange(NSRange(location: 3, length: 0))
        highlight.textView.insertText(
            "X\n\nY",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(highlight.textView.string, "==aX==\n\n==Yb==")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: highlight.textView.string).count, 2)
    }

    func testNestedMultilineInsertionAtVisibleContentEdgesDropsEmptyWrappers() throws {
        let original = "**==ab==**"

        let leading = makeHarness(text: original, textWidth: 320)
        leading.textView.undoManager?.removeAllActions()
        leading.textView.setSelectedRange(NSRange(location: 4, length: 0))
        leading.textView.insertText(
            "\nY",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(leading.textView.string, "\n**==Yab==**")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: leading.textView.string).count, 2)
        XCTAssertFalse(leading.textView.string.contains("**====**"))
        leading.textView.undoManager?.undo()
        XCTAssertEqual(leading.textView.string, original)
        leading.textView.undoManager?.redo()
        XCTAssertEqual(leading.textView.string, "\n**==Yab==**")

        let trailing = makeHarness(text: original, textWidth: 320)
        trailing.textView.undoManager?.removeAllActions()
        trailing.textView.setSelectedRange(NSRange(location: 6, length: 0))
        trailing.textView.insertText(
            "X\r\n",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(trailing.textView.string, "**==abX==**\r\n")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: trailing.textView.string).count, 2)
        XCTAssertFalse(trailing.textView.string.contains("**====**"))
        trailing.textView.undoManager?.undo()
        XCTAssertEqual(trailing.textView.string, original)
        trailing.textView.undoManager?.redo()
        XCTAssertEqual(trailing.textView.string, "**==abX==**\r\n")

        let reversedOriginal = "==**ab**=="
        let reversedLeading = makeHarness(text: reversedOriginal, textWidth: 320)
        reversedLeading.textView.undoManager?.removeAllActions()
        reversedLeading.textView.setSelectedRange(NSRange(location: 4, length: 0))
        reversedLeading.textView.insertText(
            "\r\nY",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(reversedLeading.textView.string, "\r\n==**Yab**==")
        XCTAssertEqual(
            MarkdownInlineFormat.matches(in: reversedLeading.textView.string).count,
            2
        )
        XCTAssertFalse(reversedLeading.textView.string.contains("==****=="))
        reversedLeading.textView.undoManager?.undo()
        XCTAssertEqual(reversedLeading.textView.string, reversedOriginal)
        reversedLeading.textView.undoManager?.redo()
        XCTAssertEqual(reversedLeading.textView.string, "\r\n==**Yab**==")

        let reversedTrailing = makeHarness(text: reversedOriginal, textWidth: 320)
        reversedTrailing.textView.undoManager?.removeAllActions()
        reversedTrailing.textView.setSelectedRange(NSRange(location: 6, length: 0))
        reversedTrailing.textView.insertText(
            "X\n",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(reversedTrailing.textView.string, "==**abX**==\n")
        XCTAssertEqual(
            MarkdownInlineFormat.matches(in: reversedTrailing.textView.string).count,
            2
        )
        XCTAssertFalse(reversedTrailing.textView.string.contains("==****=="))
        reversedTrailing.textView.undoManager?.undo()
        XCTAssertEqual(reversedTrailing.textView.string, reversedOriginal)
        reversedTrailing.textView.undoManager?.redo()
        XCTAssertEqual(reversedTrailing.textView.string, "==**abX**==\n")
    }

    func testNestedMultilineInsertionCanonicalizesWhitespaceEdgeSplits() throws {
        let boldOutside = "**pre ==ab== post**"
        let boldLeading = makeHarness(text: boldOutside, textWidth: 360)
        boldLeading.textView.undoManager?.removeAllActions()
        boldLeading.textView.setSelectedRange(NSRange(location: 8, length: 0))
        boldLeading.textView.insertText(
            "\nY",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(boldLeading.textView.string, "**pre** \n**==Yab== post**")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: boldLeading.textView.string).count, 3)
        boldLeading.textView.undoManager?.undo()
        XCTAssertEqual(boldLeading.textView.string, boldOutside)
        boldLeading.textView.undoManager?.redo()
        XCTAssertEqual(boldLeading.textView.string, "**pre** \n**==Yab== post**")

        let boldReturn = makeHarness(text: boldOutside, textWidth: 360)
        boldReturn.textView.undoManager?.removeAllActions()
        boldReturn.textView.setSelectedRange(NSRange(location: 8, length: 0))
        boldReturn.textView.insertNewline(nil)
        XCTAssertEqual(boldReturn.textView.string, "**pre** \n**==ab== post**")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: boldReturn.textView.string).count, 3)

        let fullInnerSelection = makeHarness(text: boldOutside, textWidth: 360)
        fullInnerSelection.textView.undoManager?.removeAllActions()
        fullInnerSelection.textView.setSelectedRange(NSRange(location: 8, length: 2))
        fullInnerSelection.textView.insertNewline(nil)
        XCTAssertEqual(fullInnerSelection.textView.string, "**pre** \n **post**")
        XCTAssertEqual(
            MarkdownInlineFormat.matches(in: fullInnerSelection.textView.string).count,
            2
        )
        fullInnerSelection.textView.undoManager?.undo()
        XCTAssertEqual(fullInnerSelection.textView.string, boldOutside)
        fullInnerSelection.textView.undoManager?.redo()
        XCTAssertEqual(fullInnerSelection.textView.string, "**pre** \n **post**")

        let boldTrailing = makeHarness(text: boldOutside, textWidth: 360)
        boldTrailing.textView.undoManager?.removeAllActions()
        boldTrailing.textView.setSelectedRange(NSRange(location: 10, length: 0))
        boldTrailing.textView.insertText(
            "X\r\n",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(
            boldTrailing.textView.string,
            "**pre ==abX==**\r\n **post**"
        )
        XCTAssertEqual(MarkdownInlineFormat.matches(in: boldTrailing.textView.string).count, 3)
        boldTrailing.textView.undoManager?.undo()
        XCTAssertEqual(boldTrailing.textView.string, boldOutside)
        boldTrailing.textView.undoManager?.redo()
        XCTAssertEqual(
            boldTrailing.textView.string,
            "**pre ==abX==**\r\n **post**"
        )

        let highlightOutside = "==pre **ab** post=="
        let highlightLeading = makeHarness(text: highlightOutside, textWidth: 360)
        highlightLeading.textView.undoManager?.removeAllActions()
        highlightLeading.textView.setSelectedRange(NSRange(location: 8, length: 0))
        highlightLeading.textView.insertText(
            "\r\nY",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(
            highlightLeading.textView.string,
            "==pre== \r\n==**Yab** post=="
        )
        XCTAssertEqual(
            MarkdownInlineFormat.matches(in: highlightLeading.textView.string).count,
            3
        )
        highlightLeading.textView.undoManager?.undo()
        XCTAssertEqual(highlightLeading.textView.string, highlightOutside)
        highlightLeading.textView.undoManager?.redo()
        XCTAssertEqual(
            highlightLeading.textView.string,
            "==pre== \r\n==**Yab** post=="
        )

        let highlightTrailing = makeHarness(text: highlightOutside, textWidth: 360)
        highlightTrailing.textView.undoManager?.removeAllActions()
        highlightTrailing.textView.setSelectedRange(NSRange(location: 10, length: 0))
        highlightTrailing.textView.insertText(
            "X\n",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(
            highlightTrailing.textView.string,
            "==pre **abX**==\n ==post=="
        )
        XCTAssertEqual(
            MarkdownInlineFormat.matches(in: highlightTrailing.textView.string).count,
            3
        )
        highlightTrailing.textView.undoManager?.undo()
        XCTAssertEqual(highlightTrailing.textView.string, highlightOutside)
        highlightTrailing.textView.undoManager?.redo()
        XCTAssertEqual(
            highlightTrailing.textView.string,
            "==pre **abX**==\n ==post=="
        )
    }

    func testMultilineInsertionMovesBoundaryWhitespaceOutsideWrappers() throws {
        for delimiter in ["**", "=="] {
            let original = "\(delimiter)a b\(delimiter)"

            let beforeSpace = makeHarness(text: original, textWidth: 320)
            beforeSpace.textView.undoManager?.removeAllActions()
            beforeSpace.textView.setSelectedRange(NSRange(location: 3, length: 0))
            beforeSpace.textView.insertNewline(nil)
            XCTAssertEqual(
                beforeSpace.textView.string,
                "\(delimiter)a\(delimiter)\n \(delimiter)b\(delimiter)"
            )
            XCTAssertEqual(
                MarkdownInlineFormat.matches(in: beforeSpace.textView.string).count,
                2
            )
            beforeSpace.textView.undoManager?.undo()
            XCTAssertEqual(beforeSpace.textView.string, original)
            beforeSpace.textView.undoManager?.redo()
            XCTAssertEqual(
                beforeSpace.textView.string,
                "\(delimiter)a\(delimiter)\n \(delimiter)b\(delimiter)"
            )

            let afterSpace = makeHarness(text: original, textWidth: 320)
            afterSpace.textView.undoManager?.removeAllActions()
            afterSpace.textView.setSelectedRange(NSRange(location: 4, length: 0))
            afterSpace.textView.insertText(
                "\r\n",
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            XCTAssertEqual(
                afterSpace.textView.string,
                "\(delimiter)a\(delimiter) \r\n\(delimiter)b\(delimiter)"
            )
            XCTAssertEqual(
                MarkdownInlineFormat.matches(in: afterSpace.textView.string).count,
                2
            )
            afterSpace.textView.undoManager?.undo()
            XCTAssertEqual(afterSpace.textView.string, original)
            afterSpace.textView.undoManager?.redo()
            XCTAssertEqual(
                afterSpace.textView.string,
                "\(delimiter)a\(delimiter) \r\n\(delimiter)b\(delimiter)"
            )
        }
    }

    func testSingleLineWhitespaceAtContentEdgesMovesOutsideWrappers() throws {
        for delimiter in ["**", "=="] {
            let original = "\(delimiter)a\(delimiter)"

            let leading = makeHarness(text: original, textWidth: 320)
            leading.textView.undoManager?.removeAllActions()
            leading.textView.setSelectedRange(NSRange(location: 2, length: 0))
            leading.textView.insertText(
                " ",
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            XCTAssertEqual(leading.textView.string, " \(original)")
            XCTAssertEqual(leading.textView.selectedRange(), NSRange(location: 1, length: 0))
            XCTAssertEqual(MarkdownInlineFormat.matches(in: leading.textView.string).count, 1)
            leading.textView.undoManager?.undo()
            XCTAssertEqual(leading.textView.string, original)
            leading.textView.undoManager?.redo()
            XCTAssertEqual(leading.textView.string, " \(original)")

            let leadingAffinity = makeHarness(text: original, textWidth: 320)
            leadingAffinity.textView.setSelectedRange(NSRange(location: 2, length: 0))
            leadingAffinity.textView.insertText(
                " ",
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            leadingAffinity.textView.insertText(
                "X",
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            XCTAssertEqual(leadingAffinity.textView.string, " X\(original)")

            let trailing = makeHarness(text: original, textWidth: 320)
            trailing.textView.undoManager?.removeAllActions()
            trailing.textView.setSelectedRange(NSRange(location: 3, length: 0))
            trailing.textView.insertText(
                "\t",
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            XCTAssertEqual(trailing.textView.string, "\(original)\t")
            XCTAssertEqual(MarkdownInlineFormat.matches(in: trailing.textView.string).count, 1)
            trailing.textView.undoManager?.undo()
            XCTAssertEqual(trailing.textView.string, original)
            trailing.textView.undoManager?.redo()
            XCTAssertEqual(trailing.textView.string, "\(original)\t")
        }

        let nested = "**==ab==**"
        let nestedLeading = makeHarness(text: nested, textWidth: 320)
        nestedLeading.textView.undoManager?.removeAllActions()
        nestedLeading.textView.setSelectedRange(NSRange(location: 4, length: 0))
        nestedLeading.textView.insertText(
            " ",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(nestedLeading.textView.string, " \(nested)")
        XCTAssertEqual(nestedLeading.textView.selectedRange(), NSRange(location: 1, length: 0))
        XCTAssertEqual(MarkdownInlineFormat.matches(in: nestedLeading.textView.string).count, 2)
        nestedLeading.textView.undoManager?.undo()
        XCTAssertEqual(nestedLeading.textView.string, nested)

        let nestedTrailing = makeHarness(text: nested, textWidth: 320)
        nestedTrailing.textView.undoManager?.removeAllActions()
        nestedTrailing.textView.setSelectedRange(NSRange(location: 6, length: 0))
        nestedTrailing.textView.insertText(
            "\t",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(nestedTrailing.textView.string, "\(nested)\t")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: nestedTrailing.textView.string).count, 2)
        nestedTrailing.textView.undoManager?.undo()
        XCTAssertEqual(nestedTrailing.textView.string, nested)

        let mixed = "**pre ==ab== post**"
        let mixedLeading = makeHarness(text: mixed, textWidth: 360)
        mixedLeading.textView.undoManager?.removeAllActions()
        mixedLeading.textView.setSelectedRange(NSRange(location: 8, length: 0))
        mixedLeading.textView.insertText(
            " ",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(mixedLeading.textView.string, "**pre  ==ab== post**")
        XCTAssertEqual(mixedLeading.textView.selectedRange(), NSRange(location: 7, length: 0))
        XCTAssertEqual(MarkdownInlineFormat.matches(in: mixedLeading.textView.string).count, 2)
        mixedLeading.textView.undoManager?.undo()
        XCTAssertEqual(mixedLeading.textView.string, mixed)

        let mixedTrailing = makeHarness(text: mixed, textWidth: 360)
        mixedTrailing.textView.undoManager?.removeAllActions()
        mixedTrailing.textView.setSelectedRange(NSRange(location: 10, length: 0))
        mixedTrailing.textView.insertText(
            "\t",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(mixedTrailing.textView.string, "**pre ==ab==\t post**")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: mixedTrailing.textView.string).count, 2)
        mixedTrailing.textView.undoManager?.undo()
        XCTAssertEqual(mixedTrailing.textView.string, mixed)
    }

    func testBoundaryCharacterDeletionCanonicalizesRemainingWhitespace() throws {
        for delimiter in ["**", "=="] {
            let original = "\(delimiter)a b\(delimiter)"

            let backward = makeHarness(text: original, textWidth: 320)
            backward.textView.undoManager?.removeAllActions()
            backward.textView.setSelectedRange(NSRange(location: 3, length: 0))
            backward.textView.deleteBackward(nil)
            XCTAssertEqual(backward.textView.string, " \(delimiter)b\(delimiter)")
            XCTAssertEqual(backward.textView.selectedRange(), NSRange(location: 0, length: 0))
            XCTAssertEqual(MarkdownInlineFormat.matches(in: backward.textView.string).count, 1)
            backward.textView.undoManager?.undo()
            XCTAssertEqual(backward.textView.string, original)
            backward.textView.undoManager?.redo()
            XCTAssertEqual(backward.textView.string, " \(delimiter)b\(delimiter)")

            let forward = makeHarness(text: original, textWidth: 320)
            forward.textView.undoManager?.removeAllActions()
            forward.textView.setSelectedRange(NSRange(location: 4, length: 0))
            forward.textView.deleteForward(nil)
            XCTAssertEqual(forward.textView.string, "\(delimiter)a\(delimiter) ")
            XCTAssertEqual(forward.textView.selectedRange(), NSRange(location: 6, length: 0))
            XCTAssertEqual(MarkdownInlineFormat.matches(in: forward.textView.string).count, 1)
            forward.textView.undoManager?.undo()
            XCTAssertEqual(forward.textView.string, original)
            forward.textView.undoManager?.redo()
            XCTAssertEqual(forward.textView.string, "\(delimiter)a\(delimiter) ")
        }

        let nested = "**==a b==**"
        let nestedBackward = makeHarness(text: nested, textWidth: 320)
        nestedBackward.textView.undoManager?.removeAllActions()
        nestedBackward.textView.setSelectedRange(NSRange(location: 5, length: 0))
        nestedBackward.textView.deleteBackward(nil)
        XCTAssertEqual(nestedBackward.textView.string, " **==b==**")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: nestedBackward.textView.string).count, 2)
        nestedBackward.textView.undoManager?.undo()
        XCTAssertEqual(nestedBackward.textView.string, nested)

        let nestedForward = makeHarness(text: nested, textWidth: 320)
        nestedForward.textView.undoManager?.removeAllActions()
        nestedForward.textView.setSelectedRange(NSRange(location: 6, length: 0))
        nestedForward.textView.deleteForward(nil)
        XCTAssertEqual(nestedForward.textView.string, "**==a==** ")
        XCTAssertEqual(MarkdownInlineFormat.matches(in: nestedForward.textView.string).count, 2)
        nestedForward.textView.undoManager?.undo()
        XCTAssertEqual(nestedForward.textView.string, nested)
    }

    func testUnsafeBoundaryDeletionIsConsumedWithoutBreakingMarkdown() throws {
        for original in ["**a*b**", "==a=b=="] {
            let backward = makeHarness(text: original, textWidth: 320)
            backward.textView.undoManager?.removeAllActions()
            backward.textView.setSelectedRange(NSRange(location: 3, length: 0))
            backward.textView.deleteBackward(nil)
            XCTAssertEqual(backward.textView.string, original)
            XCTAssertFalse(backward.textView.undoManager?.canUndo ?? true)
            assertEveryInlineDelimiterIsRecognized(backward.textView.string)

            let forward = makeHarness(text: original, textWidth: 320)
            forward.textView.undoManager?.removeAllActions()
            forward.textView.setSelectedRange(NSRange(location: 4, length: 0))
            forward.textView.deleteForward(nil)
            XCTAssertEqual(forward.textView.string, original)
            XCTAssertFalse(forward.textView.undoManager?.canUndo ?? true)
            assertEveryInlineDelimiterIsRecognized(forward.textView.string)
        }
    }

    func testBoundaryDeletionKeepsCaretInsideRemainingFormattedContent() throws {
        let cases: [(source: String, caret: Int, expected: String, insertion: String)] = [
            ("**a=b**", 3, "**=b**", "**X=b**"),
            ("==a*b==", 3, "==*b==", "==X*b=="),
            ("**==a*b==**", 5, "**==*b==**", "**==X*b==**")
        ]

        for item in cases {
            let harness = makeHarness(text: item.source, textWidth: 360)
            harness.textView.undoManager?.removeAllActions()
            harness.textView.setSelectedRange(NSRange(location: item.caret, length: 0))
            harness.textView.deleteBackward(nil)
            XCTAssertEqual(harness.textView.string, item.expected)
            let matches = MarkdownInlineFormat.matches(in: harness.textView.string)
            let contentStart = try XCTUnwrap(matches.last?.contentRange.location)
            XCTAssertEqual(
                harness.textView.selectedRange(),
                NSRange(location: contentStart, length: 0)
            )
            harness.textView.insertText(
                "X",
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            XCTAssertEqual(harness.textView.string, item.insertion)
            assertEveryInlineDelimiterIsRecognized(harness.textView.string)
            harness.textView.undoManager?.undo()
            XCTAssertEqual(harness.textView.string, item.source)
        }
    }

    func testCanonicalInlineReplacementHandlesInsertedWhitespaceAndRejectsRawMarkers() throws {
        let original = "**==ab==**"
        let harness = makeHarness(text: original, textWidth: 360)
        harness.textView.undoManager?.removeAllActions()
        harness.textView.setSelectedRange(NSRange(location: 5, length: 0))
        harness.textView.insertText(
            " X \n Y ",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(harness.textView.string, "**==a X==** \n **==Y b==**")
        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 20, length: 0))
        XCTAssertEqual(MarkdownInlineFormat.matches(in: harness.textView.string).count, 4)
        harness.textView.undoManager?.undo()
        XCTAssertEqual(harness.textView.string, original)
        harness.textView.undoManager?.redo()
        XCTAssertEqual(harness.textView.string, "**==a X==** \n **==Y b==**")

        let rawMarkers = makeHarness(text: "**ab**", textWidth: 320)
        rawMarkers.textView.undoManager?.removeAllActions()
        rawMarkers.textView.setSelectedRange(NSRange(location: 3, length: 0))
        rawMarkers.textView.insertText(
            "X**Y**\nZ",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(rawMarkers.textView.string, "**ab**")
        XCTAssertFalse(rawMarkers.textView.undoManager?.canUndo ?? true)
    }

    func testCanonicalInlineReplacementPreservesEscapedLiteralDelimiters() throws {
        let cases: [(source: String, expected: String)] = [
            ("**a\\**b**", "**a**\n**\\**b**"),
            ("==a\\==b==", "==a==\n==\\==b==")
        ]

        for item in cases {
            let harness = makeHarness(text: item.source, textWidth: 360)
            harness.textView.undoManager?.removeAllActions()
            harness.textView.setSelectedRange(NSRange(location: 3, length: 0))
            harness.textView.insertNewline(nil)
            XCTAssertEqual(harness.textView.string, item.expected)
            XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 8, length: 0))
            assertEveryInlineDelimiterIsRecognized(harness.textView.string)
            XCTAssertEqual(
                MarkdownInlineFormat.matches(in: harness.textView.string).count,
                2
            )
            harness.textView.undoManager?.undo()
            XCTAssertEqual(harness.textView.string, item.source)
            harness.textView.undoManager?.redo()
            XCTAssertEqual(harness.textView.string, item.expected)
        }

        let replacements: [(source: String, replacement: String, expected: String)] = [
            ("**ab**", "X\\**\nY", "**aX**\\**\n**Yb**"),
            ("==ab==", "X\\==\nY", "==aX==\\==\n==Yb==")
        ]
        for item in replacements {
            let harness = makeHarness(text: item.source, textWidth: 360)
            harness.textView.undoManager?.removeAllActions()
            harness.textView.setSelectedRange(NSRange(location: 3, length: 0))
            harness.textView.insertText(
                item.replacement,
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            XCTAssertEqual(harness.textView.string, item.expected)
            XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 13, length: 0))
            assertEveryInlineDelimiterIsRecognized(harness.textView.string)
            XCTAssertEqual(
                MarkdownInlineFormat.matches(in: harness.textView.string).count,
                2
            )
            harness.textView.undoManager?.undo()
            XCTAssertEqual(harness.textView.string, item.source)
            harness.textView.undoManager?.redo()
            XCTAssertEqual(harness.textView.string, item.expected)
        }
    }

    func testCheckedTodoCanonicalReturnContinuesWithUncheckedMarker() throws {
        let original = "- [x] **a b**"
        let harness = makeHarness(text: original, textWidth: 360)
        harness.textView.undoManager?.removeAllActions()
        harness.textView.setSelectedRange(NSRange(location: 9, length: 0))
        harness.textView.insertNewline(nil)
        XCTAssertEqual(harness.textView.string, "- [x] **a**\n- [ ]  **b**")
        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 18, length: 0))
        XCTAssertEqual(MarkdownChecklist.checkboxMatches(in: harness.textView.string).count, 2)
        XCTAssertEqual(MarkdownInlineFormat.matches(in: harness.textView.string).count, 2)
        harness.textView.undoManager?.undo()
        XCTAssertEqual(harness.textView.string, original)
        harness.textView.undoManager?.redo()
        XCTAssertEqual(harness.textView.string, "- [x] **a**\n- [ ]  **b**")
    }

    func testFormattedTodoReturnUsesCurrentLinesMixedLineEnding() throws {
        let cases: [(source: String, caret: Int, expected: String)] = [
            (
                "header\r\n- [ ] **a b**\nnext",
                17,
                "header\r\n- [ ] **a**\n- [ ]  **b**\nnext"
            ),
            (
                "header\n- [ ] **a b**\r\nnext",
                16,
                "header\n- [ ] **a**\r\n- [ ]  **b**\r\nnext"
            )
        ]

        for item in cases {
            let harness = makeHarness(text: item.source, textWidth: 420)
            harness.textView.undoManager?.removeAllActions()
            harness.textView.setSelectedRange(NSRange(location: item.caret, length: 0))
            harness.textView.insertNewline(nil)
            XCTAssertEqual(harness.textView.string, item.expected)
            XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 26, length: 0))
            XCTAssertEqual(
                MarkdownChecklist.checkboxMatches(in: harness.textView.string).count,
                2
            )
            XCTAssertEqual(
                MarkdownInlineFormat.matches(in: harness.textView.string).count,
                2
            )
            harness.textView.undoManager?.undo()
            XCTAssertEqual(harness.textView.string, item.source)
            harness.textView.undoManager?.redo()
            XCTAssertEqual(harness.textView.string, item.expected)
        }
    }

    func testCanonicalInlineReplacementFuzzesNestedCaretInsertions() throws {
        let sources = [
            "**abc**",
            "==abc==",
            "**==abc==**",
            "==**abc**==",
            "**pre ==ab== post**",
            "==pre **ab** post==",
            "**a b**"
        ]
        let replacements = [" ", "\n", "\r\n", " X\nY ", "\n\n"]
        var exercised = 0

        for source in sources {
            let nsSource = source as NSString
            let sourceMatches = MarkdownInlineFormat.matches(in: source)
            let sourceDelimiters = sourceMatches.flatMap {
                [$0.openingDelimiterRange, $0.closingDelimiterRange]
            }
            for caret in 0...nsSource.length {
                let isStrictlyInsideDelimiter = sourceDelimiters.contains {
                    caret > $0.location && caret < NSMaxRange($0)
                }
                let isInsideSomeContent = sourceMatches.contains {
                    caret >= $0.contentRange.location
                        && caret <= NSMaxRange($0.contentRange)
                }
                guard !isStrictlyInsideDelimiter, isInsideSomeContent else { continue }
                let originalVisiblePrefixLength = visibleMarkdownLength(
                    source,
                    throughUTF16Offset: caret
                )
                for replacement in replacements {
                    let harness = makeHarness(text: source, textWidth: 500)
                    harness.textView.setSelectedRange(NSRange(location: caret, length: 0))
                    harness.textView.insertText(
                        replacement,
                        replacementRange: NSRange(location: NSNotFound, length: 0)
                    )
                    let output = harness.textView.string
                    let selection = harness.textView.selectedRange()
                    XCTAssertEqual(selection.length, 0)
                    XCTAssertEqual(
                        visibleMarkdownLength(
                            output,
                            throughUTF16Offset: selection.location
                        ),
                        originalVisiblePrefixLength + (replacement as NSString).length,
                        "visible caret drift for \(source), raw caret \(caret), replacement \(replacement.debugDescription), output \(output)"
                    )
                    assertEveryInlineDelimiterIsRecognized(output)
                    XCTAssertFalse(output.contains("****"))
                    XCTAssertFalse(output.contains("===="))
                    exercised += 1
                }
            }
        }
        XCTAssertGreaterThan(exercised, 150)
    }

    func testCanonicalInlineReplacementPreservesAdjacentSiblingTokens() throws {
        let source = "==**a****b**=="
        for caret in [5, 9] {
            let harness = makeHarness(text: source, textWidth: 360)
            harness.textView.undoManager?.removeAllActions()
            harness.textView.setSelectedRange(NSRange(location: caret, length: 0))
            harness.textView.insertText(
                "\n",
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            XCTAssertEqual(harness.textView.string, "==**a**==\n==**b**==")
            XCTAssertEqual(
                MarkdownInlineFormat.matches(in: harness.textView.string)
                    .filter { $0.format == .bold }.count,
                2
            )
            assertEveryInlineDelimiterIsRecognized(harness.textView.string)
            harness.textView.undoManager?.undo()
            XCTAssertEqual(harness.textView.string, source)
            harness.textView.undoManager?.redo()
            XCTAssertEqual(harness.textView.string, "==**a**==\n==**b**==")
        }

        let splitFirst = makeHarness(text: source, textWidth: 360)
        splitFirst.textView.setSelectedRange(NSRange(location: 5, length: 0))
        splitFirst.textView.insertText(
            "X\nY",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(
            splitFirst.textView.string,
            "==**aX**==\n==**Y****b**=="
        )
        XCTAssertEqual(
            MarkdownInlineFormat.matches(in: splitFirst.textView.string)
                .filter { $0.format == .bold }.count,
            3
        )
        assertEveryInlineDelimiterIsRecognized(splitFirst.textView.string)

        let unrelatedSource = "==**a****b** c=="
        let unrelated = makeHarness(text: unrelatedSource, textWidth: 360)
        unrelated.textView.setSelectedRange(NSRange(location: 13, length: 0))
        unrelated.textView.insertNewline(nil)
        XCTAssertEqual(unrelated.textView.string, "==**a****b**== \n==c==")
        let boldMatches = MarkdownInlineFormat.matches(in: unrelated.textView.string)
            .filter { $0.format == .bold }
        XCTAssertEqual(boldMatches.count, 2)
        let firstContent = try XCTUnwrap(boldMatches.first?.contentRange)
        XCTAssertEqual(
            MarkdownInlineFormat.bold.selectionState(
                in: unrelated.textView.string,
                selection: firstContent
            ),
            .active
        )
        XCTAssertNotNil(
            MarkdownInlineFormat.bold.togglePlan(
                in: unrelated.textView.string,
                selection: firstContent
            )
        )
        assertEveryInlineDelimiterIsRecognized(unrelated.textView.string)
    }

    func testNestedMultilineInsertionSplitsOnlyValidActiveLayers() throws {
        let original = "**pre==ab==post**"
        let leading = makeHarness(text: original, textWidth: 360)
        leading.textView.undoManager?.removeAllActions()
        leading.textView.setSelectedRange(NSRange(location: 7, length: 0))
        leading.textView.insertText(
            "\nY",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(
            leading.textView.string,
            "**pre**\n**==Yab==post**"
        )
        XCTAssertEqual(MarkdownInlineFormat.matches(in: leading.textView.string).count, 3)
        leading.textView.undoManager?.undo()
        XCTAssertEqual(leading.textView.string, original)
        leading.textView.undoManager?.redo()
        XCTAssertEqual(leading.textView.string, "**pre**\n**==Yab==post**")

        let trailing = makeHarness(text: original, textWidth: 360)
        trailing.textView.undoManager?.removeAllActions()
        trailing.textView.setSelectedRange(NSRange(location: 9, length: 0))
        trailing.textView.insertText(
            "X\r\n",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(
            trailing.textView.string,
            "**pre==abX==**\r\n**post**"
        )
        XCTAssertEqual(MarkdownInlineFormat.matches(in: trailing.textView.string).count, 3)
        trailing.textView.undoManager?.undo()
        XCTAssertEqual(trailing.textView.string, original)
        trailing.textView.undoManager?.redo()
        XCTAssertEqual(trailing.textView.string, "**pre==abX==**\r\n**post**")
    }

    func testInvalidatingBoldSyntaxClearsInheritedStorageFont() throws {
        let text = "**abc**"
        let harness = makeHarness(text: text, textWidth: 320)
        harness.textView.setSelectedRange(NSRange(location: 0, length: 2))
        harness.textView.insertText("", replacementRange: harness.textView.selectedRange())
        harness.textView.refreshChecklistPresentation(forceLayout: true)

        XCTAssertEqual(harness.textView.string, "abc**")
        XCTAssertTrue(MarkdownInlineFormat.matches(in: harness.textView.string).isEmpty)
        let storage = try XCTUnwrap(harness.textView.textStorage)
        for location in 0..<storage.length {
            let font = try XCTUnwrap(
                storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            )
            XCTAssertFalse(
                NSFontManager.shared.traits(of: font).contains(.boldFontMask),
                "unexpected inherited bold at UTF-16 offset \(location)"
            )
        }
    }

    func testInvalidatingOneOfMultipleBoldTokensClearsOnlyStaleBold() throws {
        let text = "**abc** 后 **xyz**"
        let harness = makeHarness(text: text, textWidth: 320)
        harness.textView.setSelectedRange(NSRange(location: 0, length: 2))
        harness.textView.insertText("", replacementRange: harness.textView.selectedRange())
        harness.textView.refreshChecklistPresentation(forceLayout: true)

        XCTAssertEqual(harness.textView.string, "abc** 后 **xyz**")
        let matches = MarkdownInlineFormat.matches(in: harness.textView.string)
        XCTAssertEqual(matches.count, 1)
        let remaining = try XCTUnwrap(matches.first)
        let storage = try XCTUnwrap(harness.textView.textStorage)
        for location in 0..<storage.length {
            let font = try XCTUnwrap(
                storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            )
            let isBold = NSFontManager.shared.traits(of: font).contains(.boldFontMask)
            XCTAssertEqual(
                isBold,
                NSLocationInRange(location, remaining.contentRange),
                "unexpected font weight at UTF-16 offset \(location)"
            )
        }
    }

    func testWordDeletionAcrossHiddenFormatsIsAtomicWithAndWithoutSpaces() throws {
        for text in ["前 **粗体** 后", "A **BC** Z", "A**==中==**Z"] {
            let match = try XCTUnwrap(
                MarkdownInlineFormat.matches(in: text).first(where: {
                    $0.format == .bold
                })
            )

            let backward = makeHarness(text: text, textWidth: 360)
            backward.textView.undoManager?.removeAllActions()
            backward.textView.setSelectedRange(
                NSRange(location: NSMaxRange(match.tokenRange), length: 0)
            )
            backward.textView.deleteWordBackward(nil)
            XCTAssertFalse(backward.textView.string.contains(match.format.delimiter))
            XCTAssertTrue(MarkdownInlineFormat.matches(in: backward.textView.string).isEmpty)
            backward.textView.undoManager?.undo()
            XCTAssertEqual(backward.textView.string, text)

            let forward = makeHarness(text: text, textWidth: 360)
            forward.textView.setSelectedRange(
                NSRange(location: match.tokenRange.location, length: 0)
            )
            forward.textView.deleteWordForward(nil)
            XCTAssertFalse(forward.textView.string.contains(match.format.delimiter))
            XCTAssertTrue(MarkdownInlineFormat.matches(in: forward.textView.string).isEmpty)
        }

        let spaced = "A **BC** Z"
        let spacedMatch = try XCTUnwrap(MarkdownInlineFormat.matches(in: spaced).first)
        let afterSpace = makeHarness(text: spaced, textWidth: 320)
        afterSpace.textView.setSelectedRange(
            NSRange(location: NSMaxRange(spacedMatch.tokenRange) + 1, length: 0)
        )
        afterSpace.textView.deleteWordBackward(nil)
        XCTAssertFalse(afterSpace.textView.string.contains("**"))

        let beforeSpace = makeHarness(text: spaced, textWidth: 320)
        beforeSpace.textView.setSelectedRange(
            NSRange(location: spacedMatch.tokenRange.location - 1, length: 0)
        )
        beforeSpace.textView.deleteWordForward(nil)
        XCTAssertFalse(beforeSpace.textView.string.contains("**"))
    }

    func testLineDeletionNeverOverDeletesAcrossHiddenDelimiter() {
        let text = "A**BC**Z"
        let backward = makeHarness(text: text, textWidth: 320)
        backward.textView.setSelectedRange(NSRange(location: 4, length: 0))
        backward.textView.deleteToBeginningOfLine(nil)
        XCTAssertEqual(backward.textView.string, text)

        let forward = makeHarness(text: text, textWidth: 320)
        forward.textView.setSelectedRange(NSRange(location: 4, length: 0))
        forward.textView.deleteToEndOfLine(nil)
        XCTAssertEqual(forward.textView.string, text)
    }

    func testInlineFormatIndexStaysCurrentAcrossIMECancelAndCommit() throws {
        let original = "前**粗体**后"
        let harness = makeHarness(text: original, textWidth: 360)
        let textView = harness.textView
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.setMarkedText(
            "pin",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: 0, length: 0)
        )
        textView.setMarkedText(
            "pinyin",
            selectedRange: NSRange(location: 6, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertTrue(textView.hasMarkedText())
        runMainLoop()
        layoutManager.ensureLayout(for: textContainer)
        let shiftedMatch = try XCTUnwrap(
            MarkdownInlineFormat.matches(in: textView.string).first
        )
        let shiftedOpening = shiftedMatch.openingDelimiterRange
        for offset in shiftedOpening.location..<NSMaxRange(shiftedOpening) {
            let glyph = layoutManager.glyphIndexForCharacter(at: offset)
            XCTAssertTrue(layoutManager.propertyForGlyph(at: glyph).contains(.null))
        }

        textView.setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(textView.string, original)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.setMarkedText(
            "pin",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: 0, length: 0)
        )
        textView.insertText(
            "拼",
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertFalse(textView.hasMarkedText())
        XCTAssertEqual(textView.string, "拼" + original)
        textView.refreshChecklistPresentation(forceLayout: true)
        let committedMatch = try XCTUnwrap(
            MarkdownInlineFormat.matches(in: textView.string).first
        )
        let committedFont = try XCTUnwrap(
            textView.textStorage?.attribute(
                .font,
                at: committedMatch.contentRange.location,
                effectiveRange: nil
            ) as? NSFont
        )
        XCTAssertTrue(
            NSFontManager.shared.traits(of: committedFont).contains(.boldFontMask)
        )

        let delimiterIME = makeHarness(text: "**粗体**", textWidth: 280)
        delimiterIME.textView.setSelectedRange(NSRange(location: 1, length: 0))
        delimiterIME.textView.setMarkedText(
            "x",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 1, length: 0)
        )
        XCTAssertTrue(delimiterIME.textView.hasMarkedText())
        XCTAssertEqual(delimiterIME.textView.markedRange().location, 1)
        XCTAssertTrue(
            MarkdownInlineFormat.matches(in: delimiterIME.textView.string).isEmpty
        )
        delimiterIME.textView.setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(delimiterIME.textView.string, "**粗体**")
    }

    func testStaleSelectionToolbarFormatButtonCannotEditNewSelection() throws {
        let text = "先选择这里，再选择那里"
        let harness = makeHarness(text: text, textWidth: 360)
        harness.textView.selectionMovePresentationDelay = 0
        harness.textView.setSelectedRange((text as NSString).range(of: "这里"))
        runMainLoop()
        let staleBoldButton = try XCTUnwrap(
            harness.textView.visibleSelectionToolbarBoldButton
        )

        harness.textView.setSelectedRange((text as NSString).range(of: "那里"))
        staleBoldButton.performClick(nil)

        XCTAssertEqual(harness.textView.string, text)
        XCTAssertNil(harness.textView.visibleSelectionToolbar)
    }

    func testPendingCaretIsConsumedAfterExternalTextUpdateAndClamped() {
        let harness = makeHarness(text: "旧正文", textWidth: 180, viewportHeight: 80)
        let updatedText = (0..<30).map { "第\($0)行😀" }.joined(separator: "\n")
        let updatedLength = (updatedText as NSString).length
        harness.controller.setPendingCaretAfterExternalTextUpdate(
            atUTF16Offset: updatedLength + 99,
            scrollToVisible: true
        )
        harness.textView.string = updatedText

        XCTAssertTrue(
            harness.controller.consumePendingSelectionAfterExternalTextUpdate(
                in: harness.textView
            )
        )
        XCTAssertEqual(
            harness.textView.selectedRange(),
            NSRange(location: updatedLength, length: 0)
        )
        XCTAssertFalse(
            harness.controller.consumePendingSelectionAfterExternalTextUpdate(
                in: harness.textView
            )
        )
    }

    func testDeleteBackwardInsideTodoContentUsesNormalCharacterDeletion() throws {
        let original = "- [ ] 正文"
        let harness = makeHarness(text: original, textWidth: 420)
        let textView = harness.textView
        textView.setSelectedRange(
            NSRange(location: (original as NSString).length, length: 0)
        )

        textView.deleteBackward(nil)

        XCTAssertEqual(textView.string, "- [ ] 正")
        XCTAssertEqual(MarkdownChecklist.progress(in: textView.string).total, 1)
    }

    private func glyphX(
        _ glyphIndex: Int,
        layoutManager: NSLayoutManager
    ) -> CGFloat {
        let lineRect = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        return lineRect.minX + layoutManager.location(forGlyphAt: glyphIndex).x
    }

    private func runMainLoop(for duration: TimeInterval = 0.03) {
        RunLoop.current.run(until: Date().addingTimeInterval(duration))
    }

    private func makeDocument(
        scope: NoteScope,
        stableKey: String? = nil
    ) -> NoteDocument {
        let stableKey = stableKey ?? "test-\(scope.rawValue)"
        return NoteDocument(
            scope: scope,
            stableKey: stableKey,
            displayName: "测试笔记",
            context: nil,
            fileURL: URL(
                fileURLWithPath: "/tmp/codex-notes-selection-test-\(stableKey).md"
            )
        )
    }

    private func rightMouseEvent(in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: NSPoint(x: 20, y: 20),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private func clickTextView(
        at point: NSPoint,
        in harness: EditorHarness
    ) throws {
        let windowPoint = harness.textView.convert(point, to: nil)
        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: harness.window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let mouseUp = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0.01,
            windowNumber: harness.window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 0
        ))
        NSApplication.shared.postEvent(mouseUp, atStart: false)
        harness.textView.mouseDown(with: mouseDown)
        _ = NSApplication.shared.nextEvent(
            matching: .leftMouseUp,
            until: Date(),
            inMode: .default,
            dequeue: true
        )
    }

    private func assertChecklistLayout(
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        isChecked: Bool
    ) throws -> CGFloat {
        let marker = isChecked ? "x" : " "
        let todo = "- [\(marker)] 这是一条足够长的待办内容，用来验证多种字号和行距的换行对齐。"
        let ordinary = "这是一条足够长的普通段落，它的换行不应带有待办缩进。"
        let text = todo + "\n" + ordinary
        let context = "font=\(fontSize), spacing=\(lineSpacing), checked=\(isChecked)"
        let harness = makeHarness(
            text: text,
            textWidth: 190,
            fontSize: fontSize,
            lineSpacing: lineSpacing
        )
        let textView = harness.textView
        let layoutManager = try XCTUnwrap(textView.layoutManager, context)
        let textContainer = try XCTUnwrap(textView.textContainer, context)
        let match = try XCTUnwrap(
            MarkdownChecklist.checkboxMatches(in: text).first,
            context
        )
        XCTAssertEqual(match.isChecked, isChecked, context)

        layoutManager.ensureLayout(for: textContainer)
        let firstContentGlyph = layoutManager.glyphIndexForCharacter(
            at: match.contentRange.location
        )
        var firstTodoLineRange = NSRange()
        let firstTodoLineRect = layoutManager.lineFragmentRect(
            forGlyphAt: firstContentGlyph,
            effectiveRange: &firstTodoLineRange
        )
        let continuationGlyph = NSMaxRange(firstTodoLineRange)
        XCTAssertLessThan(continuationGlyph, layoutManager.numberOfGlyphs, context)
        let continuationLineRect = layoutManager.lineFragmentRect(
            forGlyphAt: continuationGlyph,
            effectiveRange: nil
        )
        XCTAssertEqual(
            glyphX(continuationGlyph, layoutManager: layoutManager),
            glyphX(firstContentGlyph, layoutManager: layoutManager),
            accuracy: 0.5,
            context
        )
        XCTAssertEqual(
            continuationLineRect.minY - firstTodoLineRect.minY,
            firstTodoLineRect.height,
            accuracy: 0.5,
            context
        )

        let checklistStyle = try XCTUnwrap(
            textView.textStorage?.attribute(
                .paragraphStyle,
                at: match.lineRange.location,
                effectiveRange: nil
            ) as? NSParagraphStyle,
            context
        )
        XCTAssertEqual(checklistStyle.firstLineHeadIndent, 0, accuracy: 0.001, context)
        XCTAssertEqual(checklistStyle.lineSpacing, 0, accuracy: 0.001, context)

        let completionAttribute = layoutManager.temporaryAttribute(
            .strikethroughStyle,
            atCharacterIndex: match.contentRange.location,
            effectiveRange: nil
        )
        XCTAssertEqual(completionAttribute != nil, isChecked, context)

        let ordinaryStart = (todo as NSString).length + 1
        let ordinaryFirstGlyph = layoutManager.glyphIndexForCharacter(at: ordinaryStart)
        var ordinaryFirstLineRange = NSRange()
        _ = layoutManager.lineFragmentRect(
            forGlyphAt: ordinaryFirstGlyph,
            effectiveRange: &ordinaryFirstLineRange
        )
        let ordinaryContinuationGlyph = NSMaxRange(ordinaryFirstLineRange)
        XCTAssertLessThan(ordinaryContinuationGlyph, layoutManager.numberOfGlyphs, context)
        XCTAssertEqual(
            glyphX(ordinaryContinuationGlyph, layoutManager: layoutManager),
            glyphX(ordinaryFirstGlyph, layoutManager: layoutManager),
            accuracy: 0.5,
            context
        )
        let ordinaryStyle = try XCTUnwrap(
            textView.textStorage?.attribute(
                .paragraphStyle,
                at: ordinaryStart,
                effectiveRange: nil
            ) as? NSParagraphStyle,
            context
        )
        XCTAssertEqual(ordinaryStyle.firstLineHeadIndent, 0, accuracy: 0.001, context)
        XCTAssertEqual(ordinaryStyle.headIndent, 0, accuracy: 0.001, context)
        XCTAssertEqual(ordinaryStyle.lineSpacing, 0, accuracy: 0.001, context)

        var glyphIndex = 0
        while glyphIndex < layoutManager.numberOfGlyphs {
            var lineGlyphRange = NSRange()
            let fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange
            )
            let usedRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            )
            XCTAssertGreaterThanOrEqual(fragmentRect.minX, -0.5, context)
            XCTAssertLessThanOrEqual(
                fragmentRect.maxX,
                textContainer.containerSize.width + 0.5,
                context
            )
            XCTAssertGreaterThanOrEqual(usedRect.minX, fragmentRect.minX - 0.5, context)
            XCTAssertLessThanOrEqual(usedRect.maxX, fragmentRect.maxX + 0.5, context)
            let nextGlyphIndex = NSMaxRange(lineGlyphRange)
            XCTAssertGreaterThan(nextGlyphIndex, glyphIndex, context)
            glyphIndex = nextGlyphIndex
        }
        XCTAssertEqual(textView.string, text, context)
        return firstTodoLineRect.height
    }

    private func makeTemporaryImageRoot() -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-notes-editor-images-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
        return rootURL
    }

    private func makeImageDocument(
        rootURL: URL,
        stableKey: String
    ) -> NoteDocument {
        NoteDocument(
            scope: .task,
            stableKey: stableKey,
            displayName: "图片测试",
            context: nil,
            fileURL: rootURL
                .appendingPathComponent("Tasks", isDirectory: true)
                .appendingPathComponent("\(stableKey).md")
        )
    }

    private struct EditorAdornmentPixelGeometry {
        let surface: NSRect
        let ink: NSRect
    }

    private func renderedSelectionGeometry(
        text: String,
        selection: NSRange,
        appearance: NSAppearance.Name,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        windowIsKey: Bool = true
    ) throws -> EditorAdornmentPixelGeometry {
        let harness = makeHarness(
            text: text,
            textWidth: 280,
            fontSize: fontSize,
            lineSpacing: lineSpacing
        )
        let usesDarkInk = appearance == .aqua
        configureAdornmentPixelHarness(
            harness,
            appearance: appearance,
            usesDarkInk: usesDarkInk
        )
        harness.window.reportsKeyWindow = windowIsKey
        harness.textView.insertionPointColor = .clear
        harness.textView.selectedTextAttributes = [
            .backgroundColor: selectionGeometryProbeColor,
            .foregroundColor: usesDarkInk ? NSColor.black : NSColor.white
        ]
        harness.textView.setSelectedRange(selection)
        prepareForPixelRendering(harness)

        let pixels = renderedPixels(of: harness.textView)
        let width = max(1, Int(harness.textView.bounds.width.rounded(.up)))
        let height = max(1, Int(harness.textView.bounds.height.rounded(.up)))
        let surface: NSRect
        if windowIsKey {
            surface = try XCTUnwrap(
                pixelBounds(
                    pixels,
                    width: width,
                    height: height,
                    matches: isSelectionGeometryProbePixel
                )
            )
        } else {
            harness.textView.setSelectedRange(
                NSRange(location: selection.location, length: 0)
            )
            harness.textView.needsDisplay = true
            let unselectedPixels = renderedPixels(of: harness.textView)
            surface = try XCTUnwrap(
                differingPixelBounds(
                    pixels,
                    unselectedPixels,
                    width: width,
                    height: height
                )
            )
            harness.textView.setSelectedRange(selection)
        }
        let ink = try XCTUnwrap(
            pixelBounds(
                pixels,
                width: width,
                height: height,
                restrictedTo: surface,
                matches: usesDarkInk ? isDarkInkPixel : isLightInkPixel
            )
        )
        XCTAssertEqual(harness.textView.string, text)
        XCTAssertEqual(harness.textView.selectedRange(), selection)
        return EditorAdornmentPixelGeometry(surface: surface, ink: ink)
    }

    private func renderedInsertionPointGeometry(
        text: String,
        caretLocation: Int,
        appearance: NSAppearance.Name,
        fontSize: CGFloat,
        lineSpacing: CGFloat
    ) throws -> EditorAdornmentPixelGeometry {
        let harness = makeHarness(
            text: text,
            textWidth: 280,
            fontSize: fontSize,
            lineSpacing: lineSpacing
        )
        let usesDarkInk = appearance == .aqua
        configureAdornmentPixelHarness(
            harness,
            appearance: appearance,
            usesDarkInk: usesDarkInk
        )
        harness.textView.insertionPointColor = selectionGeometryProbeColor
        harness.textView.setSelectedRange(
            NSRange(location: caretLocation, length: 0)
        )
        let width = max(1, Int(harness.textView.bounds.width.rounded(.up)))
        let height = max(1, Int(harness.textView.bounds.height.rounded(.up)))
        let nativeRect = try nativeInsertionPointRect(
            in: harness.textView,
            at: caretLocation
        )
        let surface = harness.textView.adjustedInsertionPointRect(nativeRect)

        harness.textView.insertionPointColor = .clear
        prepareForPixelRendering(harness)
        let textPixels = renderedPixels(of: harness.textView)
        let ink = try XCTUnwrap(
            pixelBounds(
                textPixels,
                width: width,
                height: height,
                restrictedTo: NSRect(
                    x: 0,
                    y: surface.minY,
                    width: min(CGFloat(width), 120),
                    height: surface.height
                ),
                matches: usesDarkInk ? isDarkInkPixel : isLightInkPixel
            )
        )
        XCTAssertEqual(harness.textView.string, text)
        XCTAssertEqual(
            harness.textView.selectedRange(),
            NSRange(location: caretLocation, length: 0)
        )
        return EditorAdornmentPixelGeometry(surface: surface, ink: ink)
    }

    private func nativeInsertionPointRect(
        in textView: CheckboxTextView,
        at characterLocation: Int
    ) throws -> NSRect {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let sourceLength = (textView.string as NSString).length

        let containerRect: NSRect
        if characterLocation == sourceLength,
           textView.string.hasSuffix("\n") {
            containerRect = layoutManager.extraLineFragmentRect
        } else {
            let characterIndex = min(
                max(characterLocation, 0),
                max(sourceLength - 1, 0)
            )
            let glyphIndex = layoutManager.glyphIndexForCharacter(
                at: characterIndex
            )
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            )
            let glyphLocation = layoutManager.location(forGlyphAt: glyphIndex)
            containerRect = NSRect(
                x: lineRect.minX + glyphLocation.x,
                y: lineRect.minY,
                width: 1,
                height: lineRect.height
            )
        }
        return containerRect.offsetBy(
            dx: textView.textContainerOrigin.x,
            dy: textView.textContainerOrigin.y
        )
    }

    private var selectionGeometryProbeColor: NSColor {
        NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
    }

    private func configureAdornmentPixelHarness(
        _ harness: EditorHarness,
        appearance: NSAppearance.Name,
        usesDarkInk: Bool
    ) {
        harness.window.appearance = NSAppearance(named: appearance)
        harness.textView.selectionMovePresentationDelay = 60
        harness.textView.textContainerInset = NSSize(width: 12, height: 12)
        harness.textView.drawsBackground = true
        harness.textView.backgroundColor = usesDarkInk ? .white : .black
        harness.textView.textColor = usesDarkInk ? .black : .white
    }

    private func prepareForPixelRendering(_ harness: EditorHarness) {
        if let textContainer = harness.textView.textContainer {
            harness.textView.layoutManager?.ensureLayout(for: textContainer)
        }
        harness.scrollView.needsDisplay = true
        harness.textView.needsDisplay = true
    }

    private func pixelBounds(
        _ pixels: Data,
        width: Int,
        height: Int,
        restrictedTo restriction: NSRect? = nil,
        matches: (UInt8, UInt8, UInt8, UInt8) -> Bool
    ) -> NSRect? {
        let minX = max(0, Int((restriction?.minX ?? 0).rounded(.down)))
        let maxX = min(width, Int((restriction?.maxX ?? CGFloat(width)).rounded(.up)))
        let minY = max(0, Int((restriction?.minY ?? 0).rounded(.down)))
        let maxY = min(height, Int((restriction?.maxY ?? CGFloat(height)).rounded(.up)))
        guard minX < maxX, minY < maxY else { return nil }

        var foundMinX = width
        var foundMaxX = -1
        var foundMinY = height
        var foundMaxY = -1
        pixels.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for y in minY..<maxY {
                for x in minX..<maxX {
                    let offset = (y * width + x) * 4
                    guard offset + 3 < bytes.count else { continue }
                    if matches(
                        bytes[offset],
                        bytes[offset + 1],
                        bytes[offset + 2],
                        bytes[offset + 3]
                    ) {
                        foundMinX = min(foundMinX, x)
                        foundMaxX = max(foundMaxX, x)
                        foundMinY = min(foundMinY, y)
                        foundMaxY = max(foundMaxY, y)
                    }
                }
            }
        }
        guard foundMinX <= foundMaxX, foundMinY <= foundMaxY else { return nil }
        return NSRect(
            x: foundMinX,
            y: foundMinY,
            width: foundMaxX - foundMinX + 1,
            height: foundMaxY - foundMinY + 1
        )
    }

    private func differingPixelBounds(
        _ lhs: Data,
        _ rhs: Data,
        width: Int,
        height: Int
    ) -> NSRect? {
        guard lhs.count == rhs.count else { return nil }
        var foundMinX = width
        var foundMaxX = -1
        var foundMinY = height
        var foundMaxY = -1
        lhs.withUnsafeBytes { lhsRawBuffer in
            rhs.withUnsafeBytes { rhsRawBuffer in
                let lhsBytes = lhsRawBuffer.bindMemory(to: UInt8.self)
                let rhsBytes = rhsRawBuffer.bindMemory(to: UInt8.self)
                for y in 0..<height {
                    for x in 0..<width {
                        let offset = (y * width + x) * 4
                        guard offset + 3 < lhsBytes.count else { continue }
                        let difference = abs(
                            Int(lhsBytes[offset]) - Int(rhsBytes[offset])
                        ) + abs(
                            Int(lhsBytes[offset + 1]) - Int(rhsBytes[offset + 1])
                        ) + abs(
                            Int(lhsBytes[offset + 2]) - Int(rhsBytes[offset + 2])
                        ) + abs(
                            Int(lhsBytes[offset + 3]) - Int(rhsBytes[offset + 3])
                        )
                        if difference > 24 {
                            foundMinX = min(foundMinX, x)
                            foundMaxX = max(foundMaxX, x)
                            foundMinY = min(foundMinY, y)
                            foundMaxY = max(foundMaxY, y)
                        }
                    }
                }
            }
        }
        guard foundMinX <= foundMaxX, foundMinY <= foundMaxY else { return nil }
        return NSRect(
            x: foundMinX,
            y: foundMinY,
            width: foundMaxX - foundMinX + 1,
            height: foundMaxY - foundMinY + 1
        )
    }

    private func isSelectionGeometryProbePixel(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        _ alpha: UInt8
    ) -> Bool {
        red > 220 && green < 80 && blue > 220 && alpha > 220
    }

    private func isDarkInkPixel(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        _ alpha: UInt8
    ) -> Bool {
        max(red, green, blue) < 90 && alpha > 220
    }

    private func isLightInkPixel(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        _ alpha: UInt8
    ) -> Bool {
        min(red, green, blue) > 200 && alpha > 220
    }

    private func renderedPixels(of view: NSView) -> Data {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let width = max(1, Int(view.bounds.width.rounded(.up)))
        let height = max(1, Int(view.bounds.height.rounded(.up)))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return Data(
            bytes: bitmap.bitmapData!,
            count: bitmap.bytesPerRow * bitmap.pixelsHigh
        )
    }

    private func renderedPixels(of view: NSView, in rect: NSRect) -> Data {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let width = max(1, Int(rect.width.rounded(.up)))
        let height = max(1, Int(rect.height.rounded(.up)))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        view.cacheDisplay(in: rect, to: bitmap)
        return Data(
            bytes: bitmap.bitmapData!,
            count: bitmap.bytesPerRow * bitmap.pixelsHigh
        )
    }

    private func cacheDisplayOnly(of view: NSView, in rect: NSRect) {
        let width = max(1, Int(rect.width.rounded(.up)))
        let height = max(1, Int(rect.height.rounded(.up)))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        view.cacheDisplay(in: rect, to: bitmap)
    }

    private func colorComponents(
        of cgColor: CGColor?
    ) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        guard let cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB)
        else { return nil }
        return (
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent,
            alpha: color.alphaComponent
        )
    }

    private func selectedSubstring(in textView: NSTextView) -> String {
        let range = textView.selectedRange()
        guard range.location != NSNotFound, range.length > 0 else { return "" }
        return (textView.string as NSString).substring(with: range)
    }

    private func differingBytes(_ lhs: Data, _ rhs: Data) -> Int {
        zip(lhs, rhs).reduce(into: 0) { count, pair in
            if pair.0 != pair.1 { count += 1 }
        }
    }

    private func highContrastPixelCount(
        _ pixels: Data,
        width: Int,
        height: Int,
        rect: NSRect,
        expectsLightPixels: Bool
    ) -> Int {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }

        return pixels.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var count = 0
            for y in minY..<maxY {
                for x in minX..<maxX {
                    let offset = (y * width + x) * 4
                    guard offset + 3 < bytes.count else { continue }
                    let red = bytes[offset]
                    let green = bytes[offset + 1]
                    let blue = bytes[offset + 2]
                    let alpha = bytes[offset + 3]
                    guard alpha > 128 else { continue }
                    if expectsLightPixels {
                        if min(red, green, blue) > 180 { count += 1 }
                    } else if max(red, green, blue) < 75 {
                        count += 1
                    }
                }
            }
            return count
        }
    }

    private struct HighlightPixelComponent {
        let rect: NSRect
        let pixelCount: Int
    }

    private func renderedHighlightComponents(
        text: String,
        textWidth: CGFloat,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        appearance: NSAppearance.Name,
        backgroundColor: NSColor,
        foregroundColor: NSColor,
        minimumComponentWidth: CGFloat = 10
    ) -> [HighlightPixelComponent] {
        let harness = makeHarness(
            text: text,
            textWidth: textWidth,
            viewportHeight: 180,
            fontSize: fontSize,
            lineSpacing: lineSpacing
        )
        harness.window.appearance = NSAppearance(named: appearance)
        harness.scrollView.backgroundColor = backgroundColor
        harness.textView.backgroundColor = backgroundColor
        harness.textView.textColor = foregroundColor
        harness.textView.insertionPointColor = .clear
        harness.textView.refreshChecklistPresentation(forceLayout: true)
        if let textContainer = harness.textView.textContainer {
            harness.textView.layoutManager?.ensureLayout(for: textContainer)
        }
        harness.scrollView.needsDisplay = true
        harness.textView.needsDisplay = true

        let pixels = renderedPixels(of: harness.scrollView)
        let width = max(1, Int(harness.scrollView.bounds.width.rounded(.up)))
        let height = max(1, Int(harness.scrollView.bounds.height.rounded(.up)))
        return mergeHighlightRowComponents(
            yellowPixelComponents(pixels, width: width, height: height)
        )
            .filter {
                $0.pixelCount > 20 && $0.rect.width > minimumComponentWidth
            }
            .sorted { lhs, rhs in
                if lhs.rect.minY == rhs.rect.minY {
                    return lhs.rect.minX < rhs.rect.minX
                }
                return lhs.rect.minY < rhs.rect.minY
            }
    }

    private func mergeHighlightRowComponents(
        _ components: [HighlightPixelComponent]
    ) -> [HighlightPixelComponent] {
        let sorted = components.sorted {
            if $0.rect.midY == $1.rect.midY {
                return $0.rect.minX < $1.rect.minX
            }
            return $0.rect.midY < $1.rect.midY
        }
        var rows: [HighlightPixelComponent] = []
        for component in sorted where component.pixelCount > 3 {
            if let last = rows.last {
                let overlap = max(
                    0,
                    min(last.rect.maxY, component.rect.maxY)
                        - max(last.rect.minY, component.rect.minY)
                )
                let requiredOverlap = min(
                    last.rect.height,
                    component.rect.height
                ) * 0.45
                if overlap >= requiredOverlap {
                    rows[rows.count - 1] = HighlightPixelComponent(
                        rect: last.rect.union(component.rect),
                        pixelCount: last.pixelCount + component.pixelCount
                    )
                    continue
                }
            }
            rows.append(component)
        }
        return rows
    }

    private func yellowPixelComponents(
        _ pixels: Data,
        width: Int,
        height: Int
    ) -> [HighlightPixelComponent] {
        guard width > 0, height > 0 else { return [] }
        let pixelCount = width * height
        var mask = [Bool](repeating: false, count: pixelCount)
        pixels.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for index in 0..<pixelCount {
                let offset = index * 4
                guard offset + 3 < bytes.count else { break }
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                let alpha = Int(bytes[offset + 3])
                mask[index] = alpha > 80
                    && red > 60
                    && green > 50
                    && red - blue > 24
                    && green - blue > 18
            }
        }

        var visited = [Bool](repeating: false, count: pixelCount)
        var components: [HighlightPixelComponent] = []
        for start in 0..<pixelCount where mask[start] && !visited[start] {
            var stack = [start]
            visited[start] = true
            var minX = width
            var maxX = 0
            var minY = height
            var maxY = 0
            var count = 0
            while let current = stack.popLast() {
                let x = current % width
                let y = current / width
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
                count += 1
                if x > 0 {
                    let next = current - 1
                    if mask[next] && !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
                if x + 1 < width {
                    let next = current + 1
                    if mask[next] && !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
                if y > 0 {
                    let next = current - width
                    if mask[next] && !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
                if y + 1 < height {
                    let next = current + width
                    if mask[next] && !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }
            components.append(
                HighlightPixelComponent(
                    rect: NSRect(
                        x: minX,
                        y: minY,
                        width: maxX - minX + 1,
                        height: maxY - minY + 1
                    ),
                    pixelCount: count
                )
            )
        }
        return components
    }

    private func blueDominantPixelCount(
        _ pixels: Data,
        width: Int,
        height: Int
    ) -> Int {
        let expectedByteCount = width * height * 4
        guard pixels.count >= expectedByteCount else { return 0 }
        return pixels.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var count = 0
            for offset in stride(from: 0, to: expectedByteCount, by: 4) {
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                let alpha = Int(bytes[offset + 3])
                if alpha > 128,
                   blue > 180,
                   blue - red > 80,
                   blue - green > 40 {
                    count += 1
                }
            }
            return count
        }
    }

    private func makePNGData(width: Int, height: Int) -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        let bytes = bitmap.bitmapData!
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            bytes[offset] = 42
            bytes[offset + 1] = 132
            bytes[offset + 2] = 218
            bytes[offset + 3] = 255
        }
        return bitmap.representation(using: .png, properties: [:])!
    }

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("codex-notes-test-\(UUID().uuidString)"))
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func visibleMarkdownLength(
        _ markdown: String,
        throughUTF16Offset offset: Int
    ) -> Int {
        let hiddenBeforeOffset = MarkdownInlineFormat.matches(in: markdown)
            .flatMap { [$0.openingDelimiterRange, $0.closingDelimiterRange] }
            .reduce(0) { result, range in
                result + max(0, min(offset, NSMaxRange(range)) - range.location)
            }
        return offset - hiddenBeforeOffset
    }

    private func assertEveryInlineDelimiterIsRecognized(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let recognized = MarkdownInlineFormat.matches(in: markdown).flatMap {
            [$0.openingDelimiterRange, $0.closingDelimiterRange]
        }
        let source = markdown as NSString
        for delimiter in ["**", "=="] {
            var search = NSRange(location: 0, length: source.length)
            while search.length > 0 {
                let found = source.range(of: delimiter, options: [], range: search)
                guard found.location != NSNotFound else { break }
                var precedingBackslashes = 0
                var cursor = found.location
                while cursor > 0, source.character(at: cursor - 1) == 0x5C {
                    precedingBackslashes += 1
                    cursor -= 1
                }
                if precedingBackslashes.isMultiple(of: 2) {
                    XCTAssertTrue(
                        recognized.contains(found),
                        "orphan delimiter \(delimiter) in \(markdown)",
                        file: file,
                        line: line
                    )
                }
                let next = NSMaxRange(found)
                search = NSRange(location: next, length: source.length - next)
            }
        }
    }

    private func makeHarness(
        text: String,
        textWidth: CGFloat,
        viewportHeight: CGFloat = 180,
        fontSize: CGFloat = 15,
        lineSpacing: CGFloat = 7,
        refresh: Bool = true,
        isEditable: Bool = true,
        selectionMoveConfiguration: EditorSelectionMoveConfiguration? = nil,
        documentIdentity: MarkdownEditorDocumentIdentity? = nil,
        imageConfiguration: EditorImageConfiguration? = nil,
        textBinding: Binding<String>? = nil
    ) -> EditorHarness {
        _ = NSApplication.shared
        let controller = MarkdownEditorController()
        let parent = PlainMarkdownTextView(
            controller: controller,
            text: textBinding ?? .constant(text),
            documentIdentity: documentIdentity,
            isEditable: isEditable,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            appearanceID: "test",
            backgroundColor: .textBackgroundColor,
            textColor: .textColor,
            disabledTextColor: .secondaryLabelColor,
            insertionPointColor: .controlAccentColor,
            selectionBackgroundColor: .selectedTextBackgroundColor,
            selectionTextColor: .selectedTextColor,
            selectionToolbarBackgroundColor: .controlBackgroundColor,
            selectionToolbarForegroundColor: .labelColor,
            selectionToolbarAccentColor: .controlAccentColor,
            selectionToolbarHoverColor: .selectedTextBackgroundColor,
            selectionToolbarSelectionColor: .selectedTextBackgroundColor,
            selectionToolbarBorderColor: .separatorColor,
            successColor: .systemGreen,
            checkboxCheckmarkColor: .textBackgroundColor,
            checkboxHoverBackgroundColor: .controlBackgroundColor,
            selectionMoveConfiguration: selectionMoveConfiguration,
            imageConfiguration: imageConfiguration
        )
        let coordinator = parent.makeCoordinator()
        coordinator.appliedDocumentIdentity = documentIdentity
        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: textWidth, height: viewportHeight)
        )
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        let textView = CheckboxTextView(
            frame: NSRect(x: 0, y: 0, width: textWidth, height: 1_200)
        )
        textView.editorController = controller
        textView.selectionMoveConfiguration = selectionMoveConfiguration
        textView.imageConfiguration = imageConfiguration
        textView.installChecklistTextStorageDelegate()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.drawsBackground = false
        textView.backgroundColor = .textBackgroundColor
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.string = text
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: textWidth,
            height: .greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.layoutManager?.delegate = coordinator
        textView.delegate = coordinator
        coordinator.textView = textView
        textView.updateChecklistStyle(
            fontSize: fontSize,
            completedTextColor: .secondaryLabelColor,
            successColor: .systemGreen,
            checkmarkColor: .textBackgroundColor,
            accentColor: .controlAccentColor,
            hoverBackgroundColor: .controlBackgroundColor
        )
        scrollView.documentView = textView
        coordinator.observeScrollBounds(in: scrollView)
        if refresh {
            textView.refreshChecklistPresentation(forceLayout: true)
        }
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }
        let window = EditorHarnessWindow(
            contentRect: NSRect(x: 0, y: 0, width: textWidth, height: viewportHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        controller.attach(to: textView)
        return EditorHarness(
            window: window,
            scrollView: scrollView,
            textView: textView,
            coordinator: coordinator,
            controller: controller
        )
    }
}

@MainActor
private struct EditorHarness {
    let window: EditorHarnessWindow
    let scrollView: NSScrollView
    let textView: CheckboxTextView
    let coordinator: PlainMarkdownTextView.Coordinator
    let controller: MarkdownEditorController
}

private final class EditorHarnessWindow: NSWindow {
    var reportsKeyWindow = true

    override var isKeyWindow: Bool {
        reportsKeyWindow
    }
}

private final class UndoProbe: NSObject {
    var didUndo = false
}

private final class WeakObjectBox<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object) {
        self.value = value
    }
}

@MainActor
private final class ImageErrorProbe {
    var messages: [String] = []
}

@MainActor
private final class TextBindingProbe {
    private(set) var value: String
    private(set) var recordedWrites: [String] = []

    init(_ value: String) {
        self.value = value
    }

    func record(_ value: String) {
        self.value = value
        recordedWrites.append(value)
    }

    func reset(to value: String) {
        self.value = value
        recordedWrites.removeAll()
    }
}
