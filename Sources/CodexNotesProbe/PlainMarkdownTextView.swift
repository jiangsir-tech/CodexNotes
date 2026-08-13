import AppKit
import CodexNotesCore
import ImageIO
import SwiftUI

struct EditorSelectionSnapshot: Equatable {
    let document: NoteDocument
    let destinationDocument: NoteDocument
    let selectionStableKey: String
    let sourceText: String
    let range: NSRange
    let selectedText: String
}

struct EditorSelectionMoveConfiguration {
    let sourceDocument: NoteDocument
    let destinationDocument: NoteDocument
    let selectionStableKey: String
    let title: String
    let isEnabled: Bool
    let disabledReason: String?
    let action: (EditorSelectionSnapshot) -> Void

    init(
        sourceDocument: NoteDocument,
        destinationDocument: NoteDocument,
        selectionStableKey: String,
        title: String,
        isEnabled: Bool,
        disabledReason: String? = nil,
        action: @escaping (EditorSelectionSnapshot) -> Void
    ) {
        self.sourceDocument = sourceDocument
        self.destinationDocument = destinationDocument
        self.selectionStableKey = selectionStableKey
        self.title = title
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
        self.action = action
    }
}

struct MarkdownEditorDocumentIdentity: Equatable, Sendable {
    let scope: NoteScope
    let stableKey: String
    let fileURL: URL

    init(document: NoteDocument) {
        scope = document.scope
        stableKey = document.stableKey
        fileURL = document.fileURL.standardizedFileURL
    }
}

enum EditorImagePayload: Sendable {
    case fileURL(URL)
    case encoded(Data)
}

struct EditorImageConfiguration {
    let documentIdentity: MarkdownEditorDocumentIdentity
    let store: NoteImageStore
    let isEnabled: Bool
    let reportError: @MainActor (String) -> Void

    init(
        documentIdentity: MarkdownEditorDocumentIdentity,
        store: NoteImageStore,
        isEnabled: Bool,
        reportError: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.documentIdentity = documentIdentity
        self.store = store
        self.isEnabled = isEnabled
        self.reportError = reportError
    }
}

private enum EditorImageImportError: LocalizedError {
    case tooManyImages
    case batchTooLarge

    var errorDescription: String? {
        switch self {
        case .tooManyImages:
            return L10n.text(.editorImageImportErrorTooManyImages)
        case .batchTooLarge:
            return L10n.text(.editorImageImportErrorBatchTooLarge)
        }
    }
}

@MainActor
final class MarkdownEditorController: ObservableObject {
    @Published fileprivate(set) var selectionIsTodo = false
    @Published fileprivate(set) var todoCycleState: MarkdownTodoCycleState?
    @Published private(set) var hasTextSelection = false
    @Published private(set) var canToggleBoldFormat = false
    @Published private(set) var canToggleHighlightFormat = false
    private weak var textView: CheckboxTextView?
    private var pendingSelectionAfterExternalTextUpdate: PendingSelection?
    var textCompositionDidEnd: (() -> Void)?

    private struct PendingSelection {
        let range: NSRange
        let scrollToVisible: Bool
    }

    func toggleTodoFormat() {
        textView?.toggleTodoFormat()
    }

    func cycleTodoState() {
        textView?.cycleTodoState()
    }

    func toggleBoldFormat() {
        textView?.toggleInlineFormat(.bold)
    }

    func toggleHighlightFormat() {
        textView?.toggleInlineFormat(.highlight)
    }

    func currentSelectionSnapshot() -> EditorSelectionSnapshot? {
        textView?.currentSelectionMoveSnapshot()
    }

    func moveCurrentSelection() {
        textView?.moveCurrentSelection()
    }

    func blocksAutomaticWindowCollapse(in window: NSWindow) -> Bool {
        guard let textView else { return false }
        return textView.hasMarkedText()
            || (window.isKeyWindow && window.firstResponder === textView)
    }

    var hasActiveTextComposition: Bool {
        textView?.hasMarkedText() == true
    }

    fileprivate func notifyTextCompositionDidEnd() {
        textCompositionDidEnd?()
    }

    func setPendingSelectionAfterExternalTextUpdate(
        _ range: NSRange,
        scrollToVisible: Bool = true
    ) {
        pendingSelectionAfterExternalTextUpdate = PendingSelection(
            range: range,
            scrollToVisible: scrollToVisible
        )
    }

    func setPendingCaretAfterExternalTextUpdate(
        atUTF16Offset location: Int,
        scrollToVisible: Bool = true
    ) {
        setPendingSelectionAfterExternalTextUpdate(
            NSRange(location: location, length: 0),
            scrollToVisible: scrollToVisible
        )
    }

    @discardableResult
    func consumePendingSelectionAfterExternalTextUpdate(
        in textView: CheckboxTextView
    ) -> Bool {
        guard self.textView === textView,
              let pendingSelectionAfterExternalTextUpdate
        else { return false }

        self.pendingSelectionAfterExternalTextUpdate = nil
        let sourceLength = (textView.string as NSString).length
        guard let safeRange = Self.safeSelectionRange(
            pendingSelectionAfterExternalTextUpdate.range,
            sourceLength: sourceLength
        ) else { return false }

        textView.setSelectedRange(safeRange)
        if pendingSelectionAfterExternalTextUpdate.scrollToVisible {
            textView.scrollRangeToVisible(safeRange)
        }
        refreshSelectionState()
        return true
    }

    func attach(to textView: CheckboxTextView) {
        self.textView = textView
        refreshSelectionState()
    }

    fileprivate func detach(from textView: CheckboxTextView) {
        guard self.textView === textView else { return }
        self.textView = nil
        if selectionIsTodo {
            selectionIsTodo = false
        }
        todoCycleState = nil
        hasTextSelection = false
        canToggleBoldFormat = false
        canToggleHighlightFormat = false
        pendingSelectionAfterExternalTextUpdate = nil
    }

    fileprivate func refreshSelectionState() {
        let newValue = textView?.selectionIsEntirelyTodo ?? false
        if selectionIsTodo != newValue {
            selectionIsTodo = newValue
        }
        let newCycleState = textView?.currentTodoCycleState
        if todoCycleState != newCycleState {
            todoCycleState = newCycleState
        }
        let newHasTextSelection = textView?.hasNonemptySingleSelection ?? false
        if hasTextSelection != newHasTextSelection {
            hasTextSelection = newHasTextSelection
        }
        let newCanToggleBold = textView?.canToggleInlineFormat(.bold) ?? false
        if canToggleBoldFormat != newCanToggleBold {
            canToggleBoldFormat = newCanToggleBold
        }
        let newCanToggleHighlight = textView?.canToggleInlineFormat(.highlight) ?? false
        if canToggleHighlightFormat != newCanToggleHighlight {
            canToggleHighlightFormat = newCanToggleHighlight
        }
    }

    private static func safeSelectionRange(
        _ requestedRange: NSRange,
        sourceLength: Int
    ) -> NSRange? {
        guard requestedRange.location != NSNotFound,
              requestedRange.location >= 0,
              requestedRange.length >= 0
        else { return nil }

        let safeLocation = min(requestedRange.location, sourceLength)
        let safeLength = min(
            requestedRange.length,
            sourceLength - safeLocation
        )
        return NSRange(location: safeLocation, length: safeLength)
    }
}

struct PlainMarkdownTextView: NSViewRepresentable {
    let controller: MarkdownEditorController
    @Binding var text: String
    let documentIdentity: MarkdownEditorDocumentIdentity?
    let isEditable: Bool
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let appearanceID: String
    let backgroundColor: NSColor
    let textColor: NSColor
    let disabledTextColor: NSColor
    let insertionPointColor: NSColor
    let selectionBackgroundColor: NSColor
    let selectionTextColor: NSColor
    let selectionToolbarBackgroundColor: NSColor
    let selectionToolbarForegroundColor: NSColor
    let selectionToolbarAccentColor: NSColor
    let selectionToolbarHoverColor: NSColor
    let selectionToolbarSelectionColor: NSColor
    let selectionToolbarBorderColor: NSColor
    let successColor: NSColor
    let checkboxCheckmarkColor: NSColor
    let checkboxHoverBackgroundColor: NSColor
    var selectionMoveConfiguration: EditorSelectionMoveConfiguration? = nil
    var imageConfiguration: EditorImageConfiguration? = nil
    var languageRevision: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor
        scrollView.borderType = .noBorder

        let textView = CheckboxTextView()
        textView.editorController = controller
        textView.selectionMoveConfiguration = selectionMoveConfiguration
        textView.imageConfiguration = imageConfiguration
        textView.installChecklistTextStorageDelegate()
        textView.layoutManager?.delegate = context.coordinator
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = isEditable ? textColor : disabledTextColor
        textView.insertionPointColor = insertionPointColor
        // The scroll view owns the opaque editor background. Keeping the text
        // view transparent lets custom inline underlays draw before TextKit's
        // native selection and glyph pass without being painted over.
        textView.drawsBackground = false
        textView.backgroundColor = backgroundColor
        textView.selectedTextAttributes = [
            .backgroundColor: selectionBackgroundColor,
            .foregroundColor: selectionTextColor
        ]
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.updateChecklistStyle(
            fontSize: fontSize,
            completedTextColor: disabledTextColor,
            successColor: successColor,
            checkmarkColor: checkboxCheckmarkColor,
            accentColor: insertionPointColor,
            hoverBackgroundColor: checkboxHoverBackgroundColor
        )
        textView.updateSelectionToolbarStyle(
            backgroundColor: selectionToolbarBackgroundColor,
            foregroundColor: selectionToolbarForegroundColor,
            accentColor: selectionToolbarAccentColor,
            hoverColor: selectionToolbarHoverColor,
            selectionColor: selectionToolbarSelectionColor,
            borderColor: selectionToolbarBorderColor
        )

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.observeScrollBounds(in: scrollView)
        context.coordinator.appliedAppearanceID = appearanceID
        context.coordinator.appliedEditableState = isEditable
        context.coordinator.appliedLineSpacing = lineSpacing
        context.coordinator.appliedDocumentIdentity = documentIdentity
        context.coordinator.appliedLanguageRevision = languageRevision
        textView.refreshChecklistPresentation(forceLayout: true)
        controller.attach(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let didTransitionDocument = context.coordinator.transitionDocumentIfNeeded(
            to: documentIdentity,
            text: text,
            controller: controller,
            in: textView
        )
        context.coordinator.parent = self
        textView.isEditable = isEditable
        textView.selectionMoveConfiguration = selectionMoveConfiguration
        textView.imageConfiguration = imageConfiguration

        if context.coordinator.appliedLanguageRevision != languageRevision {
            textView.rebuildVisibleSelectionToolbarForLanguageChange()
            context.coordinator.appliedLanguageRevision = languageRevision
        }

        if context.coordinator.appliedAppearanceID != appearanceID
            || context.coordinator.appliedEditableState != isEditable
        {
            context.coordinator.applyAppearance(
                in: scrollView,
                backgroundColor: backgroundColor,
                textColor: isEditable ? textColor : disabledTextColor,
                insertionPointColor: insertionPointColor,
                selectionBackgroundColor: selectionBackgroundColor,
                selectionTextColor: selectionTextColor
            )
            context.coordinator.appliedAppearanceID = appearanceID
            context.coordinator.appliedEditableState = isEditable
        }

        if !didTransitionDocument,
           textView.string != text,
           !textView.hasMarkedText() {
            textView.dismissSelectionMovePill()
            let selectedRange = textView.selectedRange()
            let undoManager = textView.undoManager
            let shouldRestoreUndoRegistration = undoManager?.isUndoRegistrationEnabled == true
            context.coordinator.isApplyingExternalText = true
            textView.breakUndoCoalescing()
            undoManager?.removeAllActions()
            if shouldRestoreUndoRegistration {
                undoManager?.disableUndoRegistration()
            }
            textView.invalidateInlineFontBaseline()
            textView.string = text
            if shouldRestoreUndoRegistration {
                undoManager?.enableUndoRegistration()
            }
            undoManager?.removeAllActions()
            textView.breakUndoCoalescing()
            if !controller.consumePendingSelectionAfterExternalTextUpdate(in: textView) {
                let safeLocation = min(selectedRange.location, (text as NSString).length)
                let safeLength = min(
                    selectedRange.length,
                    (text as NSString).length - safeLocation
                )
                textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            }
            context.coordinator.isApplyingExternalText = false
        }

        let editorFontSizeChanged = textView.updateBaseFontSizeIfNeeded(fontSize)

        if context.coordinator.appliedLineSpacing != lineSpacing {
            context.coordinator.refreshLineSpacing(in: scrollView)
            context.coordinator.appliedLineSpacing = lineSpacing
        }

        textView.updateChecklistStyle(
            fontSize: fontSize,
            completedTextColor: disabledTextColor,
            successColor: successColor,
            checkmarkColor: checkboxCheckmarkColor,
            accentColor: insertionPointColor,
            hoverBackgroundColor: checkboxHoverBackgroundColor
        )
        textView.updateSelectionToolbarStyle(
            backgroundColor: selectionToolbarBackgroundColor,
            foregroundColor: isEditable
                ? selectionToolbarForegroundColor
                : disabledTextColor,
            accentColor: selectionToolbarAccentColor,
            hoverColor: selectionToolbarHoverColor,
            selectionColor: selectionToolbarSelectionColor,
            borderColor: selectionToolbarBorderColor
        )
        textView.refreshChecklistPresentation(forceLayout: editorFontSizeChanged)
        controller.refreshSelectionState()
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = coordinator.textView else { return }
        coordinator.stopObservingScrollBounds()
        textView.dismissSelectionMovePill()
        textView.cancelPendingImageImports()
        coordinator.parent.controller.detach(from: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: PlainMarkdownTextView
        weak var textView: CheckboxTextView?
        var isApplyingExternalText = false
        var isApplyingAppearance = false
        var appliedAppearanceID: String?
        var appliedEditableState: Bool?
        var appliedLineSpacing: CGFloat?
        var appliedDocumentIdentity: MarkdownEditorDocumentIdentity?
        var appliedLanguageRevision: String?
        private var scrollBoundsObserver: NSObjectProtocol?

        init(parent: PlainMarkdownTextView) {
            self.parent = parent
        }

        deinit {
            stopObservingScrollBounds()
        }

        func observeScrollBounds(in scrollView: NSScrollView) {
            stopObservingScrollBounds()
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            scrollBoundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak textView] _ in
                textView?.dismissSelectionMovePill()
            }
        }

        func stopObservingScrollBounds() {
            guard let scrollBoundsObserver else { return }
            NotificationCenter.default.removeObserver(scrollBoundsObserver)
            self.scrollBoundsObserver = nil
        }

        @MainActor
        @discardableResult
        func transitionDocumentIfNeeded(
            to nextIdentity: MarkdownEditorDocumentIdentity?,
            text desiredText: String,
            controller: MarkdownEditorController,
            in textView: CheckboxTextView
        ) -> Bool {
            guard appliedDocumentIdentity != nextIdentity else { return false }

            textView.dismissSelectionMovePill()
            textView.prepareForDocumentIdentityChange()
            let selectedRange = textView.selectedRange()
            let undoManager = textView.undoManager
            let shouldRestoreUndoRegistration = undoManager?.isUndoRegistrationEnabled == true

            // A document switch is an external replacement transaction. Ending
            // the old composition while this guard is active prevents an IME
            // callback from writing the old document's marked text through the
            // new SwiftUI binding.
            isApplyingExternalText = true
            textView.breakUndoCoalescing()
            undoManager?.removeAllActions()
            if shouldRestoreUndoRegistration {
                undoManager?.disableUndoRegistration()
            }
            if textView.hasMarkedText() {
                // End both halves of Cocoa text input: notify the input system
                // to discard its conversion session, then clear the client's
                // marked range before this view represents another document.
                textView.inputContext?.discardMarkedText()
                textView.unmarkText()
            }
            // Assign unconditionally: two different documents may have exactly
            // the same Markdown, but they must still form a hard editing boundary.
            textView.string = desiredText
            if shouldRestoreUndoRegistration {
                undoManager?.enableUndoRegistration()
            }
            undoManager?.removeAllActions()
            textView.breakUndoCoalescing()

            if !controller.consumePendingSelectionAfterExternalTextUpdate(in: textView) {
                let sourceLength = (desiredText as NSString).length
                let safeLocation = min(selectedRange.location, sourceLength)
                let safeLength = min(selectedRange.length, sourceLength - safeLocation)
                textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
            }
            isApplyingExternalText = false
            appliedDocumentIdentity = nextIdentity
            return true
        }

        func applyAppearance(
            in scrollView: NSScrollView,
            backgroundColor: NSColor,
            textColor: NSColor,
            insertionPointColor: NSColor,
            selectionBackgroundColor: NSColor,
            selectionTextColor: NSColor
        ) {
            guard let textView else { return }

            let selectedRanges = textView.selectedRanges
            let scrollOrigin = scrollView.contentView.bounds.origin
            let undoManager = textView.undoManager
            let shouldRestoreUndoRegistration = undoManager?.isUndoRegistrationEnabled == true

            isApplyingAppearance = true
            if shouldRestoreUndoRegistration {
                undoManager?.disableUndoRegistration()
            }

            scrollView.backgroundColor = backgroundColor
            textView.backgroundColor = backgroundColor
            textView.textColor = textColor
            textView.insertionPointColor = insertionPointColor
            textView.selectedTextAttributes = [
                .backgroundColor: selectionBackgroundColor,
                .foregroundColor: selectionTextColor
            ]
            textView.typingAttributes[.foregroundColor] = textColor

            textView.selectedRanges = selectedRanges
            scrollView.contentView.scroll(to: scrollOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)

            if shouldRestoreUndoRegistration {
                undoManager?.enableUndoRegistration()
            }
            isApplyingAppearance = false
        }

        func refreshLineSpacing(in scrollView: NSScrollView) {
            guard let textView,
                  let layoutManager = textView.layoutManager
            else { return }

            let selectedRanges = textView.selectedRanges
            let selectionAffinity = textView.selectionAffinity
            let scrollOrigin = scrollView.contentView.bounds.origin
            let characterRange = NSRange(
                location: 0,
                length: textView.textStorage?.length ?? 0
            )
            layoutManager.invalidateLayout(
                forCharacterRange: characterRange,
                actualCharacterRange: nil
            )
            layoutManager.invalidateDisplay(forCharacterRange: characterRange)
            if let textContainer = textView.textContainer {
                layoutManager.ensureLayout(for: textContainer)
            }
            if textView.selectedRanges != selectedRanges {
                textView.setSelectedRanges(
                    selectedRanges,
                    affinity: selectionAffinity,
                    stillSelecting: false
                )
            }
            scrollView.contentView.scroll(to: scrollOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            textView.needsDisplay = true
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            lineSpacingAfterGlyphAt glyphIndex: Int,
            withProposedLineFragmentRect rect: NSRect
        ) -> CGFloat {
            guard glyphIndex + 1 < layoutManager.numberOfGlyphs else {
                return 0
            }
            return parent.lineSpacing
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
            properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
            characterIndexes charIndexes: UnsafePointer<Int>,
            font aFont: NSFont,
            forGlyphRange glyphRange: NSRange
        ) -> Int {
            guard let textView, glyphRange.length > 0 else { return 0 }

            let count = glyphRange.length
            let generatedGlyphs = Array(
                UnsafeBufferPointer(start: glyphs, count: count)
            )
            var generatedProperties = Array(
                UnsafeBufferPointer(start: props, count: count)
            )
            let generatedCharacterIndexes = Array(
                UnsafeBufferPointer(start: charIndexes, count: count)
            )
            var collapsedAnyMarkdown = false

            for index in 0..<count {
                if textView.isInlineFormatDelimiter(
                    atUTF16Offset: generatedCharacterIndexes[index]
                ) {
                    // Inline-format Markdown is a storage detail. Every UTF-16
                    // unit in both the opening and closing delimiter becomes a
                    // null glyph, so the valid token has exactly the width of
                    // its visible content while the source string stays intact.
                    generatedProperties[index].insert(.null)
                    collapsedAnyMarkdown = true
                    continue
                }
                if let imageRange = textView.managedImageRange(
                    containingUTF16Offset: generatedCharacterIndexes[index]
                ) {
                    if generatedCharacterIndexes[index] == imageRange.location {
                        generatedProperties[index].insert(.controlCharacter)
                    } else {
                        generatedProperties[index].insert(.null)
                    }
                    collapsedAnyMarkdown = true
                    continue
                }
                guard let prefixRange = textView.checklistPrefixRange(
                    containingUTF16Offset: generatedCharacterIndexes[index]
                ) else { continue }
                if generatedCharacterIndexes[index] == prefixRange.location {
                    generatedProperties[index].insert(.controlCharacter)
                } else {
                    generatedProperties[index].insert(.null)
                }
                collapsedAnyMarkdown = true
            }

            guard collapsedAnyMarkdown else { return 0 }
            generatedGlyphs.withUnsafeBufferPointer { glyphBuffer in
                generatedProperties.withUnsafeBufferPointer { propertyBuffer in
                    generatedCharacterIndexes.withUnsafeBufferPointer { characterBuffer in
                        layoutManager.setGlyphs(
                            glyphBuffer.baseAddress!,
                            properties: propertyBuffer.baseAddress!,
                            characterIndexes: characterBuffer.baseAddress!,
                            font: aFont,
                            forGlyphRange: glyphRange
                        )
                    }
                }
            }
            return count
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldUse action: NSLayoutManager.ControlCharacterAction,
            forControlCharacterAt charIndex: Int
        ) -> NSLayoutManager.ControlCharacterAction {
            guard textView?.isChecklistPrefixStart(atUTF16Offset: charIndex) == true
                    || textView?.isManagedImageStart(atUTF16Offset: charIndex) == true
            else {
                return action
            }
            return .whitespace
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            boundingBoxForControlGlyphAt glyphIndex: Int,
            for textContainer: NSTextContainer,
            proposedLineFragment proposedRect: NSRect,
            glyphPosition: NSPoint,
            characterIndex charIndex: Int
        ) -> NSRect {
            guard let textView else {
                return NSRect(
                    x: glyphPosition.x,
                    y: proposedRect.minY,
                    width: 0,
                    height: proposedRect.height
                )
            }
            if textView.isManagedImageStart(atUTF16Offset: charIndex) {
                let size = textView.managedImageLayoutSize(
                    atUTF16Offset: charIndex,
                    in: textContainer
                )
                return NSRect(
                    x: glyphPosition.x,
                    y: proposedRect.minY,
                    width: size.width,
                    height: size.height
                )
            }
            guard textView.isChecklistPrefixStart(atUTF16Offset: charIndex) else {
                return NSRect(
                    x: glyphPosition.x,
                    y: proposedRect.minY,
                    width: 0,
                    height: proposedRect.height
                )
            }
            return NSRect(
                x: glyphPosition.x,
                y: proposedRect.minY,
                width: textView.checklistPrefixDisplayWidth,
                height: proposedRect.height
            )
        }

        func layoutManager(
            _ layoutManager: NSLayoutManager,
            shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
            lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
            baselineOffset: UnsafeMutablePointer<CGFloat>,
            in textContainer: NSTextContainer,
            forGlyphRange glyphRange: NSRange
        ) -> Bool {
            guard let textView, glyphRange.length > 0 else { return false }
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            guard let imageMatch = textView.managedImageMatches.first(where: {
                NSLocationInRange($0.tokenRange.location, characterRange)
            }) else { return false }

            let size = textView.managedImageLayoutSize(
                atUTF16Offset: imageMatch.tokenRange.location,
                in: textContainer
            )
            lineFragmentRect.pointee.size.height = max(
                lineFragmentRect.pointee.height,
                size.height
            )
            lineFragmentUsedRect.pointee.size.width = max(
                lineFragmentUsedRect.pointee.width,
                size.width
            )
            lineFragmentUsedRect.pointee.size.height = max(
                lineFragmentUsedRect.pointee.height,
                size.height
            )
            baselineOffset.pointee = max(
                baselineOffset.pointee,
                size.height - 8
            )
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? CheckboxTextView else {
                return
            }
            textView.dismissSelectionMovePill()
            guard !isApplyingExternalText,
                  !isApplyingAppearance,
                  !textView.isApplyingChecklistPresentation
            else { return }
            textView.refreshChecklistPresentation(forceLayout: true)
            parent.controller.refreshSelectionState()
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? CheckboxTextView else {
                return
            }
            parent.controller.refreshSelectionState()
            guard !isApplyingExternalText, !isApplyingAppearance else {
                textView.dismissSelectionMovePill()
                return
            }
            textView.selectionDidChangeForMovePill()
        }
    }
}

final class SymmetricSelectionLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        guard rectCount > 0,
              let textView = firstTextView as? CheckboxTextView,
              textView.shouldCenterSelectionBackground(
                  forCharacterRange: charRange,
                  color: color
              )
        else {
            super.fillBackgroundRectArray(
                rectArray,
                count: rectCount,
                forCharacterRange: charRange,
                color: color
            )
            return
        }

        var adjustedRects = Array(
            UnsafeBufferPointer(start: rectArray, count: rectCount)
        )
        var changedAnyRect = false
        for index in adjustedRects.indices {
            guard let offset = centeredLineSpacingOffset(
                for: adjustedRects[index],
                textView: textView,
                coordinatesIncludeTextContainerOrigin: true
            ) else { continue }
            adjustedRects[index].origin.y += offset
            changedAnyRect = true
        }
        guard changedAnyRect else {
            super.fillBackgroundRectArray(
                rectArray,
                count: rectCount,
                forCharacterRange: charRange,
                color: color
            )
            return
        }

        adjustedRects.withUnsafeBufferPointer { adjustedBuffer in
            guard let adjustedBaseAddress = adjustedBuffer.baseAddress else {
                return
            }
            super.fillBackgroundRectArray(
                adjustedBaseAddress,
                count: adjustedBuffer.count,
                forCharacterRange: charRange,
                color: color
            )
        }
    }

    func centeredInsertionPointRect(
        _ rect: NSRect,
        textView: CheckboxTextView
    ) -> NSRect {
        guard let offset = centeredLineSpacingOffset(
            for: rect,
            textView: textView,
            coordinatesIncludeTextContainerOrigin: true
        ) else { return rect }
        return rect.offsetBy(dx: 0, dy: offset)
    }

    private func centeredLineSpacingOffset(
        for rect: NSRect,
        textView: CheckboxTextView,
        coordinatesIncludeTextContainerOrigin: Bool
    ) -> CGFloat? {
        guard !textView.hasMarkedText(),
              let textContainer = textView.textContainer,
              numberOfGlyphs > 0
        else { return nil }

        let lineSpacing = textView.selectionGeometryLineSpacing
        guard lineSpacing > 0 else { return nil }

        let containerRect = coordinatesIncludeTextContainerOrigin
            ? rect.offsetBy(
                dx: -textView.textContainerOrigin.x,
                dy: -textView.textContainerOrigin.y
            )
            : rect
        let probePoint = NSPoint(
            x: max(containerRect.minX, 0),
            y: containerRect.midY
        )
        let glyphIndex = glyphIndex(
            for: probePoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < numberOfGlyphs else { return nil }

        var lineGlyphRange = NSRange()
        let lineRect = lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &lineGlyphRange
        )
        guard abs(lineRect.minY - containerRect.minY) <= 0.5,
              NSMaxRange(lineGlyphRange) < numberOfGlyphs,
              !textView.lineContainsManagedImage(lineGlyphRange)
        else { return nil }

        // `lineSpacingAfterGlyphAt` enlarges this native line fragment only
        // below the glyph baseline. Moving the unchanged selection/caret rect
        // upward by half that spacing produces equal visual leading while
        // preserving TextKit's x geometry, rect size, hit testing and layout.
        return -lineSpacing / 2
    }
}

final class CheckboxTextView: NSTextView, NSTextStorageDelegate {
    private var ownedTextStorage: NSTextStorage?

    private static func makeSelectionTextSystem() -> (
        textStorage: NSTextStorage,
        textContainer: NSTextContainer
    ) {
        let textStorage = NSTextStorage()
        let layoutManager = SymmetricSelectionLayoutManager()
        let textContainer = NSTextContainer()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        return (textStorage, textContainer)
    }

    override convenience init(frame frameRect: NSRect) {
        let textSystem = Self.makeSelectionTextSystem()
        self.init(frame: frameRect, textContainer: textSystem.textContainer)
        ownedTextStorage = textSystem.textStorage
    }

    override init(
        frame frameRect: NSRect,
        textContainer container: NSTextContainer?
    ) {
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private struct CheckboxGeometry {
        let match: MarkdownCheckboxMatch
        let boxRect: NSRect
        let hitRect: NSRect
    }

    private struct ManagedImagePreview {
        let image: NSImage
        let pixelWidth: Int
        let pixelHeight: Int
    }

    private struct DecodedManagedImagePreview: @unchecked Sendable {
        let image: CGImage
    }

    private struct ManagedImageGeometry {
        let match: MarkdownImageMatch
        let previewRect: NSRect
        let hitRect: NSRect
        let fileURL: URL?
        let preview: ManagedImagePreview?
    }

    private struct PendingImageInsertion {
        let generation: UInt
        let documentIdentity: MarkdownEditorDocumentIdentity
        let sourceText: String
        let replacementRange: NSRange
        let requiresSelectionMatch: Bool
    }

    private struct ImageBoundaryComposition {
        let prefix: String
        let suffix: String
    }

    private enum InlineTextDirection {
        case backward
        case forward
    }

    private struct SelectionMoveIdentity: Equatable {
        let sourceDocument: NoteDocument
        let destinationDocument: NoteDocument
        let selectionStableKey: String

        init?(_ configuration: EditorSelectionMoveConfiguration?) {
            guard let configuration else { return nil }
            sourceDocument = configuration.sourceDocument
            destinationDocument = configuration.destinationDocument
            selectionStableKey = configuration.selectionStableKey
        }
    }

    private struct SelectionToolbarSnapshot: Equatable {
        let sourceText: String
        let range: NSRange
    }

    private final class SelectionToolbarButton: NSButton {
        enum Role {
            case format
            case highlight
            case move
        }

        let role: Role
        var isSelected = false {
            didSet { applyAppearance() }
        }
        var normalForegroundColor: NSColor = .labelColor
        var accentForegroundColor: NSColor = .controlAccentColor
        var hoverBackgroundColor: NSColor = .clear
        var pressedBackgroundColor: NSColor = .clear
        var selectedBackgroundColor: NSColor = .clear
        var highlightSelectedBackgroundColor: NSColor = .clear

        private var hoverTrackingArea: NSTrackingArea?
        private var isHovered = false
        private var isPressed = false
        private var renderedForegroundColor: NSColor = .labelColor

        init(role: Role) {
            self.role = role
            super.init(frame: .zero)
            isBordered = false
            focusRingType = .none
            refusesFirstResponder = true
            imageScaling = .scaleProportionallyDown
            wantsLayer = true
            layer?.cornerRadius = 7
            layer?.masksToBounds = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { false }

        override func becomeFirstResponder() -> Bool {
            false
        }

        override func draw(_ dirtyRect: NSRect) {
            switch role {
            case .move:
                super.draw(dirtyRect)
            case .format:
                drawBoldGlyph()
            case .highlight:
                drawHighlighterGlyph()
            }
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverTrackingArea {
                removeTrackingArea(hoverTrackingArea)
            }
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            hoverTrackingArea = trackingArea
        }

        override func mouseEntered(with event: NSEvent) {
            isHovered = true
            applyAppearance()
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            applyAppearance()
        }

        override func mouseDown(with event: NSEvent) {
            isPressed = true
            applyAppearance()
            super.mouseDown(with: event)
            isPressed = false
            applyAppearance()
        }

        func applyAppearance() {
            let foregroundColor: NSColor
            let backgroundColor: NSColor
            if !isEnabled {
                foregroundColor = normalForegroundColor.withAlphaComponent(0.42)
                backgroundColor = .clear
            } else if isPressed {
                foregroundColor = isSelected
                    ? accentForegroundColor
                    : normalForegroundColor
                backgroundColor = pressedBackgroundColor
            } else if isSelected {
                foregroundColor = role == .highlight
                    ? normalForegroundColor
                    : accentForegroundColor
                backgroundColor = role == .highlight
                    ? highlightSelectedBackgroundColor
                    : selectedBackgroundColor
            } else if isHovered {
                foregroundColor = normalForegroundColor
                backgroundColor = hoverBackgroundColor
            } else {
                foregroundColor = normalForegroundColor
                backgroundColor = .clear
            }

            contentTintColor = foregroundColor
            renderedForegroundColor = foregroundColor
            layer?.backgroundColor = backgroundColor.cgColor
            alphaValue = isEnabled ? 1 : 0.78

            if !title.isEmpty {
                let weight: NSFont.Weight = role == .format ? .bold : .semibold
                attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [
                        .font: NSFont.systemFont(
                            ofSize: role == .format ? 15 : 12,
                            weight: weight
                        ),
                        .foregroundColor: foregroundColor
                    ]
                )
            }
            needsDisplay = true
        }

        private func drawBoldGlyph() {
            let glyph = NSAttributedString(
                string: "B",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15, weight: .bold),
                    .foregroundColor: renderedForegroundColor
                ]
            )
            let glyphSize = glyph.size()
            glyph.draw(
                at: NSPoint(
                    x: (bounds.midX - glyphSize.width / 2).rounded(.down),
                    y: (bounds.midY - glyphSize.height / 2).rounded(.down)
                )
            )
        }

        private func drawHighlighterGlyph() {
            guard let symbol = NSImage(
                systemSymbolName: "highlighter",
                accessibilityDescription: nil
            ) ?? NSImage(
                systemSymbolName: "pencil.tip",
                accessibilityDescription: nil
            ) else { return }

            let pointConfiguration = NSImage.SymbolConfiguration(
                pointSize: 14,
                weight: .semibold
            )
            let colorConfiguration = NSImage.SymbolConfiguration(
                hierarchicalColor: renderedForegroundColor
            )
            let configuredSymbol = symbol.withSymbolConfiguration(
                pointConfiguration.applying(colorConfiguration)
            ) ?? symbol
            let naturalSize = configuredSymbol.size
            let maximumDimension: CGFloat = 16
            let scale = min(
                maximumDimension / max(naturalSize.width, 1),
                maximumDimension / max(naturalSize.height, 1)
            )
            let drawSize = NSSize(
                width: naturalSize.width * scale,
                height: naturalSize.height * scale
            )
            let drawRect = NSRect(
                x: (bounds.midX - drawSize.width / 2).rounded(.down),
                y: (bounds.midY - drawSize.height / 2).rounded(.down),
                width: drawSize.width,
                height: drawSize.height
            )
            configuredSymbol.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
    }

    private final class SelectionToolbarView: NSView {
        static let height: CGFloat = 34
        static let formatButtonSize = NSSize(width: 28, height: 28)
        static let moveButtonHeight: CGFloat = 28

        let boldButton = SelectionToolbarButton(role: .format)
        let highlightButton = SelectionToolbarButton(role: .highlight)
        let moveButton = SelectionToolbarButton(role: .move)
        private let separator = NSView()

        private(set) var preferredSize = NSSize(width: 194, height: height)

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            identifier = NSUserInterfaceItemIdentifier("selection-toolbar")
            wantsLayer = true
            layer?.cornerRadius = 9
            layer?.borderWidth = 0.5
            layer?.masksToBounds = false
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.2
            layer?.shadowRadius = 8
            layer?.shadowOffset = NSSize(width: 0, height: -2)

            boldButton.identifier = NSUserInterfaceItemIdentifier(
                "selection-toolbar-bold"
            )
            boldButton.title = "B"
            boldButton.toolTip = L10n.text(.editorSelectionToolbarBoldTooltip)
            boldButton.setAccessibilityLabel(
                L10n.text(.editorSelectionToolbarBoldLabel)
            )

            highlightButton.identifier = NSUserInterfaceItemIdentifier(
                "selection-toolbar-highlight"
            )
            highlightButton.title = ""
            highlightButton.image = NSImage(
                systemSymbolName: "highlighter",
                accessibilityDescription: nil
            ) ?? NSImage(
                systemSymbolName: "pencil.tip",
                accessibilityDescription: nil
            )
            highlightButton.imagePosition = .imageOnly
            highlightButton.toolTip = L10n.text(
                .editorSelectionToolbarHighlightTooltip
            )
            highlightButton.setAccessibilityLabel(
                L10n.text(.editorSelectionToolbarHighlightLabel)
            )

            moveButton.identifier = NSUserInterfaceItemIdentifier(
                "selection-toolbar-move"
            )
            moveButton.image = NSImage(
                systemSymbolName: "arrow.right",
                accessibilityDescription: nil
            )
            moveButton.imagePosition = .imageLeading
            moveButton.imageHugsTitle = true
            moveButton.cell?.lineBreakMode = .byTruncatingMiddle

            separator.identifier = NSUserInterfaceItemIdentifier(
                "selection-toolbar-separator"
            )
            separator.wantsLayer = true

            addSubview(boldButton)
            addSubview(highlightButton)
            addSubview(separator)
            addSubview(moveButton)
            setAccessibilityRole(.toolbar)
            setAccessibilityLabel(L10n.text(.editorSelectionToolbarLabel))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { false }

        override func becomeFirstResponder() -> Bool {
            false
        }

        func updateMoveAction(
            title: String?,
            isEnabled: Bool,
            toolTip: String?
        ) {
            let showsMoveAction = title != nil
            separator.isHidden = !showsMoveAction
            moveButton.isHidden = !showsMoveAction
            moveButton.title = title ?? ""
            moveButton.isEnabled = isEnabled
            moveButton.toolTip = toolTip
            let accessibilityLabel: String
            if !isEnabled,
               let title,
               let toolTip,
               toolTip != title {
                accessibilityLabel = "\(title): \(toolTip)"
            } else {
                accessibilityLabel = toolTip
                    ?? title
                    ?? L10n.text(.editorSelectionToolbarMoveLabel)
            }
            moveButton.setAccessibilityLabel(accessibilityLabel)
            moveButton.applyAppearance()
            updatePreferredSize()
        }

        func updateFormatStates(
            bold: Bool,
            boldEnabled: Bool,
            highlight: Bool,
            highlightEnabled: Bool
        ) {
            boldButton.isEnabled = boldEnabled
            highlightButton.isEnabled = highlightEnabled
            boldButton.isSelected = bold
            highlightButton.isSelected = highlight
            boldButton.state = bold ? .on : .off
            highlightButton.state = highlight ? .on : .off
            boldButton.setAccessibilityValue(
                L10n.text(bold ? .accessibilityValueOn : .accessibilityValueOff)
            )
            highlightButton.setAccessibilityValue(
                L10n.text(highlight ? .accessibilityValueOn : .accessibilityValueOff)
            )
            boldButton.setAccessibilityHelp(
                L10n.text(
                    boldEnabled
                        ? .editorSelectionToolbarBoldHelpEnabled
                        : .editorSelectionToolbarBoldHelpDisabled
                )
            )
            highlightButton.setAccessibilityHelp(
                L10n.text(
                    highlightEnabled
                        ? .editorSelectionToolbarHighlightHelpEnabled
                        : .editorSelectionToolbarHighlightHelpDisabled
                )
            )
            boldButton.applyAppearance()
            highlightButton.applyAppearance()
        }

        func applyStyle(
            backgroundColor: NSColor,
            foregroundColor: NSColor,
            accentColor: NSColor,
            borderColor: NSColor
        ) {
            layer?.backgroundColor = backgroundColor.cgColor
            layer?.borderColor = borderColor.cgColor
            separator.layer?.backgroundColor = borderColor.cgColor
            let rgb = backgroundColor.usingColorSpace(.deviceRGB)
                ?? backgroundColor
            let luminance = 0.2126 * rgb.redComponent
                + 0.7152 * rgb.greenComponent
                + 0.0722 * rgb.blueComponent
            let usesDarkSurface = luminance < 0.5
            let neutralOverlay = usesDarkSurface ? NSColor.white : NSColor.black
            layer?.shadowOpacity = usesDarkSurface ? 0.42 : 0.20
            layer?.shadowRadius = 8
            layer?.shadowOffset = NSSize(width: 0, height: -2)

            for button in [boldButton, highlightButton, moveButton] {
                button.normalForegroundColor = foregroundColor
                button.accentForegroundColor = accentColor
                button.hoverBackgroundColor = neutralOverlay.withAlphaComponent(
                    usesDarkSurface ? 0.10 : 0.07
                )
                button.pressedBackgroundColor = neutralOverlay.withAlphaComponent(
                    usesDarkSurface ? 0.16 : 0.12
                )
                button.selectedBackgroundColor = accentColor.withAlphaComponent(
                    usesDarkSurface ? 0.24 : 0.18
                )
                button.highlightSelectedBackgroundColor = NSColor.systemYellow
                    .withAlphaComponent(usesDarkSurface ? 0.38 : 0.34)
                button.applyAppearance()
            }
        }

        override func layout() {
            super.layout()
            let y: CGFloat = 3
            let buttonSize = Self.formatButtonSize
            boldButton.frame = NSRect(
                x: 3,
                y: y,
                width: buttonSize.width,
                height: buttonSize.height
            )
            highlightButton.frame = NSRect(
                x: boldButton.frame.maxX + 2,
                y: y,
                width: buttonSize.width,
                height: buttonSize.height
            )

            guard !moveButton.isHidden else { return }
            separator.frame = NSRect(
                x: highlightButton.frame.maxX + 7,
                y: 8,
                width: 1,
                height: 18
            )
            moveButton.frame = NSRect(
                x: separator.frame.maxX + 7,
                y: y,
                width: max(0, bounds.width - separator.frame.maxX - 10),
                height: Self.moveButtonHeight
            )
        }

        private func updatePreferredSize() {
            let formatWidth: CGFloat = 3 + 28 + 2 + 28 + 3
            if moveButton.isHidden {
                preferredSize = NSSize(width: formatWidth, height: Self.height)
            } else {
                let labelWidth = ceil(moveButton.attributedTitle.size().width)
                let moveWidth = min(max(labelWidth + 40, 111), 122)
                preferredSize = NSSize(
                    width: formatWidth + 15 + moveWidth,
                    height: Self.height
                )
            }
            frame.size = preferredSize
            needsLayout = true
        }
    }

    weak var editorController: MarkdownEditorController?
    var imageConfiguration: EditorImageConfiguration? {
        didSet {
            let oldIdentity = oldValue?.documentIdentity
            let newIdentity = imageConfiguration?.documentIdentity
            let oldRoot = oldValue?.store.rootURL
            let newRoot = imageConfiguration?.store.rootURL
            let becameDisabled = oldValue?.isEnabled == true
                && imageConfiguration?.isEnabled != true
            if oldIdentity != newIdentity || oldRoot != newRoot || becameDisabled {
                cancelPendingImageImports()
            }
            if oldIdentity != newIdentity || oldRoot != newRoot {
                resetManagedImagePresentation()
                refreshChecklistPresentation(forceLayout: true)
            }
        }
    }
    var selectionMoveConfiguration: EditorSelectionMoveConfiguration? {
        didSet {
            let identityChanged = SelectionMoveIdentity(oldValue)
                != SelectionMoveIdentity(selectionMoveConfiguration)
            let availabilityChanged = oldValue?.isEnabled
                != selectionMoveConfiguration?.isEnabled
            if identityChanged || availabilityChanged {
                dismissSelectionMovePill()
                scheduleSelectionMovePillPresentation()
            } else {
                refreshSelectionMovePillLabel()
            }
        }
    }
    var selectionMovePresentationDelay: TimeInterval = 0.14
    fileprivate private(set) var checklistMatches: [MarkdownCheckboxMatch] = [] {
        didSet {
            var prefixStartOffsets = Set<Int>()
            prefixStartOffsets.reserveCapacity(checklistMatches.count)
            for match in checklistMatches {
                prefixStartOffsets.insert(match.prefixRange.location)
            }
            checklistPrefixRanges = checklistMatches.map(\.prefixRange)
            checklistPrefixStartOffsets = prefixStartOffsets
        }
    }
    fileprivate private(set) var checklistFontSize: CGFloat = 15

    private var completedTextColor: NSColor = .secondaryLabelColor
    private var successColor: NSColor = .systemGreen
    private var checkmarkColor: NSColor = .textBackgroundColor
    private var accentColor: NSColor = .controlAccentColor
    private var hoverBackgroundColor: NSColor = .controlBackgroundColor
    private var presentationStyleRevision = 0
    private var appliedPresentationStyleRevision = -1
    private var appliedPresentationText: String?
    private var appliedGlyphFontSize: CGFloat = -1
    private var appliedStorageFontSize: CGFloat = -1
    private var appliedBoldFontRanges: [NSRange] = []
    private var hoveredMarkerLocation: Int?
    private var checkboxTrackingArea: NSTrackingArea?
    private var checklistPrefixRanges: [NSRange] = []
    private var checklistPrefixStartOffsets = Set<Int>()
    private var checklistGlyphIndexSourceText: String?
    private var inlineFormatMatches: [MarkdownInlineFormatMatch] = []
    private var inlineFormatDelimiterRanges: [NSRange] = []
    private var inlineFormatDelimiterOffsets = Set<Int>()
    private var inlineFormatIndexSourceText: String?
    private(set) var managedImageMatches: [MarkdownImageMatch] = []
    private var managedImageRanges: [NSRange] = []
    private var managedImageStartOffsets = Set<Int>()
    // Markdown offsets move whenever text is edited above an image. Keep the
    // resolved asset keyed by its stable Markdown destination so presentation
    // never temporarily loses the image while NSTextStorage is relaying edits.
    private var managedImageURLsByDestination: [String: URL] = [:]
    private var managedImagePreviews: [URL: ManagedImagePreview] = [:]
    // Keep decoded dimensions independently of the bounded bitmap cache. If a
    // preview bitmap is evicted, its line must retain the natural aspect ratio
    // instead of jumping back to the temporary 16:9 placeholder.
    private var managedImagePixelSizes: [URL: NSSize] = [:]
    private var requestedManagedImageURLs = Set<URL>()
    private var failedManagedImageURLs = Set<URL>()
    private var managedImageLoadGeneration: UInt = 0
    private var imageImportGeneration: UInt = 0
    private var pendingImageImportCount = 0
    private var imageBoundaryComposition: ImageBoundaryComposition?
    private let imageImportQueue = DispatchQueue(
        label: "tech.jiangsir.codexnotes.image-import",
        qos: .userInitiated
    )
    private let imagePreviewQueue = DispatchQueue(
        label: "tech.jiangsir.codexnotes.image-preview",
        qos: .utility
    )
    fileprivate private(set) var isApplyingChecklistPresentation = false
    private var isApplyingMarkdownEditPlan = false
    private var hasPendingChecklistPresentationRefresh = false
    private var selectionMovePresentationWorkItem: DispatchWorkItem?
    private var selectionMovePresentationGeneration: UInt = 0
    private var displayedSelectionToolbarSnapshot: SelectionToolbarSnapshot?
    private var selectionToolbarView: SelectionToolbarView?
    private var isHandlingMouseSelection = false
    private var isAdjustingInlineKeyboardSelection = false
    private var inlineKeyboardSelectionAnchor: Int?
    private var inlineKeyboardSelectionActiveLocation: Int?
    private var windowDidResignKeyObserver: NSObjectProtocol?
    private var selectionToolbarBackgroundColor: NSColor = .controlBackgroundColor
    private var selectionToolbarForegroundColor: NSColor = .labelColor
    private var selectionToolbarAccentColor: NSColor = .controlAccentColor
    private var selectionToolbarBorderColor: NSColor = .separatorColor

    fileprivate var selectionGeometryLineSpacing: CGFloat {
        guard let coordinator = layoutManager?.delegate
                as? PlainMarkdownTextView.Coordinator
        else { return 0 }
        return max(0, coordinator.parent.lineSpacing)
    }

    fileprivate func shouldCenterSelectionBackground(
        forCharacterRange characterRange: NSRange,
        color _: NSColor
    ) -> Bool {
        guard !hasMarkedText(),
              layoutManager?.textViewForBeginningOfSelection === self,
              characterRange.location != NSNotFound,
              characterRange.length > 0
        else { return false }

        return selectedRanges.contains { value in
            let selectedRange = value.rangeValue
            return selectedRange.location != NSNotFound
                && selectedRange.length > 0
                && NSIntersectionRange(
                    selectedRange,
                    characterRange
                ).length > 0
        }
    }

    fileprivate func lineContainsManagedImage(_ glyphRange: NSRange) -> Bool {
        guard let layoutManager,
              glyphRange.location != NSNotFound,
              glyphRange.length > 0
        else { return false }
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        return managedImageMatches.contains {
            NSIntersectionRange($0.tokenRange, characterRange).length > 0
        }
    }

    override func setNeedsDisplay(
        _ invalidRect: NSRect,
        avoidAdditionalLayout flag: Bool
    ) {
        let halfLineSpacing = selectionGeometryLineSpacing / 2
        guard halfLineSpacing > 0,
              !invalidRect.isEmpty,
              invalidRect.minY.isFinite,
              invalidRect.maxY.isFinite
        else {
            super.setNeedsDisplay(
                invalidRect,
                avoidAdditionalLayout: flag
            )
            return
        }

        // Selection and caret rectangles are shifted into the upper half of
        // the inter-line gap without changing their size. TextKit invalidates
        // their original rectangles, so include both the native and shifted
        // bounds to prevent stale pixels after deselection or a blink-off.
        super.setNeedsDisplay(
            invalidRect.insetBy(dx: 0, dy: -halfLineSpacing),
            avoidAdditionalLayout: flag
        )
    }

    override var isEditable: Bool {
        didSet {
            if !isEditable {
                cancelPendingImageImports()
                dismissSelectionMovePill()
                if imageBoundaryComposition != nil, hasMarkedText() {
                    inputContext?.discardMarkedText()
                    unmarkText()
                }
                imageBoundaryComposition = nil
            }
        }
    }

    deinit {
        imageImportGeneration &+= 1
        managedImageLoadGeneration &+= 1
        selectionMovePresentationWorkItem?.cancel()
        if let windowDidResignKeyObserver {
            NotificationCenter.default.removeObserver(windowDidResignKeyObserver)
        }
    }

    var hasNonemptySingleSelection: Bool {
        selectionRangeSnapshot() != nil
    }

    func currentSelectionMoveSnapshot() -> EditorSelectionSnapshot? {
        guard let selectionMoveConfiguration,
              let selectedRange = selectionRangeSnapshot()
        else { return nil }
        let sourceText = string
        synchronizeInlineFormatIndex(with: sourceText)
        let range = atomicInlineDeletionRange(for: selectedRange)
        return EditorSelectionSnapshot(
            document: selectionMoveConfiguration.sourceDocument,
            destinationDocument: selectionMoveConfiguration.destinationDocument,
            selectionStableKey: selectionMoveConfiguration.selectionStableKey,
            sourceText: sourceText,
            range: range,
            selectedText: (sourceText as NSString).substring(with: range)
        )
    }

    func moveCurrentSelection() {
        guard isEditable,
              !hasMarkedText(),
              let selectionMoveConfiguration,
              selectionMoveConfiguration.isEnabled,
              let snapshot = currentSelectionMoveSnapshot()
        else { return }
        let action = selectionMoveConfiguration.action
        dismissSelectionMovePill()
        action(snapshot)
    }

    var visibleSelectionToolbar: NSView? {
        selectionToolbarView
    }

    var visibleSelectionToolbarBoldButton: NSButton? {
        selectionToolbarView?.boldButton
    }

    var visibleSelectionToolbarHighlightButton: NSButton? {
        selectionToolbarView?.highlightButton
    }

    var visibleSelectionToolbarMoveButton: NSButton? {
        selectionToolbarView?.moveButton.isHidden == false
            ? selectionToolbarView?.moveButton
            : nil
    }

    // Compatibility for callers that previously addressed the sole move pill.
    var visibleSelectionMovePill: NSButton? {
        visibleSelectionToolbarMoveButton
    }

    func updateSelectionToolbarStyle(
        backgroundColor: NSColor,
        foregroundColor: NSColor,
        accentColor: NSColor,
        hoverColor _: NSColor,
        selectionColor _: NSColor,
        borderColor: NSColor
    ) {
        selectionToolbarBackgroundColor = backgroundColor
        selectionToolbarForegroundColor = foregroundColor
        selectionToolbarAccentColor = accentColor
        selectionToolbarBorderColor = borderColor
        applySelectionToolbarStyle()
    }

    func selectionDidChangeForMovePill() {
        if !isAdjustingInlineKeyboardSelection, !hasMarkedText() {
            inlineKeyboardSelectionAnchor = nil
            inlineKeyboardSelectionActiveLocation = nil
        }
        dismissSelectionMovePill()
        guard !isHandlingMouseSelection else { return }
        scheduleSelectionMovePillPresentation()
    }

    func dismissSelectionMovePill() {
        selectionMovePresentationGeneration &+= 1
        selectionMovePresentationWorkItem?.cancel()
        selectionMovePresentationWorkItem = nil
        displayedSelectionToolbarSnapshot = nil
        selectionToolbarView?.removeFromSuperview()
        selectionToolbarView = nil
    }

    /// Recreates only the transient selection toolbar so its AppKit-owned
    /// labels and accessibility strings adopt the current app language.
    /// Editor text, selection, first-responder state, and undo history remain
    /// untouched.
    func rebuildVisibleSelectionToolbarForLanguageChange() {
        guard let snapshot = displayedSelectionToolbarSnapshot else { return }
        dismissSelectionMovePill()
        guard eligibleSelectionToolbarSnapshot() == snapshot else { return }
        presentSelectionToolbar(for: snapshot)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowDidResignKeyObserver {
            NotificationCenter.default.removeObserver(windowDidResignKeyObserver)
            self.windowDidResignKeyObserver = nil
        }
        dismissSelectionMovePill()
        guard let window else { return }
        windowDidResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.dismissSelectionMovePill()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySelectionToolbarStyle()
        guard let toolbar = selectionToolbarView else { return }
        // AppKit reapplies view-backed layer defaults after the appearance
        // callback. Restyle once on the next turn so the intended shadow is
        // not reset to zero while the already-visible toolbar changes theme.
        DispatchQueue.main.async { [weak self, weak toolbar] in
            guard let self,
                  let toolbar,
                  self.selectionToolbarView === toolbar
            else { return }
            self.applySelectionToolbarStyle(to: toolbar)
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            dismissSelectionMovePill()
        }
        return didResign
    }

    override func cancelOperation(_ sender: Any?) {
        let consumedSelectionMovePresentation = selectionMovePresentationWorkItem != nil
            || selectionToolbarView != nil
        dismissSelectionMovePill()
        if !consumedSelectionMovePresentation {
            super.cancelOperation(sender)
        }
    }

    private func scheduleSelectionMovePillPresentation() {
        guard let snapshot = eligibleSelectionToolbarSnapshot() else { return }
        selectionMovePresentationGeneration &+= 1
        let generation = selectionMovePresentationGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.selectionMovePresentationGeneration == generation
            else { return }
            self.selectionMovePresentationWorkItem = nil
            self.presentSelectionToolbar(for: snapshot)
        }
        selectionMovePresentationWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0, selectionMovePresentationDelay),
            execute: workItem
        )
    }

    private func presentSelectionToolbar(for snapshot: SelectionToolbarSnapshot) {
        guard eligibleSelectionToolbarSnapshot() == snapshot,
              let anchorRect = selectionMoveAnchorRect(for: snapshot.range)
        else { return }

        let toolbar = SelectionToolbarView(frame: .zero)
        toolbar.boldButton.target = self
        toolbar.boldButton.action = #selector(performSelectionBold(_:))
        toolbar.highlightButton.target = self
        toolbar.highlightButton.action = #selector(performSelectionHighlight(_:))
        toolbar.moveButton.target = self
        toolbar.moveButton.action = #selector(performSelectionMovePill(_:))
        let configuration = selectionMoveConfiguration
        toolbar.updateMoveAction(
            title: configuration.map(selectionMovePillTitle(for:)),
            isEnabled: configuration?.isEnabled == true,
            toolTip: selectionMoveToolTip(for: configuration)
        )
        let formatStates = selectionToolbarFormatStates(for: snapshot)
        toolbar.updateFormatStates(
            bold: formatStates.boldActive,
            boldEnabled: formatStates.boldEnabled,
            highlight: formatStates.highlightActive,
            highlightEnabled: formatStates.highlightEnabled
        )
        applySelectionToolbarStyle(to: toolbar)

        let availableRect = visibleRect.insetBy(dx: 8, dy: 8)
        guard availableRect.width >= 64 else { return }
        let toolbarSize = NSSize(
            width: min(toolbar.preferredSize.width, availableRect.width),
            height: SelectionToolbarView.height
        )
        guard let toolbarFrame = selectionMovePillFrame(
            anchorRect: anchorRect,
            buttonSize: toolbarSize,
            availableRect: availableRect
        ) else { return }

        toolbar.frame = toolbarFrame
        displayedSelectionToolbarSnapshot = snapshot
        selectionToolbarView = toolbar
        addSubview(toolbar, positioned: .above, relativeTo: nil)
        // AppKit can replace a view-backed layer while attaching the toolbar,
        // which otherwise drops the light-appearance shadow configuration.
        applySelectionToolbarStyle(to: toolbar)
    }

    private func eligibleSelectionToolbarSnapshot() -> SelectionToolbarSnapshot? {
        guard isEditable,
              !hasMarkedText(),
              !isHandlingMouseSelection,
              window?.isKeyWindow == true,
              window?.firstResponder === self,
              let range = selectionRangeSnapshot()
        else { return nil }
        return SelectionToolbarSnapshot(sourceText: string, range: range)
    }

    private func selectionMoveAnchorRect(for characterRange: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        layoutManager.ensureLayout(forCharacterRange: characterRange)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        guard glyphRange.length > 0 else { return nil }

        let origin = textContainerOrigin
        let viewport = visibleRect
        var visibleSelectionRects: [NSRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: glyphRange,
            in: textContainer
        ) { rect, _ in
            let textViewRect = rect.offsetBy(dx: origin.x, dy: origin.y)
            if textViewRect.width > 0,
               textViewRect.height > 0,
               textViewRect.intersects(viewport)
            {
                visibleSelectionRects.append(textViewRect)
            }
        }
        if let lastVisibleRect = visibleSelectionRects.last {
            return lastVisibleRect
        }

        let lastGlyphRange = NSRange(
            location: NSMaxRange(glyphRange) - 1,
            length: 1
        )
        let fallbackRect = layoutManager.boundingRect(
            forGlyphRange: lastGlyphRange,
            in: textContainer
        ).offsetBy(dx: origin.x, dy: origin.y)
        guard fallbackRect.width > 0,
              fallbackRect.height > 0,
              fallbackRect.intersects(viewport)
        else { return nil }
        return fallbackRect
    }

    private func selectionMovePillFrame(
        anchorRect: NSRect,
        buttonSize: NSSize,
        availableRect: NSRect
    ) -> NSRect? {
        guard availableRect.width >= buttonSize.width,
              availableRect.height >= buttonSize.height
        else { return nil }

        let gap: CGFloat = 6
        let x = min(
            max(anchorRect.midX - buttonSize.width / 2, availableRect.minX),
            availableRect.maxX - buttonSize.width
        )
        let aboveY = anchorRect.minY - gap - buttonSize.height
        let belowY = anchorRect.maxY + gap
        let y: CGFloat
        if aboveY >= availableRect.minY {
            y = aboveY
        } else if belowY + buttonSize.height <= availableRect.maxY {
            y = belowY
        } else {
            y = min(
                max(anchorRect.midY - buttonSize.height / 2, availableRect.minY),
                availableRect.maxY - buttonSize.height
            )
        }
        return NSRect(origin: NSPoint(x: x, y: y), size: buttonSize)
    }

    private func selectionMovePillTitle(
        for configuration: EditorSelectionMoveConfiguration
    ) -> String {
        configuration.title
    }

    private func selectionMoveToolTip(
        for configuration: EditorSelectionMoveConfiguration?
    ) -> String? {
        guard let configuration else { return nil }
        if configuration.isEnabled {
            return configuration.title
        }
        return configuration.disabledReason ?? configuration.title
    }

    private func refreshSelectionMovePillLabel() {
        guard let toolbar = selectionToolbarView else { return }
        let configuration = selectionMoveConfiguration
        toolbar.updateMoveAction(
            title: configuration.map(selectionMovePillTitle(for:)),
            isEnabled: configuration?.isEnabled == true,
            toolTip: selectionMoveToolTip(for: configuration)
        )
        if let snapshot = displayedSelectionToolbarSnapshot {
            let formatStates = selectionToolbarFormatStates(for: snapshot)
            toolbar.updateFormatStates(
                bold: formatStates.boldActive,
                boldEnabled: formatStates.boldEnabled,
                highlight: formatStates.highlightActive,
                highlightEnabled: formatStates.highlightEnabled
            )
        }
        applySelectionToolbarStyle(to: toolbar)
    }

    private func applySelectionToolbarStyle() {
        guard let toolbar = selectionToolbarView else { return }
        applySelectionToolbarStyle(to: toolbar)
    }

    private func applySelectionToolbarStyle(to toolbar: SelectionToolbarView) {
        let appearance = effectiveAppearance
        let editorSurface = Self.resolvedToolbarColor(
            backgroundColor,
            appearance: appearance
        )
        let toolbarSurface = Self.opaqueToolbarColor(
            selectionToolbarBackgroundColor,
            over: editorSurface,
            appearance: appearance
        )
        let toolbarBorder = Self.opaqueToolbarColor(
            selectionToolbarBorderColor,
            over: toolbarSurface,
            appearance: appearance
        )
        toolbar.applyStyle(
            backgroundColor: toolbarSurface,
            foregroundColor: Self.resolvedToolbarColor(
                selectionToolbarForegroundColor,
                appearance: appearance
            ),
            accentColor: Self.resolvedToolbarColor(
                selectionToolbarAccentColor,
                appearance: appearance
            ),
            borderColor: toolbarBorder
        )
    }

    private static func resolvedToolbarColor(
        _ color: NSColor,
        appearance: NSAppearance
    ) -> NSColor {
        var resolvedColor: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.deviceRGB)
        }
        return resolvedColor ?? color.usingColorSpace(.deviceRGB) ?? color
    }

    private static func opaqueToolbarColor(
        _ foregroundColor: NSColor,
        over backgroundColor: NSColor,
        appearance: NSAppearance
    ) -> NSColor {
        let foreground = resolvedToolbarColor(
            foregroundColor,
            appearance: appearance
        )
        let background = resolvedToolbarColor(
            backgroundColor,
            appearance: appearance
        )
        guard let foregroundRGB = foreground.usingColorSpace(.deviceRGB),
              let backgroundRGB = background.usingColorSpace(.deviceRGB)
        else {
            return foreground.withAlphaComponent(1)
        }

        let foregroundAlpha = min(max(foregroundRGB.alphaComponent, 0), 1)
        let inverseAlpha = 1 - foregroundAlpha
        return NSColor(
            deviceRed: foregroundRGB.redComponent * foregroundAlpha
                + backgroundRGB.redComponent * inverseAlpha,
            green: foregroundRGB.greenComponent * foregroundAlpha
                + backgroundRGB.greenComponent * inverseAlpha,
            blue: foregroundRGB.blueComponent * foregroundAlpha
                + backgroundRGB.blueComponent * inverseAlpha,
            alpha: 1
        )
    }

    @objc private func performSelectionMovePill(_ sender: NSButton) {
        guard sender === selectionToolbarView?.moveButton,
              let toolbarSnapshot = displayedSelectionToolbarSnapshot,
              eligibleSelectionToolbarSnapshot() == toolbarSnapshot,
              let configuration = selectionMoveConfiguration,
              configuration.isEnabled,
              let snapshot = currentSelectionMoveSnapshot(),
              snapshot.sourceText == toolbarSnapshot.sourceText
        else {
            dismissSelectionMovePill()
            return
        }
        let action = configuration.action
        dismissSelectionMovePill()
        action(snapshot)
    }

    @objc private func performSelectionBold(_ sender: NSButton) {
        performSelectionFormat(sender, format: .bold)
    }

    @objc private func performSelectionHighlight(_ sender: NSButton) {
        performSelectionFormat(sender, format: .highlight)
    }

    private func performSelectionFormat(
        _ sender: NSButton,
        format: MarkdownInlineFormat
    ) {
        let expectedButton = format == .highlight
            ? selectionToolbarView?.highlightButton
            : selectionToolbarView?.boldButton
        guard sender === expectedButton,
              let snapshot = displayedSelectionToolbarSnapshot,
              eligibleSelectionToolbarSnapshot() == snapshot
        else {
            dismissSelectionMovePill()
            return
        }
        toggleInlineFormat(format)
    }

    // Core owns Markdown parsing and edit planning. These two small adapter
    // points intentionally contain no duplicate delimiter parser.
    private func selectionToolbarFormatStates(
        for snapshot: SelectionToolbarSnapshot
    ) -> (
        boldActive: Bool,
        boldEnabled: Bool,
        highlightActive: Bool,
        highlightEnabled: Bool
    ) {
        let boldState = MarkdownInlineFormat.bold.selectionState(
            in: snapshot.sourceText,
            selection: snapshot.range
        )
        let highlightState = MarkdownInlineFormat.highlight.selectionState(
            in: snapshot.sourceText,
            selection: snapshot.range
        )
        return (
            boldActive: boldState == .active,
            boldEnabled: boldState != .unavailable,
            highlightActive: highlightState == .active,
            highlightEnabled: highlightState != .unavailable
        )
    }

    func toggleInlineFormat(_ format: MarkdownInlineFormat) {
        guard isEditable,
              !hasMarkedText(),
              let range = selectionRangeSnapshot()
        else {
            dismissSelectionMovePill()
            return
        }
        let snapshot = SelectionToolbarSnapshot(sourceText: string, range: range)
        guard let plan = format.togglePlan(
            in: snapshot.sourceText,
            selection: snapshot.range
        ) else {
            refreshSelectionMovePillLabel()
            return
        }

        apply(plan)

        // Applying the Markdown edit causes native selection notifications to
        // dismiss and debounce the toolbar. Recreate it immediately with the
        // new UTF-16 range so formatting feels like a stable toggle surface.
        dismissSelectionMovePill()
        if let updatedSnapshot = eligibleSelectionToolbarSnapshot() {
            presentSelectionToolbar(for: updatedSnapshot)
        }
    }

    func canToggleInlineFormat(_ format: MarkdownInlineFormat) -> Bool {
        guard isEditable,
              !hasMarkedText(),
              let range = selectionRangeSnapshot()
        else { return false }
        return format.selectionState(in: string, selection: range) != .unavailable
    }

    var selectionIsEntirelyTodo: Bool {
        let starts = selectedLogicalLineStarts()
        guard !starts.isEmpty else { return false }
        let source = string as NSString
        let todoStarts = Set(checklistMatches.map(\.lineRange.location))
        let selection = selectedRange()
        let ignoresBlankLines = starts.count > 1 || selection.length > 0
        let candidateStarts = starts.filter { start in
            if todoStarts.contains(start) { return true }
            guard ignoresBlankLines else { return true }

            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            source.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: start, length: 0)
            )
            let contents = source.substring(
                with: NSRange(location: lineStart, length: contentsEnd - lineStart)
            )
            return !contents.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !candidateStarts.isEmpty else { return false }
        return candidateStarts.allSatisfy { todoStarts.contains($0) }
    }

    func installChecklistTextStorageDelegate() {
        guard let textStorage else { return }
        if let existingDelegate = textStorage.delegate,
           existingDelegate !== self
        {
            assertionFailure("CheckboxTextView requires the NSTextStorage delegate")
            return
        }
        textStorage.delegate = self
        synchronizeChecklistGlyphIndex(with: textStorage.string)
        synchronizeInlineFormatIndex(with: textStorage.string)
        synchronizeManagedImageMatches(with: textStorage.string)
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters),
              !isApplyingChecklistPresentation
        else { return }

        // NSTextStorage calls its delegate after the final string is ready but
        // before notifying NSLayoutManager. Updating only the in-memory prefix
        // index here prevents TextKit from ever generating a frame with stale
        // checkbox offsets during IME composition.
        synchronizeChecklistGlyphIndex(with: textStorage.string)
        let inlineFormatsChanged = synchronizeInlineFormatIndex(
            with: textStorage.string
        )
        synchronizeManagedImageMatches(with: textStorage.string)

        // The delegate is invoked after NSTextStorage has its final UTF-16
        // string and before layout consumes the edit. Refreshing and
        // invalidating the delimiter index here is what keeps IME edits from
        // ever drawing against stale Markdown ranges.
        if inlineFormatsChanged {
            let synchronizedText = textStorage.string
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.string == synchronizedText,
                      let layoutManager = self.layoutManager
                else { return }
                let fullRange = NSRange(
                    location: 0,
                    length: (synchronizedText as NSString).length
                )
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
                self.needsDisplay = true
            }
        }
    }

    func updateChecklistStyle(
        fontSize: CGFloat,
        completedTextColor: NSColor,
        successColor: NSColor,
        checkmarkColor: NSColor,
        accentColor: NSColor,
        hoverBackgroundColor: NSColor
    ) {
        let changed = checklistFontSize != fontSize
            || !self.completedTextColor.isEqual(completedTextColor)
            || !self.successColor.isEqual(successColor)
            || !self.checkmarkColor.isEqual(checkmarkColor)
            || !self.accentColor.isEqual(accentColor)
            || !self.hoverBackgroundColor.isEqual(hoverBackgroundColor)
        checklistFontSize = fontSize
        self.completedTextColor = completedTextColor
        self.successColor = successColor
        self.checkmarkColor = checkmarkColor
        self.accentColor = accentColor
        self.hoverBackgroundColor = hoverBackgroundColor
        if changed {
            presentationStyleRevision += 1
        }
    }

    @discardableResult
    func updateBaseFontSizeIfNeeded(_ fontSize: CGFloat) -> Bool {
        guard checklistFontSize != fontSize else { return false }
        font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        return true
    }

    func refreshChecklistPresentation(forceLayout: Bool = false) {
        guard !isApplyingChecklistPresentation,
              let layoutManager,
              let textStorage
        else { return }
        let currentText = string
        guard !hasMarkedText() else {
            refreshChecklistGlyphIndexDuringMarkedText(
                currentText: currentText,
                layoutManager: layoutManager
            )
            hasPendingChecklistPresentationRefresh = true
            return
        }

        let newMatches = MarkdownChecklist.checkboxMatches(in: currentText)
        let matchesChanged = newMatches != checklistMatches
        let newManagedImageMatches = imageConfiguration == nil
            ? []
            : MarkdownImage.matches(in: currentText)
        let managedImagesChanged = newManagedImageMatches != managedImageMatches
        let newInlineFormatMatches = MarkdownInlineFormat.matches(in: currentText)
        let inlineFormatsChanged = newInlineFormatMatches != inlineFormatMatches
        let glyphMetricsChanged = appliedGlyphFontSize != checklistFontSize
        let textChanged = appliedPresentationText != currentText
        guard forceLayout
                || matchesChanged
                || managedImagesChanged
                || inlineFormatsChanged
                || glyphMetricsChanged
                || textChanged
                || appliedPresentationStyleRevision != presentationStyleRevision
        else { return }

        let fullRange = NSRange(location: 0, length: (currentText as NSString).length)
        let selectedRanges = self.selectedRanges
        let selectionAffinity = self.selectionAffinity
        let scrollView = enclosingScrollView
        let scrollOrigin = scrollView?.contentView.bounds.origin
        let undoManager = self.undoManager
        let shouldRestoreUndoRegistration = undoManager?.isUndoRegistrationEnabled == true
        let needsParagraphLayout = forceLayout
            || matchesChanged
            || glyphMetricsChanged
            || textChanged

        isApplyingChecklistPresentation = true
        hasPendingChecklistPresentationRefresh = false
        if shouldRestoreUndoRegistration {
            undoManager?.disableUndoRegistration()
        }
        defer {
            if shouldRestoreUndoRegistration {
                undoManager?.enableUndoRegistration()
            }
            if self.selectedRanges != selectedRanges {
                setSelectedRanges(
                    selectedRanges,
                    affinity: selectionAffinity,
                    stillSelecting: false
                )
            }
            if let scrollView, let scrollOrigin {
                scrollView.contentView.scroll(to: scrollOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            isApplyingChecklistPresentation = false
            assert(string == currentText, "Checklist presentation must not mutate Markdown text")
        }

        updateChecklistGlyphIndex(matches: newMatches, sourceText: currentText)
        updateInlineFormatIndex(
            matches: newInlineFormatMatches,
            sourceText: currentText
        )
        updateManagedImageMatches(newManagedImageMatches)
        resolveManagedImageAssets()
        if needsParagraphLayout {
            applyChecklistParagraphStyles(
                matches: newMatches,
                source: currentText as NSString,
                textStorage: textStorage,
                layoutManager: layoutManager,
                fullRange: fullRange
            )
        }

        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.strikethroughColor, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.font, forCharacterRange: fullRange)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)

        for match in newMatches {
            if match.isChecked, match.contentRange.length > 0 {
                layoutManager.addTemporaryAttributes(
                    [
                        .foregroundColor: completedTextColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: completedTextColor
                    ],
                    forCharacterRange: match.contentRange
                )
            }
        }

        // NSLayoutManager temporary font attributes do not participate in the
        // custom glyph-generation callback above. Put presentation fonts on
        // NSTextStorage instead: this changes no Markdown characters and is
        // performed with undo registration disabled, but gives TextKit the
        // actual Regular/Bold font when it creates glyphs.
        let regularFont = NSFont.monospacedSystemFont(
            ofSize: checklistFontSize,
            weight: .regular
        )
        let boldFont = NSFont.monospacedSystemFont(
            ofSize: checklistFontSize,
            weight: .bold
        )
        let newBoldRanges = newInlineFormatMatches.compactMap { match in
            match.format == .bold && match.contentRange.length > 0
                ? match.contentRange
                : nil
        }
        let fontBaselineChanged = appliedStorageFontSize != checklistFontSize
        let rangesToRestore: [NSRange]
        if fontBaselineChanged
            || appliedBoldFontRanges.count != newBoldRanges.count
        {
            rangesToRestore = fullRange.length > 0 ? [fullRange] : []
        } else {
            rangesToRestore = appliedBoldFontRanges.compactMap { range in
                guard range.location < fullRange.length else { return nil }
                return NSRange(
                    location: range.location,
                    length: min(range.length, fullRange.length - range.location)
                )
            }
        }
        if !rangesToRestore.isEmpty || !newBoldRanges.isEmpty {
            textStorage.beginEditing()
            for range in rangesToRestore where range.length > 0 {
                textStorage.addAttribute(.font, value: regularFont, range: range)
            }
            for range in newBoldRanges {
                textStorage.addAttribute(.font, value: boldFont, range: range)
            }
            textStorage.endEditing()
        }
        appliedStorageFontSize = checklistFontSize
        appliedBoldFontRanges = newBoldRanges
        typingAttributes[.font] = regularFont
        appliedPresentationText = currentText
        appliedPresentationStyleRevision = presentationStyleRevision
        appliedGlyphFontSize = checklistFontSize
        layoutManager.invalidateDisplay(forCharacterRange: fullRange)
        if let textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func refreshChecklistGlyphIndexDuringMarkedText(
        currentText: String,
        layoutManager: NSLayoutManager
    ) {
        let matchesChanged = synchronizeChecklistGlyphIndex(
            with: currentText
        )
        let inlineFormatsChanged = synchronizeInlineFormatIndex(with: currentText)
        let managedImagesChanged = synchronizeManagedImageMatches(with: currentText)
        guard matchesChanged || inlineFormatsChanged || managedImagesChanged else { return }

        let source = currentText as NSString
        let sourceLength = source.length
        guard sourceLength > 0 else {
            needsDisplay = true
            return
        }

        let currentMarkedRange = markedRange()
        let markedLocation = currentMarkedRange.location == NSNotFound
            ? 0
            : min(currentMarkedRange.location, sourceLength - 1)
        let invalidationRange = source.lineRange(
            for: NSRange(location: markedLocation, length: 0)
        )
        let suffixRange = NSRange(
            location: invalidationRange.location,
            length: sourceLength - invalidationRange.location
        )
        layoutManager.invalidateGlyphs(
            forCharacterRange: suffixRange,
            changeInLength: 0,
            actualCharacterRange: nil
        )
        layoutManager.invalidateLayout(
            forCharacterRange: suffixRange,
            actualCharacterRange: nil
        )
        layoutManager.invalidateDisplay(forCharacterRange: suffixRange)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    @discardableResult
    private func synchronizeChecklistGlyphIndex(with currentText: String) -> Bool {
        guard checklistGlyphIndexSourceText != currentText else { return false }
        return updateChecklistGlyphIndex(
            matches: MarkdownChecklist.checkboxMatches(in: currentText),
            sourceText: currentText
        )
    }

    @discardableResult
    private func updateChecklistGlyphIndex(
        matches: [MarkdownCheckboxMatch],
        sourceText: String
    ) -> Bool {
        checklistGlyphIndexSourceText = sourceText
        guard matches != checklistMatches else { return false }
        checklistMatches = matches
        return true
    }

    @discardableResult
    private func synchronizeInlineFormatIndex(with currentText: String) -> Bool {
        guard inlineFormatIndexSourceText != currentText else { return false }
        return updateInlineFormatIndex(
            matches: MarkdownInlineFormat.matches(in: currentText),
            sourceText: currentText
        )
    }

    @discardableResult
    private func updateInlineFormatIndex(
        matches: [MarkdownInlineFormatMatch],
        sourceText: String
    ) -> Bool {
        inlineFormatIndexSourceText = sourceText
        guard matches != inlineFormatMatches else { return false }
        inlineFormatMatches = matches
        inlineFormatDelimiterRanges = matches
            .flatMap { [$0.openingDelimiterRange, $0.closingDelimiterRange] }
            .sorted {
                if $0.location == $1.location { return $0.length < $1.length }
                return $0.location < $1.location
            }
        var offsets = Set<Int>()
        for range in inlineFormatDelimiterRanges {
            guard range.location >= 0, range.length > 0 else { continue }
            for offset in range.location..<NSMaxRange(range) {
                offsets.insert(offset)
            }
        }
        inlineFormatDelimiterOffsets = offsets
        return true
    }

    @discardableResult
    private func synchronizeManagedImageMatches(with currentText: String) -> Bool {
        let matches = imageConfiguration == nil ? [] : MarkdownImage.matches(in: currentText)
        guard matches != managedImageMatches else { return false }
        updateManagedImageMatches(matches)
        return true
    }

    private func updateManagedImageMatches(_ matches: [MarkdownImageMatch]) {
        managedImageMatches = matches
        managedImageRanges = matches.map(\.tokenRange)
        managedImageStartOffsets = Set(matches.map(\.tokenRange.location))
    }

    private func resolveManagedImageAssets() {
        guard let imageConfiguration else {
            managedImageURLsByDestination.removeAll()
            return
        }

        var resolved: [String: URL] = [:]
        for match in managedImageMatches {
            if let fileURL = imageConfiguration.store.resolveManagedAsset(
                markdownDestination: match.markdownDestination,
                relativeTo: imageConfiguration.documentIdentity.fileURL
            ) {
                resolved[match.markdownDestination] = fileURL
            }
        }
        managedImageURLsByDestination = resolved
    }

    private func requestManagedImagePreviewIfNeeded(
        _ fileURL: URL,
        documentIdentity: MarkdownEditorDocumentIdentity
    ) {
        guard let store = imageConfiguration?.store,
              managedImagePreviews[fileURL] == nil,
              !requestedManagedImageURLs.contains(fileURL),
              !failedManagedImageURLs.contains(fileURL)
        else { return }

        requestedManagedImageURLs.insert(fileURL)
        let generation = managedImageLoadGeneration
        imagePreviewQueue.async { [weak self] in
            let data = try? store.loadValidatedManagedAssetData(at: fileURL)
            let decodedPreview = data.flatMap(Self.loadManagedImagePreview(data:))
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.managedImageLoadGeneration == generation,
                      self.imageConfiguration?.documentIdentity == documentIdentity,
                      self.imageConfiguration?.store === store
                else { return }
                self.requestedManagedImageURLs.remove(fileURL)
                guard self.managedImageURLsByDestination.values.contains(fileURL)
                else { return }
                if let decodedPreview {
                    let cgImage = decodedPreview.image
                    self.managedImagePixelSizes[fileURL] = NSSize(
                        width: cgImage.width,
                        height: cgImage.height
                    )
                    if self.managedImagePreviews.count >= 64,
                       let oldestURL = self.managedImagePreviews.keys.first,
                       oldestURL != fileURL {
                        self.managedImagePreviews.removeValue(forKey: oldestURL)
                    }
                    self.managedImagePreviews[fileURL] = ManagedImagePreview(
                        image: NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height)
                        ),
                        pixelWidth: cgImage.width,
                        pixelHeight: cgImage.height
                    )
                } else {
                    self.failedManagedImageURLs.insert(fileURL)
                }
                self.invalidateManagedImageLayout(for: fileURL)
            }
        }
    }

    private static func loadManagedImagePreview(
        data: Data
    ) -> DecodedManagedImagePreview? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_024,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }
        return DecodedManagedImagePreview(image: cgImage)
    }

    private func invalidateManagedImageLayout(for fileURL: URL) {
        guard let layoutManager else { return }
        for match in managedImageMatches
        where managedImageURLsByDestination[match.markdownDestination] == fileURL {
            layoutManager.invalidateGlyphs(
                forCharacterRange: match.tokenRange,
                changeInLength: 0,
                actualCharacterRange: nil
            )
            layoutManager.invalidateLayout(
                forCharacterRange: match.lineRange,
                actualCharacterRange: nil
            )
            layoutManager.invalidateDisplay(forCharacterRange: match.lineRange)
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func cancelPendingImageImports() {
        imageImportGeneration &+= 1
        pendingImageImportCount = 0
    }

    func prepareForDocumentIdentityChange() {
        cancelPendingImageImports()
        imageBoundaryComposition = nil
        invalidateInlineFontBaseline()
        resetManagedImagePresentation()
    }

    fileprivate func invalidateInlineFontBaseline() {
        appliedStorageFontSize = -1
        appliedBoldFontRanges.removeAll()
    }

    private func resetManagedImagePresentation() {
        managedImageLoadGeneration &+= 1
        managedImageMatches.removeAll()
        managedImageRanges.removeAll()
        managedImageStartOffsets.removeAll()
        managedImageURLsByDestination.removeAll()
        managedImagePreviews.removeAll()
        managedImagePixelSizes.removeAll()
        requestedManagedImageURLs.removeAll()
        failedManagedImageURLs.removeAll()

        guard let layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
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
        needsDisplay = true
    }

    override func unmarkText() {
        let shouldRefreshPresentation = hasPendingChecklistPresentationRefresh
        let composition = imageBoundaryComposition
        let caretBeforeSuffix: Int?
        if let composition, !composition.suffix.isEmpty {
            let range = markedRange()
            let suffixLength = (composition.suffix as NSString).length
            caretBeforeSuffix = range.location == NSNotFound
                ? nil
                : NSMaxRange(range) - suffixLength
        } else {
            caretBeforeSuffix = nil
        }
        super.unmarkText()
        imageBoundaryComposition = nil
        if let caretBeforeSuffix {
            setSafeCollapsedSelection(at: caretBeforeSuffix)
        }
        if shouldRefreshPresentation,
           hasPendingChecklistPresentationRefresh,
           !hasMarkedText()
        {
            refreshChecklistPresentation(forceLayout: true)
        }
        if !hasMarkedText() {
            editorController?.notifyTextCompositionDidEnd()
        }
    }

    private func applyChecklistParagraphStyles(
        matches: [MarkdownCheckboxMatch],
        source: NSString,
        textStorage: NSTextStorage,
        layoutManager: NSLayoutManager,
        fullRange: NSRange
    ) {
        let baseStyle = (defaultParagraphStyle ?? NSParagraphStyle.default)
            .mutableCopy() as! NSMutableParagraphStyle
        let paragraphFont = font ?? NSFont.monospacedSystemFont(
            ofSize: checklistFontSize,
            weight: .regular
        )
        var indentationWidths: [String: CGFloat] = [:]

        let paragraphStyles: [(range: NSRange, style: NSParagraphStyle)] = matches.compactMap {
            match in
            let indentationRange = NSRange(
                location: match.lineRange.location,
                length: match.prefixRange.location - match.lineRange.location
            )
            let indentation = source.substring(with: indentationRange)
            let indentationWidth: CGFloat
            if let cachedWidth = indentationWidths[indentation] {
                indentationWidth = cachedWidth
            } else {
                let measuredWidth = source.substring(with: indentationRange)
                    .size(
                        withAttributes: [
                            .font: paragraphFont,
                            .paragraphStyle: baseStyle
                        ]
                    ).width
                indentationWidths[indentation] = measuredWidth
                indentationWidth = measuredWidth
            }
            let hangingStyle = baseStyle.mutableCopy() as! NSMutableParagraphStyle
            hangingStyle.firstLineHeadIndent = 0
            hangingStyle.headIndent = indentationWidth + checklistPrefixDisplayWidth
            return (
                source.lineRange(for: match.lineRange),
                hangingStyle.copy() as! NSParagraphStyle
            )
        }

        textStorage.beginEditing()
        if fullRange.length > 0 {
            textStorage.addAttribute(
                .paragraphStyle,
                value: baseStyle,
                range: fullRange
            )
        }
        for paragraphStyle in paragraphStyles {
            textStorage.addAttribute(
                .paragraphStyle,
                value: paragraphStyle.style,
                range: paragraphStyle.range
            )
        }
        textStorage.endEditing()
        layoutManager.invalidateGlyphs(
            forCharacterRange: fullRange,
            changeInLength: 0,
            actualCharacterRange: nil
        )
        layoutManager.invalidateLayout(
            forCharacterRange: fullRange,
            actualCharacterRange: nil
        )
    }

    fileprivate func checklistPrefixRange(
        containingUTF16Offset offset: Int
    ) -> NSRange? {
        var lowerBound = 0
        var upperBound = checklistPrefixRanges.count
        while lowerBound < upperBound {
            let index = lowerBound + (upperBound - lowerBound) / 2
            let range = checklistPrefixRanges[index]
            if offset < range.location {
                upperBound = index
            } else if offset >= NSMaxRange(range) {
                lowerBound = index + 1
            } else {
                return range
            }
        }
        return nil
    }

    fileprivate func managedImageRange(
        containingUTF16Offset offset: Int
    ) -> NSRange? {
        var lowerBound = 0
        var upperBound = managedImageRanges.count
        while lowerBound < upperBound {
            let index = lowerBound + (upperBound - lowerBound) / 2
            let range = managedImageRanges[index]
            if offset < range.location {
                upperBound = index
            } else if offset >= NSMaxRange(range) {
                lowerBound = index + 1
            } else {
                return range
            }
        }
        return nil
    }

    fileprivate func isChecklistPrefixStart(atUTF16Offset offset: Int) -> Bool {
        checklistPrefixStartOffsets.contains(offset)
    }

    fileprivate func isInlineFormatDelimiter(atUTF16Offset offset: Int) -> Bool {
        inlineFormatDelimiterOffsets.contains(offset)
    }

    fileprivate func isManagedImageStart(atUTF16Offset offset: Int) -> Bool {
        managedImageStartOffsets.contains(offset)
    }

    fileprivate func managedImageLayoutSize(
        atUTF16Offset offset: Int,
        in textContainer: NSTextContainer
    ) -> NSSize {
        let availableWidth = max(
            96,
            textContainer.containerSize.width
                - 2 * textContainer.lineFragmentPadding
        )
        let maximumWidth = min(480, availableWidth)
        let decodedHeight: CGFloat? = managedImageMatches
            .first(where: { $0.tokenRange.location == offset })
            .flatMap { managedImageURLsByDestination[$0.markdownDestination] }
            .flatMap { managedImagePixelSizes[$0] }
            .flatMap { pixelSize in
                guard pixelSize.width > 0, pixelSize.height > 0 else {
                    return nil
                }
                return maximumWidth
                    * pixelSize.height
                    / pixelSize.width
            }
        let contentHeight = decodedHeight ?? maximumWidth * 9 / 16
        return NSSize(
            width: max(96, maximumWidth),
            height: max(1, contentHeight) + 12
        )
    }

    fileprivate var checklistPrefixDisplayWidth: CGFloat {
        min(max(checklistFontSize * 0.9, 14), 20) + 8
    }

    func toggleTodoFormat() {
        guard isEditable, !hasMarkedText(),
              let plan = MarkdownChecklist.toggleTodoFormat(
                  in: string,
                  selection: selectedRange()
              )
        else { return }
        apply(plan)
    }

    var currentTodoCycleState: MarkdownTodoCycleState? {
        MarkdownChecklist.todoCycleState(
            in: string,
            selection: selectedRange()
        )
    }

    func cycleTodoState() {
        guard isEditable, !hasMarkedText(),
              let plan = MarkdownChecklist.cycleTodoState(
                  in: string,
                  selection: selectedRange()
              )
        else { return }
        apply(plan)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        Self.uniquePasteboardTypes(super.readablePasteboardTypes + [.fileURL, .png, .tiff])
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        Self.uniquePasteboardTypes([.fileURL, .png, .tiff] + super.acceptableDragTypes)
    }

    override func paste(_ sender: Any?) {
        if pasteContents(from: .general) {
            return
        }
        super.paste(sender)
    }

    override func cut(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else {
            super.cut(sender)
            return
        }
        synchronizeInlineFormatIndex(with: string)
        let selection = selectedRange()
        guard selection.length > 0 else {
            super.cut(sender)
            return
        }
        let canonicalRange = atomicInlineDeletionRange(for: selection)
        if canonicalRange != selection {
            inlineKeyboardSelectionAnchor = nil
            inlineKeyboardSelectionActiveLocation = nil
            setSelectedRange(canonicalRange)
        }
        super.cut(sender)
    }

    @discardableResult
    func pasteContents(from pboard: NSPasteboard) -> Bool {
        if Self.shouldImportImagesForOrdinaryPaste(from: pboard) {
            return importImages(
                from: pboard,
                replacementRange: selectedRange(),
                requiresSelectionMatch: true
            )
        }
        if pboard.availableType(from: [.png, .tiff]) != nil,
           pboard.string(forType: .string) != nil {
            return super.readSelection(from: pboard, type: .string)
        }
        return false
    }

    override func readSelection(
        from pboard: NSPasteboard,
        type: NSPasteboard.PasteboardType
    ) -> Bool {
        let explicitlyRequestedImageType = type == .fileURL || type == .png || type == .tiff
        if explicitlyRequestedImageType, importImages(
            from: pboard,
            replacementRange: selectedRange(),
            requiresSelectionMatch: true
        ) {
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.hasImageRepresentation(sender.draggingPasteboard) else {
            return super.draggingEntered(sender)
        }
        return canBeginImageImport ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.hasImageRepresentation(sender.draggingPasteboard) else {
            return super.draggingUpdated(sender)
        }
        return canBeginImageImport ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        guard Self.hasImageRepresentation(pboard) else {
            return super.performDragOperation(sender)
        }
        guard canBeginImageImport else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        let sourceLength = (string as NSString).length
        let insertionLocation = min(characterIndexForInsertion(at: point), sourceLength)
        return importImages(
            from: pboard,
            replacementRange: NSRange(location: insertionLocation, length: 0),
            requiresSelectionMatch: false
        )
    }

    override func dragSelection(
        with event: NSEvent,
        offset mouseOffset: NSSize,
        slideBack: Bool
    ) -> Bool {
        if !hasMarkedText(), selectedRanges.count == 1 {
            synchronizeInlineFormatIndex(with: string)
            let selection = selectedRange()
            if selection.length > 0 {
                let canonicalRange = atomicInlineDeletionRange(for: selection)
                if canonicalRange != selection {
                    setSelectedRange(canonicalRange)
                }
            }
        }
        return super.dragSelection(
            with: event,
            offset: mouseOffset,
            slideBack: slideBack
        )
    }

    @discardableResult
    func importImages(
        from pboard: NSPasteboard,
        replacementRange: NSRange,
        requiresSelectionMatch: Bool
    ) -> Bool {
        guard Self.hasImageRepresentation(pboard) else { return false }
        guard canBeginImageImport, let imageConfiguration else {
            NSSound.beep()
            return true
        }

        let payloads: [EditorImagePayload]
        do {
            payloads = try Self.imagePayloads(from: pboard)
        } catch {
            imageConfiguration.reportError(
                error.localizedDescription.isEmpty
                    ? L10n.text(.editorImageImportErrorReadBatch)
                    : error.localizedDescription
            )
            return true
        }
        guard !payloads.isEmpty else { return false }

        let sourceText = string
        let sourceLength = (sourceText as NSString).length
        guard replacementRange.location != NSNotFound,
              replacementRange.location >= 0,
              replacementRange.length >= 0,
              replacementRange.location <= sourceLength,
              replacementRange.length <= sourceLength - replacementRange.location
        else {
            imageConfiguration.reportError(
                L10n.text(.editorImageImportErrorInvalidInsertionPoint)
            )
            return true
        }

        imageImportGeneration &+= 1
        let insertion = PendingImageInsertion(
            generation: imageImportGeneration,
            documentIdentity: imageConfiguration.documentIdentity,
            sourceText: sourceText,
            replacementRange: replacementRange,
            requiresSelectionMatch: requiresSelectionMatch
        )
        let store = imageConfiguration.store
        pendingImageImportCount = 1
        imageImportQueue.async { [weak self] in
            let result = Result<[PreparedNoteImage], Error> {
                var prepared: [PreparedNoteImage] = []
                prepared.reserveCapacity(payloads.count)
                var totalBytes = 0
                for payload in payloads {
                    let image: PreparedNoteImage
                    switch payload {
                    case let .fileURL(fileURL):
                        image = try store.prepareImage(at: fileURL)
                    case let .encoded(data):
                        image = try store.prepareImage(data: data)
                    }
                    let nextTotal = totalBytes.addingReportingOverflow(image.byteCount)
                    guard !nextTotal.overflow,
                          nextTotal.partialValue <= 50 * 1_024 * 1_024
                    else {
                        throw EditorImageImportError.batchTooLarge
                    }
                    totalBytes = nextTotal.partialValue
                    prepared.append(image)
                }
                guard !prepared.isEmpty else {
                    throw EditorImageImportError.batchTooLarge
                }
                return prepared
            }
            DispatchQueue.main.async { [weak self] in
                self?.completeImageImport(
                    result,
                    insertion: insertion,
                    store: store
                )
            }
        }
        return true
    }

    private var canBeginImageImport: Bool {
        isEditable
            && !hasMarkedText()
            && imageConfiguration?.isEnabled == true
            && pendingImageImportCount == 0
    }

    private func completeImageImport(
        _ result: Result<[PreparedNoteImage], Error>,
        insertion: PendingImageInsertion,
        store: NoteImageStore
    ) {
        guard imageImportGeneration == insertion.generation else { return }

        guard let imageConfiguration,
              imageConfiguration.documentIdentity == insertion.documentIdentity,
              imageConfiguration.store === store,
              imageConfiguration.isEnabled,
              isEditable,
              !hasMarkedText(),
              string == insertion.sourceText
        else {
            pendingImageImportCount = 0
            return
        }

        let sourceLength = (string as NSString).length
        let replacementRange = insertion.replacementRange
        guard replacementRange.location != NSNotFound,
              replacementRange.location >= 0,
              replacementRange.length >= 0,
              replacementRange.location <= sourceLength,
              replacementRange.length <= sourceLength - replacementRange.location,
              !insertion.requiresSelectionMatch || selectedRange() == replacementRange
        else {
            pendingImageImportCount = 0
            return
        }

        let prepared: [PreparedNoteImage]
        do {
            prepared = try result.get()
        } catch {
            pendingImageImportCount = 0
            imageConfiguration.reportError(
                error.localizedDescription.isEmpty
                    ? L10n.text(.editorImageImportErrorProcessBatch)
                    : error.localizedDescription
            )
            return
        }

        imageImportQueue.async { [weak self] in
            let commitResult = Result<[NoteImageAsset], Error> {
                try prepared.map(store.commit)
            }
            DispatchQueue.main.async { [weak self] in
                self?.finishImageImportCommit(
                    commitResult,
                    insertion: insertion,
                    store: store
                )
            }
        }
    }

    private func finishImageImportCommit(
        _ result: Result<[NoteImageAsset], Error>,
        insertion: PendingImageInsertion,
        store: NoteImageStore
    ) {
        guard imageImportGeneration == insertion.generation else { return }
        pendingImageImportCount = 0

        guard let imageConfiguration,
              imageConfiguration.documentIdentity == insertion.documentIdentity,
              imageConfiguration.store === store,
              imageConfiguration.isEnabled,
              isEditable,
              !hasMarkedText(),
              string == insertion.sourceText
        else { return }

        let sourceLength = (string as NSString).length
        let replacementRange = insertion.replacementRange
        guard replacementRange.location != NSNotFound,
              replacementRange.location >= 0,
              replacementRange.length >= 0,
              replacementRange.location <= sourceLength,
              replacementRange.length <= sourceLength - replacementRange.location,
              !insertion.requiresSelectionMatch || selectedRange() == replacementRange
        else { return }

        let assets: [NoteImageAsset]
        do {
            assets = try result.get()
        } catch {
            imageConfiguration.reportError(
                error.localizedDescription.isEmpty
                    ? L10n.text(.editorImageImportErrorSaveBatch)
                    : error.localizedDescription
            )
            return
        }

        let markdown = Self.markdownInsertion(
            markdownLines: assets.map(\.markdown),
            sourceText: string,
            replacementRange: replacementRange
        )
        breakUndoCoalescing()
        dismissSelectionMovePill()
        super.insertText(markdown, replacementRange: replacementRange)
        breakUndoCoalescing()
    }

    private static func markdownInsertion(
        markdownLines: [String],
        sourceText: String,
        replacementRange: NSRange
    ) -> String {
        let source = sourceText as NSString
        let markdown = markdownLines.joined(separator: "\n")
        let needsLeadingNewline: Bool
        if replacementRange.location == 0 {
            needsLeadingNewline = false
        } else {
            let preceding = source.character(at: replacementRange.location - 1)
            needsLeadingNewline = preceding != 0x0A && preceding != 0x0D
        }
        let end = NSMaxRange(replacementRange)
        let needsTrailingNewline: Bool
        if end >= source.length {
            // Keep block-image Markdown on its own line and leave the caret on
            // a real following line. Otherwise the next typed character lands
            // directly after `)` and makes the preview stop matching.
            needsTrailingNewline = true
        } else {
            let following = source.character(at: end)
            needsTrailingNewline = following != 0x0A && following != 0x0D
        }
        return (needsLeadingNewline ? "\n" : "")
            + markdown
            + (needsTrailingNewline ? "\n" : "")
    }

    private static func uniquePasteboardTypes(
        _ types: [NSPasteboard.PasteboardType]
    ) -> [NSPasteboard.PasteboardType] {
        var seen = Set<NSPasteboard.PasteboardType>()
        return types.filter { seen.insert($0).inserted }
    }

    private static func hasImageRepresentation(_ pboard: NSPasteboard) -> Bool {
        let fileURLs = candidateFileURLs(from: pboard)
        if !fileURLs.isEmpty {
            return fileURLs.allSatisfy(isCandidateImageFileURL)
        }
        if pboard.availableType(from: [.png, .tiff]) != nil {
            return true
        }
        return false
    }

    private static func shouldImportImagesForOrdinaryPaste(
        from pboard: NSPasteboard
    ) -> Bool {
        let fileURLs = candidateFileURLs(from: pboard)
        if !fileURLs.isEmpty {
            // Finder and screenshot tools often expose the same image as both
            // a file URL and a plain-text path. Treat that as an image paste.
            return fileURLs.allSatisfy(isCandidateImageFileURL)
        }
        guard pboard.availableType(from: [.png, .tiff]) != nil else {
            return false
        }
        // Rich-text sources can advertise a bitmap alongside meaningful text.
        // Preserve the text for ordinary Command-V; Services that explicitly
        // request an image type still follow readSelection(_:type:).
        return pboard.string(forType: .string)?.isEmpty != false
    }

    private static func imagePayloads(
        from pboard: NSPasteboard
    ) throws -> [EditorImagePayload] {
        let fileURLs = candidateFileURLs(from: pboard)
        if !fileURLs.isEmpty {
            guard fileURLs.allSatisfy(isCandidateImageFileURL) else { return [] }
            guard fileURLs.count <= 10 else {
                throw EditorImageImportError.tooManyImages
            }
            return fileURLs.map(EditorImagePayload.fileURL)
        }
        if let png = pboard.data(forType: .png) {
            return [.encoded(png)]
        }
        if let tiff = pboard.data(forType: .tiff) {
            return [.encoded(tiff)]
        }
        return []
    }

    private static func candidateFileURLs(from pboard: NSPasteboard) -> [URL] {
        (pboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] ?? []).map { $0 as URL }
    }

    private static func isCandidateImageFileURL(_ fileURL: URL) -> Bool {
        guard fileURL.isFileURL else { return false }
        switch fileURL.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "webp", "tif", "tiff":
            return true
        default:
            return false
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        defer {
            if wasComposing, !hasMarkedText() {
                editorController?.notifyTextCompositionDidEnd()
            }
        }
        dismissSelectionMovePill()
        let replacementRange = normalizedInlineInputRange(replacementRange)
        if !isApplyingMarkdownEditPlan,
           !hasMarkedText(),
           let plainText = Self.plainText(from: insertString),
           let replacement = inlineMultilineReplacement(
               plainText,
               replacementRange: replacementRange
           )
        {
            if replacement.consumesInput {
                return
            }
            super.insertText(
                replacement.text,
                replacementRange: replacement.range
            )
            setSafeCollapsedSelection(at: replacement.resultingSelection.location)
            return
        }
        if let composition = imageBoundaryComposition, hasMarkedText() {
            let committedText = Self.plainText(from: insertString)
            let marked = markedRange()
            let replacementStart = replacementRange.location == NSNotFound
                ? (marked.location == NSNotFound ? nil : marked.location)
                : replacementRange.location
            imageBoundaryComposition = nil
            if let committedText, !committedText.isEmpty {
                super.insertText(
                    Self.affixedInput(insertString, with: composition),
                    replacementRange: replacementRange
                )
                if !composition.suffix.isEmpty, let replacementStart {
                    setSafeCollapsedSelection(
                        at: replacementStart
                            + (composition.prefix as NSString).length
                            + (committedText as NSString).length
                    )
                }
            } else {
                super.insertText(insertString, replacementRange: replacementRange)
            }
            return
        }
        if !hasMarkedText(),
           let plainText = Self.plainText(from: insertString),
           !plainText.isEmpty,
           !Self.startsWithLineBreak(plainText),
           let effectiveRange = effectiveInputRange(replacementRange),
           let match = managedImageEnding(at: effectiveRange)
        {
            let followingLineLocation = NSMaxRange(match.lineRange)
            if followingLineLocation > effectiveRange.location {
                if managedImageStarting(at: followingLineLocation) != nil,
                   let lineBreak = lineTerminator(after: match)
                {
                    // The following line is another block image. Put the text
                    // on a new line between the two images instead of prefixing
                    // the second image token and making its preview disappear.
                    super.insertText(
                        plainText + lineBreak,
                        replacementRange: NSRange(
                            location: followingLineLocation,
                            length: 0
                        )
                    )
                } else {
                    super.insertText(
                        insertString,
                        replacementRange: NSRange(
                            location: followingLineLocation,
                            length: 0
                        )
                    )
                }
            } else {
                // Legacy images pasted by 1.4.38 at end-of-file have no line
                // terminator. Repair committed text atomically.
                super.insertText(
                    preferredLineBreak() + plainText,
                    replacementRange: effectiveRange
                )
            }
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    private func inlineMultilineReplacement(
        _ replacementText: String,
        replacementRange requestedRange: NSRange,
        continuationPrefixOverride: String? = nil
    ) -> (
        text: String,
        range: NSRange,
        resultingSelection: NSRange,
        consumesInput: Bool
    )? {
        synchronizeInlineFormatIndex(with: string)
        let source = string as NSString
        let range = requestedRange.location == NSNotFound
            ? selectedRange()
            : requestedRange
        guard range.location != NSNotFound,
              range.location >= 0,
              range.location <= source.length,
              range.length <= source.length - range.location
        else { return nil }

        var enclosing = inlineFormatMatches.filter {
            range.location >= $0.contentRange.location
                && NSMaxRange(range) <= NSMaxRange($0.contentRange)
        }
        guard !enclosing.isEmpty else { return nil }
        enclosing.sort {
            if $0.tokenRange.location == $1.tokenRange.location {
                return $0.tokenRange.length > $1.tokenRange.length
            }
            return $0.tokenRange.location < $1.tokenRange.location
        }

        let replacementSource = replacementText as NSString
        let replacementStartsWithWhitespace = replacementSource.length > 0
            && Self.isInlineWhitespace(replacementSource.character(at: 0))
        let replacementEndsWithWhitespace = replacementSource.length > 0
            && Self.isInlineWhitespace(
                replacementSource.character(at: replacementSource.length - 1)
            )
        let touchesRiskyBoundary = enclosing.contains { match in
            let touchesOpening = range.location == match.contentRange.location
            let touchesClosing = NSMaxRange(range) == NSMaxRange(match.contentRange)
            return replacementText.isEmpty && (touchesOpening || touchesClosing)
                || touchesOpening && replacementStartsWithWhitespace
                || touchesClosing && replacementEndsWithWhitespace
        }
        guard Self.containsLineBreak(replacementText) || touchesRiskyBoundary else {
            return nil
        }

        let unchangedSelection = NSRange(location: range.location, length: 0)
        guard !Self.containsUnescapedInlineDelimiter(in: replacementText) else {
            return ("", range, unchangedSelection, true)
        }

        let activeFormats = enclosing.map {
            InlineFormatLayer(format: $0.format, identity: $0.tokenRange)
        }
        guard MarkdownInlineFormat.allCases.allSatisfy({ format in
            activeFormats.lazy.filter { $0.format == format }.count <= 1
        }) else {
            return ("", range, unchangedSelection, true)
        }

        let continuationPrefix = continuationPrefixOverride
            ?? checklistContinuationPrefix(containing: range, source: source)
        let envelope = enclosing[0].tokenRange
        guard var units = inlineSerializationUnits(
            in: NSRange(
                location: envelope.location,
                length: range.location - envelope.location
            ),
            source: source
        ) else {
            return ("", range, unchangedSelection, true)
        }
        units += inlineSerializationUnits(
            fromReplacement: replacementText,
            formats: activeFormats,
            continuationPrefix: continuationPrefix
        )
        let caretUnitOffset = units.count
        guard let suffixUnits = inlineSerializationUnits(
            in: NSRange(
                location: NSMaxRange(range),
                length: NSMaxRange(envelope) - NSMaxRange(range)
            ),
            source: source
        ) else {
            return ("", range, unchangedSelection, true)
        }
        units += suffixUnits

        let serialized = serializeInlineUnits(
            units,
            caretUnitOffset: caretUnitOffset,
            usesNextUnitAffinity: replacementText.isEmpty
                || replacementText.last == "\n"
                || replacementText.last == "\r"
        )
        let candidate = source.substring(to: envelope.location)
            + serialized.text
            + source.substring(from: NSMaxRange(envelope))
        let candidateMatches = MarkdownInlineFormat.matches(in: candidate)
        let serializedRange = NSRange(
            location: envelope.location,
            length: (serialized.text as NSString).length
        )
        let candidateMatchesInsideEnvelope = candidateMatches.filter {
            $0.tokenRange.location >= serializedRange.location
                && NSMaxRange($0.tokenRange) <= NSMaxRange(serializedRange)
        }
        let preservesExpectedFormats = MarkdownInlineFormat.allCases.allSatisfy {
            format in
            candidateMatchesInsideEnvelope.lazy.filter { $0.format == format }.count
                == serialized.expectedFormats.lazy.filter { $0 == format }.count
        }
        let recognizedDelimiters = candidateMatchesInsideEnvelope.flatMap {
            [$0.openingDelimiterRange, $0.closingDelimiterRange]
        }
        let serializedSource = serialized.text as NSString
        let recognizesEveryDelimiter = MarkdownInlineFormat.allCases.allSatisfy {
            format in
            var searchRange = NSRange(location: 0, length: serializedSource.length)
            while searchRange.length > 0 {
                let found = serializedSource.range(
                    of: format.delimiter,
                    options: [],
                    range: searchRange
                )
                guard found.location != NSNotFound else { break }
                let global = NSRange(
                    location: envelope.location + found.location,
                    length: found.length
                )
                let next = NSMaxRange(found)
                searchRange = NSRange(
                    location: next,
                    length: serializedSource.length - next
                )
                if Self.isEscapedInlineDelimiter(
                    at: found.location,
                    in: serializedSource
                ) {
                    continue
                }
                guard recognizedDelimiters.contains(global) else { return false }
            }
            return true
        }
        guard preservesExpectedFormats, recognizesEveryDelimiter else {
            return ("", range, unchangedSelection, true)
        }

        return (
            serialized.text,
            envelope,
            NSRange(
                location: envelope.location + serialized.caretUTF16Offset,
                length: 0
            ),
            false
        )
    }

    private struct InlineFormatLayer: Equatable {
        let format: MarkdownInlineFormat
        let identity: NSRange
    }

    private struct InlineSerializationUnit {
        let text: String
        var formats: [InlineFormatLayer]
        let isLineBreak: Bool
    }

    private func inlineSerializationUnits(
        in range: NSRange,
        source: NSString
    ) -> [InlineSerializationUnit]? {
        guard range.length > 0 else { return [] }
        var result: [InlineSerializationUnit] = []
        var location = range.location
        while location < NSMaxRange(range) {
            if inlineFormatDelimiterOffsets.contains(location) {
                location += 1
                continue
            }
            let character = source.character(at: location)
            if character == 0x0D || character == 0x0A {
                let length = character == 0x0D
                    && location + 1 < NSMaxRange(range)
                    && source.character(at: location + 1) == 0x0A
                    ? 2
                    : 1
                result.append(
                    InlineSerializationUnit(
                        text: source.substring(
                            with: NSRange(location: location, length: length)
                        ),
                        formats: [],
                        isLineBreak: true
                    )
                )
                location += length
                continue
            }
            let composed = source.rangeOfComposedCharacterSequence(at: location)
            let safeRange = NSIntersectionRange(composed, range)
            let formats = inlineFormatMatches
                .filter { NSLocationInRange(location, $0.contentRange) }
                .sorted {
                    if $0.tokenRange.location == $1.tokenRange.location {
                        return $0.tokenRange.length > $1.tokenRange.length
                    }
                    return $0.tokenRange.location < $1.tokenRange.location
                }
                .map {
                    InlineFormatLayer(
                        format: $0.format,
                        identity: $0.tokenRange
                    )
                }
            guard MarkdownInlineFormat.allCases.allSatisfy({ format in
                formats.lazy.filter { $0.format == format }.count <= 1
            }) else {
                return nil
            }
            result.append(
                InlineSerializationUnit(
                    text: source.substring(with: safeRange),
                    formats: formats,
                    isLineBreak: false
                )
            )
            location = NSMaxRange(safeRange)
        }
        return result
    }

    private func inlineSerializationUnits(
        fromReplacement replacement: String,
        formats: [InlineFormatLayer],
        continuationPrefix: String
    ) -> [InlineSerializationUnit] {
        let source = replacement as NSString
        var result: [InlineSerializationUnit] = []
        var location = 0
        while location < source.length {
            let character = source.character(at: location)
            if character == 0x0D || character == 0x0A {
                let length = character == 0x0D
                    && location + 1 < source.length
                    && source.character(at: location + 1) == 0x0A
                    ? 2
                    : 1
                result.append(
                    InlineSerializationUnit(
                        text: source.substring(
                            with: NSRange(location: location, length: length)
                        ),
                        formats: [],
                        isLineBreak: true
                    )
                )
                for character in continuationPrefix {
                    result.append(
                        InlineSerializationUnit(
                            text: String(character),
                            formats: [],
                            isLineBreak: false
                        )
                    )
                }
                location += length
                continue
            }
            let composed = source.rangeOfComposedCharacterSequence(at: location)
            result.append(
                InlineSerializationUnit(
                    text: source.substring(with: composed),
                    formats: formats,
                    isLineBreak: false
                )
            )
            location = NSMaxRange(composed)
        }
        return result
    }

    private func serializeInlineUnits(
        _ originalUnits: [InlineSerializationUnit],
        caretUnitOffset: Int,
        usesNextUnitAffinity: Bool
    ) -> (
        text: String,
        caretUTF16Offset: Int,
        expectedFormats: [MarkdownInlineFormat]
    ) {
        var units = originalUnits
        var layers: [InlineFormatLayer] = []
        for layer in units.flatMap(\.formats) where !layers.contains(layer) {
            layers.append(layer)
        }
        for layer in layers {
            var index = 0
            while index < units.count {
                guard !units[index].isLineBreak,
                      units[index].formats.contains(layer)
                else {
                    index += 1
                    continue
                }
                let start = index
                while index < units.count,
                      !units[index].isLineBreak,
                      units[index].formats.contains(layer) {
                    index += 1
                }
                let end = index
                var leading = start
                while leading < end,
                      Self.isInlineBoundaryWhitespace(units[leading].text) {
                    units[leading].formats.removeAll { $0 == layer }
                    leading += 1
                }
                var trailing = end
                while trailing > leading,
                      Self.isInlineBoundaryWhitespace(units[trailing - 1].text) {
                    units[trailing - 1].formats.removeAll { $0 == layer }
                    trailing -= 1
                }
                let delimiterCharacter = String(layer.format.delimiter.prefix(1))
                if trailing - leading >= 3,
                   units[trailing - 1].text == delimiterCharacter,
                   units[trailing - 2].text == delimiterCharacter {
                    var slashIndex = trailing - 3
                    var slashCount = 0
                    while slashIndex >= leading, units[slashIndex].text == "\\" {
                        slashCount += 1
                        slashIndex -= 1
                    }
                    if slashCount % 2 == 1 {
                        for escapedIndex in (trailing - 3)..<trailing {
                            units[escapedIndex].formats.removeAll { $0 == layer }
                        }
                    }
                }
            }
        }

        var output = ""
        var active: [InlineFormatLayer] = []
        var caretOffset: Int?
        var expectedFormats: [MarkdownInlineFormat] = []
        for position in 0...units.count {
            if position == caretUnitOffset {
                if usesNextUnitAffinity,
                   position < units.count,
                   !units[position].isLineBreak {
                    let targetFormats = units[position].formats
                    let commonPrefixLength = zip(active, targetFormats)
                        .prefix { $0.0 == $0.1 }
                        .count
                    for layer in active.dropFirst(commonPrefixLength).reversed() {
                        output += layer.format.delimiter
                    }
                    for layer in targetFormats.dropFirst(commonPrefixLength) {
                        output += layer.format.delimiter
                        expectedFormats.append(layer.format)
                    }
                    active = targetFormats
                }
                caretOffset = (output as NSString).length
            }
            guard position < units.count else { break }
            let unit = units[position]
            if unit.isLineBreak {
                for layer in active.reversed() {
                    output += layer.format.delimiter
                }
                active = []
                output += unit.text
                continue
            }
            let commonPrefixLength = zip(active, unit.formats)
                .prefix { $0.0 == $0.1 }
                .count
            for layer in active.dropFirst(commonPrefixLength).reversed() {
                output += layer.format.delimiter
            }
            for layer in unit.formats.dropFirst(commonPrefixLength) {
                output += layer.format.delimiter
                expectedFormats.append(layer.format)
            }
            active = unit.formats
            output += unit.text
        }
        for layer in active.reversed() {
            output += layer.format.delimiter
        }
        return (
            output,
            caretOffset ?? (output as NSString).length,
            expectedFormats
        )
    }

    private static func isInlineBoundaryWhitespace(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func isInlineWhitespace(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isEscapedInlineDelimiter(
        at location: Int,
        in source: NSString
    ) -> Bool {
        var slashCount = 0
        var index = location - 1
        while index >= 0, source.character(at: index) == 0x5C {
            slashCount += 1
            index -= 1
        }
        return slashCount % 2 == 1
    }

    private static func containsUnescapedInlineDelimiter(in text: String) -> Bool {
        let source = text as NSString
        for format in MarkdownInlineFormat.allCases {
            var searchRange = NSRange(location: 0, length: source.length)
            while searchRange.length > 0 {
                let found = source.range(
                    of: format.delimiter,
                    options: [],
                    range: searchRange
                )
                guard found.location != NSNotFound else { break }
                if !isEscapedInlineDelimiter(at: found.location, in: source) {
                    return true
                }
                let next = NSMaxRange(found)
                searchRange = NSRange(
                    location: next,
                    length: source.length - next
                )
            }
        }
        return false
    }

    private func checklistContinuationPrefix(
        containing range: NSRange,
        source: NSString
    ) -> String {
        guard let match = checklistMatches.first(where: {
            range.location >= $0.contentRange.location
                && NSMaxRange(range) <= NSMaxRange($0.contentRange)
        }) else { return "" }
        return source.substring(
            with: NSRange(
                location: match.lineRange.location,
                length: match.contentRange.location - match.lineRange.location
            )
        )
    }

    private static func containsLineBreak(_ text: String) -> Bool {
        text.utf16.contains(0x0A) || text.utf16.contains(0x0D)
    }

    private static func leadingLineBreak(in text: String) -> String? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        switch source.character(at: 0) {
        case 0x0D:
            return source.length > 1 && source.character(at: 1) == 0x0A
                ? "\r\n"
                : "\r"
        case 0x0A:
            return "\n"
        default:
            return nil
        }
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        dismissSelectionMovePill()
        if let composition = imageBoundaryComposition, hasMarkedText() {
            if Self.plainText(from: string)?.isEmpty == false {
                super.setMarkedText(
                    Self.affixedInput(string, with: composition),
                    selectedRange: Self.adjustedMarkedSelection(
                        selectedRange,
                        prefix: composition.prefix
                    ),
                    replacementRange: replacementRange
                )
            } else {
                // Cancelling removes the complete marked range, including its
                // temporary structural line break, without changing Markdown.
                super.setMarkedText(
                    string,
                    selectedRange: selectedRange,
                    replacementRange: replacementRange
                )
                if !hasMarkedText() {
                    imageBoundaryComposition = nil
                }
            }
            return
        }
        if !hasMarkedText(),
           let plainText = Self.plainText(from: string),
           !plainText.isEmpty,
           !Self.startsWithLineBreak(plainText),
           let effectiveRange = effectiveInputRange(replacementRange),
           let match = managedImageEnding(at: effectiveRange)
        {
            let followingLineLocation = NSMaxRange(match.lineRange)
            if followingLineLocation > effectiveRange.location {
                if managedImageStarting(at: followingLineLocation) != nil,
                   let lineBreak = lineTerminator(after: match)
                {
                    let composition = ImageBoundaryComposition(
                        prefix: "",
                        suffix: lineBreak
                    )
                    imageBoundaryComposition = composition
                    super.setMarkedText(
                        Self.affixedInput(string, with: composition),
                        selectedRange: Self.adjustedMarkedSelection(
                            selectedRange,
                            prefix: composition.prefix
                        ),
                        replacementRange: NSRange(
                            location: followingLineLocation,
                            length: 0
                        )
                    )
                } else {
                    super.setMarkedText(
                        string,
                        selectedRange: selectedRange,
                        replacementRange: NSRange(
                            location: followingLineLocation,
                            length: 0
                        )
                    )
                }
            } else {
                // A 1.4.38 image at end-of-file has no following line yet.
                // Keep the structural line break inside the marked range so
                // cancelling composition restores the byte-identical original.
                let composition = ImageBoundaryComposition(
                    prefix: preferredLineBreak(),
                    suffix: ""
                )
                imageBoundaryComposition = composition
                super.setMarkedText(
                    Self.affixedInput(string, with: composition),
                    selectedRange: Self.adjustedMarkedSelection(
                        selectedRange,
                        prefix: composition.prefix
                    ),
                    replacementRange: effectiveRange
                )
            }
            return
        }
        super.setMarkedText(
            string,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
    }

    private func effectiveInputRange(_ replacementRange: NSRange) -> NSRange? {
        let range = replacementRange.location == NSNotFound
            ? selectedRange()
            : replacementRange
        let sourceLength = (string as NSString).length
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length == 0,
              range.location <= sourceLength
        else { return nil }
        return range
    }

    private func managedImageEnding(
        at replacementRange: NSRange
    ) -> MarkdownImageMatch? {
        managedImageMatches.first {
            NSMaxRange($0.tokenRange) == replacementRange.location
        }
    }

    private func managedImageStarting(at location: Int) -> MarkdownImageMatch? {
        managedImageMatches.first { $0.tokenRange.location == location }
    }

    private func lineTerminator(after match: MarkdownImageMatch) -> String? {
        let source = string as NSString
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        source.getLineStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: match.tokenRange
        )
        guard lineEnd > contentsEnd else { return nil }
        return source.substring(
            with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd)
        )
    }

    private func preferredLineBreak() -> String {
        let source = string as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let crlf = source.range(of: "\r\n", options: [], range: fullRange)
        if crlf.location != NSNotFound { return "\r\n" }
        let lf = source.range(of: "\n", options: [], range: fullRange)
        if lf.location != NSNotFound { return "\n" }
        let cr = source.range(of: "\r", options: [], range: fullRange)
        if cr.location != NSNotFound { return "\r" }
        return "\n"
    }

    private func setSafeCollapsedSelection(at location: Int) {
        let sourceLength = (string as NSString).length
        guard location >= 0, location <= sourceLength else { return }
        setSelectedRange(NSRange(location: location, length: 0))
    }

    private func normalizedInlineInputRange(_ requestedRange: NSRange) -> NSRange {
        guard !hasMarkedText() else { return requestedRange }
        synchronizeInlineFormatIndex(with: string)
        let effectiveRange = requestedRange.location == NSNotFound
            ? selectedRange()
            : requestedRange
        guard effectiveRange.length == 0,
              let delimiter = inlineDelimiterRange(
                  containingUTF16Offset: effectiveRange.location
              ),
              effectiveRange.location > delimiter.location
        else { return requestedRange }

        let distanceFromStart = effectiveRange.location - delimiter.location
        let distanceFromEnd = NSMaxRange(delimiter) - effectiveRange.location
        let location = distanceFromStart <= distanceFromEnd
            ? delimiter.location
            : NSMaxRange(delimiter)
        if requestedRange.location == NSNotFound {
            setSafeCollapsedSelection(at: location)
            return requestedRange
        }
        return NSRange(location: location, length: 0)
    }

    private static func plainText(from input: Any) -> String? {
        if let string = input as? String {
            return string
        }
        if let attributedString = input as? NSAttributedString {
            return attributedString.string
        }
        return nil
    }

    private static func affixedInput(
        _ input: Any,
        with composition: ImageBoundaryComposition
    ) -> Any {
        if let attributed = input as? NSAttributedString {
            let result = NSMutableAttributedString(string: composition.prefix)
            result.append(attributed)
            result.append(NSAttributedString(string: composition.suffix))
            return result
        }
        return composition.prefix
            + (plainText(from: input) ?? "")
            + composition.suffix
    }

    private static func adjustedMarkedSelection(
        _ range: NSRange,
        prefix: String
    ) -> NSRange {
        guard range.location != NSNotFound else { return range }
        return NSRange(
            location: range.location + (prefix as NSString).length,
            length: range.length
        )
    }

    private static func startsWithLineBreak(_ string: String) -> Bool {
        string.first == "\n" || string.first == "\r"
    }

    private func inlineDelimiterRange(
        containingUTF16Offset offset: Int
    ) -> NSRange? {
        inlineFormatDelimiterRanges.first {
            offset >= $0.location && offset < NSMaxRange($0)
        }
    }

    private func skipInlineDelimiters(
        from rawLocation: Int,
        direction: InlineTextDirection
    ) -> (location: Int, crossedDelimiter: Bool) {
        var location = rawLocation
        var crossedDelimiter = false
        while true {
            let range: NSRange?
            switch direction {
            case .forward:
                range = inlineFormatDelimiterRanges.first {
                    location >= $0.location && location < NSMaxRange($0)
                }
            case .backward:
                range = inlineFormatDelimiterRanges.last {
                    location > $0.location && location <= NSMaxRange($0)
                }
            }
            guard let range else { break }
            crossedDelimiter = true
            location = direction == .forward
                ? NSMaxRange(range)
                : range.location
        }
        return (location, crossedDelimiter)
    }

    private func nextVisibleCaretLocation(
        from rawLocation: Int,
        direction: InlineTextDirection,
        skipsTrailingDelimiters: Bool
    ) -> Int? {
        let source = string as NSString
        let initial = skipInlineDelimiters(
            from: min(max(rawLocation, 0), source.length),
            direction: direction
        )
        let visibleCharacterRange: NSRange
        switch direction {
        case .forward:
            guard initial.location < source.length else { return nil }
            visibleCharacterRange = source.rangeOfComposedCharacterSequence(
                at: initial.location
            )
        case .backward:
            guard initial.location > 0 else { return nil }
            visibleCharacterRange = source.rangeOfComposedCharacterSequence(
                at: initial.location - 1
            )
        }
        let afterCharacter = direction == .forward
            ? NSMaxRange(visibleCharacterRange)
            : visibleCharacterRange.location
        guard skipsTrailingDelimiters else { return afterCharacter }
        return skipInlineDelimiters(from: afterCharacter, direction: direction).location
    }

    private func inlineSelectionAnchor(
        at rawLocation: Int,
        extending direction: InlineTextDirection
    ) -> Int {
        var location = rawLocation
        var changed = true
        while changed {
            changed = false
            for match in inlineFormatMatches {
                let opening = match.openingDelimiterRange
                if location == opening.location || location == NSMaxRange(opening) {
                    let adjusted = direction == .forward
                        ? NSMaxRange(opening)
                        : opening.location
                    if adjusted != location {
                        location = adjusted
                        changed = true
                    }
                }
                let closing = match.closingDelimiterRange
                if location == closing.location || location == NSMaxRange(closing) {
                    let adjusted = direction == .forward
                        ? NSMaxRange(closing)
                        : closing.location
                    if adjusted != location {
                        location = adjusted
                        changed = true
                    }
                }
            }
        }
        return location
    }

    private func selectionExpandedAcrossTouchedDelimiters(
        _ requestedRange: NSRange
    ) -> NSRange {
        var result = requestedRange
        var expanded = true
        while expanded {
            expanded = false
            for match in inlineFormatMatches {
                let touchesOpening = Self.intersects(
                    result,
                    match.openingDelimiterRange
                )
                let touchesClosing = Self.intersects(
                    result,
                    match.closingDelimiterRange
                )
                guard touchesOpening || touchesClosing else { continue }

                // While shrinking a Shift selection, a range may end with only
                // the invisible opening delimiter (or begin with only the
                // closing delimiter). Trim that delimiter away instead of
                // re-expanding the token and making the caret appear stuck.
                if !Self.intersects(result, match.contentRange) {
                    let resultEnd = NSMaxRange(result)
                    if touchesOpening,
                       result.location < match.openingDelimiterRange.location,
                       resultEnd <= NSMaxRange(match.openingDelimiterRange)
                    {
                        result.length = match.openingDelimiterRange.location
                            - result.location
                        expanded = true
                        continue
                    }
                    if touchesClosing,
                       result.location >= match.closingDelimiterRange.location,
                       resultEnd > NSMaxRange(match.closingDelimiterRange)
                    {
                        result = NSRange(
                            location: NSMaxRange(match.closingDelimiterRange),
                            length: resultEnd - NSMaxRange(match.closingDelimiterRange)
                        )
                        expanded = true
                        continue
                    }
                }

                let union = NSUnionRange(result, match.tokenRange)
                if union != result {
                    result = union
                    expanded = true
                }
            }
        }
        return result
    }

    @discardableResult
    private func moveAcrossInlineFormatting(
        direction: InlineTextDirection,
        modifyingSelection: Bool
    ) -> Bool {
        guard !hasMarkedText(),
              selectedRanges.count == 1
        else { return false }
        synchronizeInlineFormatIndex(with: string)
        guard !inlineFormatDelimiterRanges.isEmpty else { return false }

        let selection = selectedRange()
        let sourceLength = (string as NSString).length
        guard selection.location != NSNotFound,
              selection.location >= 0,
              selection.location <= sourceLength,
              selection.length <= sourceLength - selection.location
        else { return false }

        if !modifyingSelection, selection.length > 0 {
            let collapsedLocation = direction == .backward
                ? selection.location
                : NSMaxRange(selection)
            inlineKeyboardSelectionAnchor = nil
            inlineKeyboardSelectionActiveLocation = nil
            setInlineKeyboardSelection(
                NSRange(location: collapsedLocation, length: 0),
                preservingAnchor: nil,
                activeLocation: nil
            )
            return true
        }

        let anchor: Int
        let activeLocation: Int
        if modifyingSelection {
            if let existingAnchor = inlineKeyboardSelectionAnchor,
               let existingActive = inlineKeyboardSelectionActiveLocation
            {
                anchor = existingAnchor
                activeLocation = existingActive
            } else if selection.length == 0 {
                let adjustedAnchor = inlineSelectionAnchor(
                    at: selection.location,
                    extending: direction
                )
                anchor = adjustedAnchor
                activeLocation = adjustedAnchor
            } else if direction == .forward {
                anchor = selection.location
                activeLocation = NSMaxRange(selection)
            } else {
                anchor = NSMaxRange(selection)
                activeLocation = selection.location
            }
        } else {
            anchor = selection.location
            activeLocation = selection.location
        }

        guard let destination = nextVisibleCaretLocation(
            from: activeLocation,
            direction: direction,
            skipsTrailingDelimiters: !modifyingSelection
        ) else { return true }

        if modifyingSelection {
            let rawRange = NSRange(
                location: min(anchor, destination),
                length: abs(destination - anchor)
            )
            let range = selectionExpandedAcrossTouchedDelimiters(rawRange)
            setInlineKeyboardSelection(
                range,
                preservingAnchor: anchor,
                activeLocation: destination
            )
        } else {
            inlineKeyboardSelectionAnchor = nil
            inlineKeyboardSelectionActiveLocation = nil
            setInlineKeyboardSelection(
                NSRange(location: destination, length: 0),
                preservingAnchor: nil,
                activeLocation: nil
            )
        }
        return true
    }

    private func setInlineKeyboardSelection(
        _ range: NSRange,
        preservingAnchor anchor: Int?,
        activeLocation: Int?
    ) {
        isAdjustingInlineKeyboardSelection = true
        inlineKeyboardSelectionAnchor = anchor
        inlineKeyboardSelectionActiveLocation = activeLocation
        setSelectedRange(range)
        scrollRangeToVisible(range)
        isAdjustingInlineKeyboardSelection = false
    }

    override func moveLeft(_ sender: Any?) {
        guard moveAcrossInlineFormatting(
            direction: .backward,
            modifyingSelection: false
        ) else {
            super.moveLeft(sender)
            return
        }
    }

    override func moveRight(_ sender: Any?) {
        guard moveAcrossInlineFormatting(
            direction: .forward,
            modifyingSelection: false
        ) else {
            super.moveRight(sender)
            return
        }
    }

    override func moveBackward(_ sender: Any?) {
        guard moveAcrossInlineFormatting(
            direction: .backward,
            modifyingSelection: false
        ) else {
            super.moveBackward(sender)
            return
        }
    }

    override func moveForward(_ sender: Any?) {
        guard moveAcrossInlineFormatting(
            direction: .forward,
            modifyingSelection: false
        ) else {
            super.moveForward(sender)
            return
        }
    }

    override func moveLeftAndModifySelection(_ sender: Any?) {
        guard moveAcrossInlineFormatting(
            direction: .backward,
            modifyingSelection: true
        ) else {
            super.moveLeftAndModifySelection(sender)
            return
        }
    }

    override func moveRightAndModifySelection(_ sender: Any?) {
        guard moveAcrossInlineFormatting(
            direction: .forward,
            modifyingSelection: true
        ) else {
            super.moveRightAndModifySelection(sender)
            return
        }
    }

    override func moveBackwardAndModifySelection(_ sender: Any?) {
        guard moveAcrossInlineFormatting(
            direction: .backward,
            modifyingSelection: true
        ) else {
            super.moveBackwardAndModifySelection(sender)
            return
        }
    }

    override func moveForwardAndModifySelection(_ sender: Any?) {
        guard moveAcrossInlineFormatting(
            direction: .forward,
            modifyingSelection: true
        ) else {
            super.moveForwardAndModifySelection(sender)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let commandModifiers = event.modifierFlags.intersection(
            [.command, .option, .control, .shift]
        )
        let key = event.charactersIgnoringModifiers
        let normalizedKey = key?.lowercased()
        if commandModifiers == .command, normalizedKey == "b" {
            toggleInlineFormat(.bold)
            return true
        }
        if commandModifiers == [.command, .shift], normalizedKey == "h" {
            toggleInlineFormat(.highlight)
            return true
        }
        let isReturn = key == "\r" || key == "\u{3}"
        guard commandModifiers == .command, isReturn else {
            return super.performKeyEquivalent(with: event)
        }

        guard isEditable, !hasMarkedText(),
              let plan = MarkdownChecklist.cycleTodoState(
                  in: string,
                  selection: selectedRange()
              )
        else { return true }
        apply(plan)
        return true
    }

    override func insertNewline(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else {
            super.insertNewline(sender)
            return
        }
        synchronizeInlineFormatIndex(with: string)
        let selection = selectedRange()
        guard selection.length == 0 else {
            super.insertNewline(sender)
            return
        }
        let insertionLocation = inlineNewlineInsertionLocation(
            from: selection.location
        )
        let insertionSelection = NSRange(location: insertionLocation, length: 0)
        let lineBreak = preferredLineBreak()

        if let todoPlan = MarkdownChecklist.returnPlan(
            in: string,
            selection: insertionSelection
        ) {
            guard todoPlan.action == .insertNextTodo else {
                apply(todoPlan.edit)
                return
            }
            let todoReplacement = todoPlan.edit.replacementString as NSString
            guard let todoLineBreak = Self.leadingLineBreak(
                in: todoPlan.edit.replacementString
            ) else {
                apply(todoPlan.edit)
                return
            }
            if let replacement = inlineMultilineReplacement(
                todoLineBreak,
                replacementRange: todoPlan.edit.replacementRange,
                continuationPrefixOverride: todoReplacement.substring(
                    from: (todoLineBreak as NSString).length
                )
            ) {
                guard !replacement.consumesInput else { return }
                apply(
                    MarkdownTextEditPlan(
                        replacementRange: replacement.range,
                        replacementString: replacement.text,
                        resultingSelection: replacement.resultingSelection
                    )
                )
                return
            }
            apply(todoPlan.edit)
            return
        }

        if let replacement = inlineMultilineReplacement(
            lineBreak,
            replacementRange: insertionSelection
        ) {
            guard !replacement.consumesInput else { return }
            apply(
                MarkdownTextEditPlan(
                    replacementRange: replacement.range,
                    replacementString: replacement.text,
                    resultingSelection: replacement.resultingSelection
                )
            )
            return
        }
        apply(
            MarkdownTextEditPlan(
                replacementRange: insertionSelection,
                replacementString: lineBreak,
                resultingSelection: NSRange(
                    location: insertionLocation + (lineBreak as NSString).length,
                    length: 0
                )
            )
        )
    }

    private func inlineNewlineInsertionLocation(from rawLocation: Int) -> Int {
        var location = rawLocation
        var changed = true
        while changed {
            changed = false
            for match in inlineFormatMatches.reversed() {
                let opening = match.openingDelimiterRange
                if location >= opening.location,
                   location <= NSMaxRange(opening),
                   location != match.tokenRange.location
                {
                    location = match.tokenRange.location
                    changed = true
                    continue
                }
                let closing = match.closingDelimiterRange
                if location >= closing.location,
                   location <= NSMaxRange(closing),
                   location != NSMaxRange(match.tokenRange)
                {
                    location = NSMaxRange(match.tokenRange)
                    changed = true
                }
            }
        }
        return location
    }

    private func adjacentVisibleCharacterRange(
        to rawLocation: Int,
        direction: InlineTextDirection
    ) -> (range: NSRange?, crossedDelimiter: Bool) {
        let source = string as NSString
        let initial = skipInlineDelimiters(
            from: min(max(rawLocation, 0), source.length),
            direction: direction
        )
        switch direction {
        case .forward:
            guard initial.location < source.length else {
                return (nil, initial.crossedDelimiter)
            }
            return (
                source.rangeOfComposedCharacterSequence(at: initial.location),
                initial.crossedDelimiter
            )
        case .backward:
            guard initial.location > 0 else {
                return (nil, initial.crossedDelimiter)
            }
            return (
                source.rangeOfComposedCharacterSequence(at: initial.location - 1),
                initial.crossedDelimiter
            )
        }
    }

    private func atomicInlineDeletionRange(for requestedRange: NSRange) -> NSRange {
        var result = requestedRange
        var expanded = true
        while expanded {
            expanded = false
            for match in inlineFormatMatches {
                let touchesDelimiter = Self.intersects(
                    result,
                    match.openingDelimiterRange
                ) || Self.intersects(result, match.closingDelimiterRange)
                let removesAllContent = Self.contains(
                    result,
                    match.contentRange
                )
                guard touchesDelimiter || removesAllContent else { continue }
                let union = NSUnionRange(result, match.tokenRange)
                if union != result {
                    result = union
                    expanded = true
                }
            }
        }
        return result
    }

    @discardableResult
    private func performAtomicInlineDeletion(
        direction: InlineTextDirection
    ) -> Bool {
        guard selectedRanges.count == 1 else { return false }
        synchronizeInlineFormatIndex(with: string)
        guard !inlineFormatDelimiterRanges.isEmpty else { return false }

        let selection = selectedRange()
        let sourceLength = (string as NSString).length
        guard selection.location != NSNotFound,
              selection.location >= 0,
              selection.location <= sourceLength,
              selection.length <= sourceLength - selection.location
        else { return false }

        if selection.length > 0 {
            let deletionRange = atomicInlineDeletionRange(for: selection)
            guard deletionRange != selection else { return false }
            inlineKeyboardSelectionAnchor = nil
            apply(
                MarkdownTextEditPlan(
                    replacementRange: deletionRange,
                    replacementString: "",
                    resultingSelection: NSRange(
                        location: deletionRange.location,
                        length: 0
                    )
                )
            )
            return true
        }

        let adjacent = adjacentVisibleCharacterRange(
            to: selection.location,
            direction: direction
        )
        guard let visibleRange = adjacent.range else {
            // At the visual beginning/end, consume the command if it crossed a
            // hidden delimiter. Letting NSTextView continue would delete one
            // invisible `*` or `=` and expose a broken token.
            return adjacent.crossedDelimiter
        }
        let deletionRange = atomicInlineDeletionRange(for: visibleRange)
        guard adjacent.crossedDelimiter || deletionRange != visibleRange else {
            return false
        }

        inlineKeyboardSelectionAnchor = nil
        apply(
            MarkdownTextEditPlan(
                replacementRange: deletionRange,
                replacementString: "",
                resultingSelection: NSRange(
                    location: deletionRange.location,
                    length: 0
                )
            )
        )
        return true
    }

    private static func intersects(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        NSIntersectionRange(lhs, rhs).length > 0
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer.location <= inner.location && NSMaxRange(outer) >= NSMaxRange(inner)
    }

    @discardableResult
    private func performCanonicalInlineDeletion(
        direction: InlineTextDirection
    ) -> Bool {
        synchronizeInlineFormatIndex(with: string)
        let selection = selectedRange()
        let deletionRange: NSRange
        if selection.length > 0 {
            deletionRange = selection
        } else {
            guard let adjacent = adjacentVisibleCharacterRange(
                to: selection.location,
                direction: direction
            ).range else { return false }
            deletionRange = adjacent
        }
        guard let replacement = inlineMultilineReplacement(
            "",
            replacementRange: deletionRange
        ) else { return false }
        guard !replacement.consumesInput else { return true }
        apply(
            MarkdownTextEditPlan(
                replacementRange: replacement.range,
                replacementString: replacement.text,
                resultingSelection: replacement.resultingSelection
            )
        )
        return true
    }

    override func deleteBackward(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else {
            super.deleteBackward(sender)
            return
        }
        synchronizeInlineFormatIndex(with: string)
        let rawSelection = selectedRange()
        let checklistSelection: NSRange
        if rawSelection.length == 0 {
            checklistSelection = NSRange(
                location: skipInlineDelimiters(
                    from: rawSelection.location,
                    direction: .backward
                ).location,
                length: 0
            )
        } else {
            checklistSelection = rawSelection
        }
        if let plan = MarkdownChecklist.deleteBackwardPlan(
                  in: string,
                  selection: checklistSelection
              ) {
            apply(plan)
            return
        }
        if performAtomicInlineDeletion(direction: .backward) { return }
        if performCanonicalInlineDeletion(direction: .backward) { return }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        guard isEditable, !hasMarkedText(), selectedRanges.count == 1 else {
            super.deleteForward(sender)
            return
        }
        if performAtomicInlineDeletion(direction: .forward) { return }
        if performCanonicalInlineDeletion(direction: .forward) { return }
        super.deleteForward(sender)
    }

    @discardableResult
    private func performAtomicInlineWordDeletion(
        direction: InlineTextDirection
    ) -> Bool {
        guard selectedRanges.count == 1 else { return false }
        synchronizeInlineFormatIndex(with: string)
        guard !inlineFormatDelimiterRanges.isEmpty else { return false }
        let selection = selectedRange()
        if selection.length > 0 {
            return performAtomicInlineDeletion(direction: direction)
        }

        guard let wordRange = nativeWordDeletionRange(direction: direction) else {
            return false
        }
        guard wordRange.length > 0 else { return false }
        let touchesInlineFormat = inlineFormatMatches.contains {
            Self.intersects(wordRange, $0.tokenRange)
        }
        guard touchesInlineFormat else { return false }
        let deletionRange = atomicInlineDeletionRange(for: wordRange)
        apply(
            MarkdownTextEditPlan(
                replacementRange: deletionRange,
                replacementString: "",
                resultingSelection: NSRange(
                    location: deletionRange.location,
                    length: 0
                )
            )
        )
        return true
    }

    private func nativeWordDeletionRange(
        direction: InlineTextDirection
    ) -> NSRange? {
        let originalRanges = selectedRanges
        let originalAffinity = selectionAffinity
        let originalAnchor = inlineKeyboardSelectionAnchor
        let originalActive = inlineKeyboardSelectionActiveLocation
        isAdjustingInlineKeyboardSelection = true
        switch direction {
        case .backward:
            super.moveWordBackwardAndModifySelection(nil)
        case .forward:
            super.moveWordForwardAndModifySelection(nil)
        }
        let candidate = selectedRange()
        setSelectedRanges(
            originalRanges,
            affinity: originalAffinity,
            stillSelecting: false
        )
        inlineKeyboardSelectionAnchor = originalAnchor
        inlineKeyboardSelectionActiveLocation = originalActive
        isAdjustingInlineKeyboardSelection = false
        return candidate.location == NSNotFound ? nil : candidate
    }

    override func deleteWordBackward(_ sender: Any?) {
        guard isEditable, !hasMarkedText(),
              performAtomicInlineWordDeletion(direction: .backward)
        else {
            super.deleteWordBackward(sender)
            return
        }
    }

    override func deleteWordForward(_ sender: Any?) {
        guard isEditable, !hasMarkedText(),
              performAtomicInlineWordDeletion(direction: .forward)
        else {
            super.deleteWordForward(sender)
            return
        }
    }

    @discardableResult
    private func performAtomicInlineLineDeletion(
        direction: InlineTextDirection
    ) -> Bool {
        guard selectedRanges.count == 1 else { return false }
        synchronizeInlineFormatIndex(with: string)
        guard !inlineFormatDelimiterRanges.isEmpty else { return false }
        let selection = selectedRange()
        guard selection.length == 0 else {
            return performAtomicInlineDeletion(direction: direction)
        }
        let source = string as NSString
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        source.getLineStart(
            &lineStart,
            end: &lineEnd,
            contentsEnd: &contentsEnd,
            for: selection
        )
        let requestedRange: NSRange
        if direction == .backward {
            requestedRange = NSRange(
                location: lineStart,
                length: selection.location - lineStart
            )
        } else {
            requestedRange = NSRange(
                location: selection.location,
                length: contentsEnd - selection.location
            )
        }
        guard requestedRange.length > 0 else { return false }
        let deletionRange = atomicInlineDeletionRange(for: requestedRange)
        guard deletionRange != requestedRange else { return false }
        // A line command whose raw range clips one hidden delimiter cannot be
        // represented as one safe contiguous deletion without also removing
        // visible text on the other side of the caret. Consume it unchanged;
        // ordinary character/word deletion remains fully available.
        return true
    }

    override func deleteToBeginningOfLine(_ sender: Any?) {
        guard isEditable, !hasMarkedText(),
              performAtomicInlineLineDeletion(direction: .backward)
        else {
            super.deleteToBeginningOfLine(sender)
            return
        }
    }

    override func deleteToEndOfLine(_ sender: Any?) {
        guard isEditable, !hasMarkedText(),
              performAtomicInlineLineDeletion(direction: .forward)
        else {
            super.deleteToEndOfLine(sender)
            return
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        dismissSelectionMovePill()
        return super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        dismissSelectionMovePill()
        let point = convert(event.locationInWindow, from: nil)
        guard isEditable, !hasMarkedText() else {
            super.mouseDown(with: event)
            return
        }

        if let geometry = checkboxGeometry(at: point),
           let plan = MarkdownChecklist.toggleCheckbox(
               in: string,
               clickUTF16Offset: geometry.match.tokenRange.location + 1
           )
        {
            apply(plan, selectionOverride: selectedRange())
            return
        }

        let selectionModifiers = event.modifierFlags.intersection(
            [.shift, .command, .option, .control]
        )
        if event.clickCount == 1,
           selectionModifiers.isEmpty,
           let insertionLocation = managedImageContinuationInsertionLocation(
               at: point
           )
        {
            window?.makeFirstResponder(self)
            breakUndoCoalescing()
            isHandlingMouseSelection = true
            setSafeCollapsedSelection(at: insertionLocation)
            isHandlingMouseSelection = false
            scheduleSelectionMovePillPresentation()
            return
        }

        isHandlingMouseSelection = true
        super.mouseDown(with: event)
        isHandlingMouseSelection = false
        normalizeSelectionOutsideInlineDelimiters()
        scheduleSelectionMovePillPresentation()
    }

    private func normalizeSelectionOutsideInlineDelimiters() {
        guard !hasMarkedText(), selectedRanges.count == 1 else { return }
        synchronizeInlineFormatIndex(with: string)
        let selection = selectedRange()
        if selection.length > 0 {
            let normalized = selectionExpandedAcrossTouchedDelimiters(selection)
            if normalized != selection {
                setSelectedRange(normalized)
            }
            return
        }
        guard let delimiter = inlineDelimiterRange(
                  containingUTF16Offset: selection.location
              ),
              selection.location > delimiter.location
        else { return }
        let distanceFromStart = selection.location - delimiter.location
        let distanceFromEnd = NSMaxRange(delimiter) - selection.location
        setSafeCollapsedSelection(
            at: distanceFromStart <= distanceFromEnd
                ? delimiter.location
                : NSMaxRange(delimiter)
        )
    }

    private func managedImageContinuationInsertionLocation(
        at point: NSPoint
    ) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let sourceLength = (string as NSString).length
        let nativeLocation = min(
            characterIndexForInsertion(at: point),
            sourceLength
        )
        let origin = textContainerOrigin
        guard point.x >= origin.x,
              point.x <= origin.x + textContainer.containerSize.width
        else { return nil }

        for geometry in managedImageGeometries() {
            let match = geometry.match
            let tokenEnd = NSMaxRange(match.tokenRange)
            let followingLineLocation = NSMaxRange(match.lineRange)
            guard point.y > geometry.hitRect.maxY,
                  followingLineLocation <= sourceLength,
                  nativeLocation >= match.tokenRange.location,
                  nativeLocation < followingLineLocation,
                  let followingLineRect = lineFragmentRectInTextView(
                      atUTF16Offset: followingLineLocation,
                      layoutManager: layoutManager,
                      textContainerOrigin: origin,
                      sourceLength: sourceLength
                  ),
                  point.y <= followingLineRect.maxY
            else { continue }

            if managedImageStarting(at: followingLineLocation) != nil {
                // Typing between adjacent image blocks is handled atomically by
                // the existing image-boundary input path.
                return tokenEnd
            }
            if let checklist = checklistMatches.first(where: {
                $0.lineRange.location == followingLineLocation
            }) {
                return checklist.contentRange.location
            }
            return followingLineLocation
        }
        return nil
    }

    private func lineFragmentRectInTextView(
        atUTF16Offset offset: Int,
        layoutManager: NSLayoutManager,
        textContainerOrigin: NSPoint,
        sourceLength: Int
    ) -> NSRect? {
        let rect: NSRect
        if offset == sourceLength {
            rect = layoutManager.extraLineFragmentRect
        } else {
            guard offset >= 0, offset < sourceLength else { return nil }
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: offset)
            guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
            rect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: nil
            )
        }
        guard rect.height > 0 else { return nil }
        return rect.offsetBy(
            dx: textContainerOrigin.x,
            dy: textContainerOrigin.y
        )
    }

    override func drawInsertionPoint(
        in rect: NSRect,
        color: NSColor,
        turnedOn flag: Bool
    ) {
        let adjustedRect = adjustedInsertionPointRect(rect)
        super.drawInsertionPoint(
            in: adjustedRect,
            color: color,
            turnedOn: flag
        )
    }

    func adjustedInsertionPointRect(_ rect: NSRect) -> NSRect {
        (layoutManager as? SymmetricSelectionLayoutManager)?
            .centeredInsertionPointRect(rect, textView: self) ?? rect
    }

    override func draw(_ dirtyRect: NSRect) {
        drawInlineHighlightBackgrounds(in: dirtyRect)
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        for geometry in managedImageGeometries()
        where geometry.hitRect.intersects(dirtyRect) {
            drawManagedImagePreview(geometry)
        }
        for geometry in checkboxGeometries() where geometry.hitRect.intersects(dirtyRect) {
            let isHovered = hoveredMarkerLocation == geometry.match.markerRange.location
            drawCheckbox(
                in: geometry.boxRect,
                isChecked: geometry.match.isChecked,
                isHovered: isHovered
            )
        }
    }

    private func drawInlineHighlightBackgrounds(in dirtyRect: NSRect) {
        guard let layoutManager,
              let textContainer,
              let textStorage,
              !inlineFormatMatches.isEmpty
        else { return }

        let origin = textContainerOrigin
        let backingScale = max(
            window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2,
            1
        )
        let sourceLength = textStorage.length
        let fallbackFont = NSFont.monospacedSystemFont(
            ofSize: checklistFontSize,
            weight: .regular
        )
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.systemYellow.withAlphaComponent(0.38).setFill()

        for match in inlineFormatMatches
        where match.format == .highlight && match.contentRange.length > 0 {
            guard match.contentRange.location < sourceLength else { continue }
            let contentRange = NSRange(
                location: match.contentRange.location,
                length: min(
                    match.contentRange.length,
                    sourceLength - match.contentRange.location
                )
            )
            guard contentRange.length > 0 else { continue }
            layoutManager.ensureLayout(forCharacterRange: contentRange)
            let highlightGlyphRange = layoutManager.glyphRange(
                forCharacterRange: contentRange,
                actualCharacterRange: nil
            )
            guard highlightGlyphRange.length > 0 else { continue }

            layoutManager.enumerateLineFragments(
                forGlyphRange: highlightGlyphRange
            ) { lineRect, _, _, lineGlyphRange, _ in
                let segmentGlyphRange = NSIntersectionRange(
                    highlightGlyphRange,
                    lineGlyphRange
                )
                guard segmentGlyphRange.length > 0,
                      segmentGlyphRange.location < layoutManager.numberOfGlyphs
                else { return }

                let characterIndex = layoutManager.characterIndexForGlyph(
                    at: segmentGlyphRange.location
                )
                let font = characterIndex < sourceLength
                    ? (textStorage.attribute(
                        .font,
                        at: characterIndex,
                        effectiveRange: nil
                    ) as? NSFont ?? fallbackFont)
                    : fallbackFont
                let glyphLocation = layoutManager.location(
                    forGlyphAt: segmentGlyphRange.location
                )
                let baselineY = origin.y + lineRect.minY + glyphLocation.y
                let lineMinY = origin.y + lineRect.minY
                let lineMaxY = origin.y + lineRect.maxY
                var minY = max(lineMinY, baselineY - font.ascender + 1)
                var maxY = min(lineMaxY, baselineY - font.descender - 1)
                minY = ceil(minY * backingScale) / backingScale
                maxY = floor(maxY * backingScale) / backingScale

                let glyphBounds = layoutManager.boundingRect(
                    forGlyphRange: segmentGlyphRange,
                    in: textContainer
                ).offsetBy(dx: origin.x, dy: origin.y)
                let minX = floor(glyphBounds.minX * backingScale) / backingScale
                let maxX = ceil(glyphBounds.maxX * backingScale) / backingScale
                let highlightRect = NSRect(
                    x: minX,
                    y: minY,
                    width: maxX - minX,
                    height: maxY - minY
                )
                guard highlightRect.width > 0,
                      highlightRect.height > 0,
                      highlightRect.intersects(dirtyRect)
                else { return }

                let radius = min(2, highlightRect.height / 2)
                NSBezierPath(
                    roundedRect: highlightRect,
                    xRadius: radius,
                    yRadius: radius
                ).fill()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let checkboxTrackingArea {
            removeTrackingArea(checkboxTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        checkboxTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let newLocation = checkboxGeometry(at: point)?.match.markerRange.location
        if hoveredMarkerLocation != newLocation {
            hoveredMarkerLocation = newLocation
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredMarkerLocation != nil {
            hoveredMarkerLocation = nil
            needsDisplay = true
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in checkboxCursorRects() {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    func checkboxCursorRects() -> [NSRect] {
        checkboxGeometries().map(\.hitRect)
    }

    private func apply(
        _ plan: MarkdownTextEditPlan,
        selectionOverride: NSRange? = nil
    ) {
        window?.makeFirstResponder(self)
        breakUndoCoalescing()
        isApplyingMarkdownEditPlan = true
        insertText(plan.replacementString, replacementRange: plan.replacementRange)
        isApplyingMarkdownEditPlan = false
        breakUndoCoalescing()
        let sourceLength = (string as NSString).length
        let requestedSelection = selectionOverride ?? plan.resultingSelection
        let safeLocation = min(requestedSelection.location, sourceLength)
        let safeLength = min(
            requestedSelection.length,
            sourceLength - safeLocation
        )
        let resultingSelection = NSRange(location: safeLocation, length: safeLength)
        setSelectedRange(resultingSelection)
        scrollRangeToVisible(resultingSelection)
        refreshChecklistPresentation()
        editorController?.refreshSelectionState()
    }

    private func checkboxGeometries() -> [CheckboxGeometry] {
        guard let layoutManager, let textContainer else { return [] }
        let origin = textContainerOrigin
        let backingScale = max(
            window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2,
            1
        )
        func alignedToPixel(_ value: CGFloat) -> CGFloat {
            (value * backingScale).rounded() / backingScale
        }
        let rawSize = min(max(checklistFontSize * 0.9, 14), 20)
        let size = alignedToPixel(rawSize)
        let hitSize = max(size + 8, 24)
        let font = NSFont.monospacedSystemFont(
            ofSize: checklistFontSize,
            weight: .regular
        )

        return checklistMatches.compactMap { match in
            let prefixGlyphRange = layoutManager.glyphRange(
                forCharacterRange: match.prefixRange,
                actualCharacterRange: nil
            )
            let anchorCharacterRange = match.contentRange.length > 0
                ? NSRange(location: match.contentRange.location, length: 1)
                : NSRange(location: match.prefixRange.location, length: 1)
            let anchorGlyphRange = layoutManager.glyphRange(
                forCharacterRange: anchorCharacterRange,
                actualCharacterRange: nil
            )
            guard match.prefixRange.length > 0,
                  prefixGlyphRange.length > 0,
                  anchorGlyphRange.length > 0,
                  anchorGlyphRange.location < layoutManager.numberOfGlyphs
            else { return nil }

            let prefixRect = layoutManager.boundingRect(
                forGlyphRange: prefixGlyphRange,
                in: textContainer
            ).offsetBy(dx: origin.x, dy: origin.y)
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: anchorGlyphRange.location,
                effectiveRange: nil
            )
            let glyphLocation = layoutManager.location(
                forGlyphAt: anchorGlyphRange.location
            )
            let baselineY = origin.y + lineRect.minY + glyphLocation.y
            let visualCenterY = baselineY - font.capHeight / 2
            let boxX = alignedToPixel(prefixRect.maxX - size - 8)
            let boxY = alignedToPixel(visualCenterY - size / 2)
            let boxRect = NSRect(
                x: boxX,
                y: boxY,
                width: size,
                height: size
            )
            let hitRect = NSRect(
                x: boxRect.midX - hitSize / 2,
                y: boxRect.midY - hitSize / 2,
                width: hitSize,
                height: hitSize
            )
            return CheckboxGeometry(match: match, boxRect: boxRect, hitRect: hitRect)
        }
    }

    func managedImagePreviewRect(atUTF16Offset offset: Int) -> NSRect? {
        managedImageGeometries().first {
            $0.match.tokenRange.location == offset
        }?.previewRect
    }

    func managedImageResolvedAssetURL(atUTF16Offset offset: Int) -> URL? {
        guard let match = managedImageMatches.first(where: {
            $0.tokenRange.location == offset
        }) else { return nil }
        return managedImageURLsByDestination[match.markdownDestination]
    }

    private func managedImageGeometries() -> [ManagedImageGeometry] {
        guard let layoutManager, let textContainer else { return [] }
        let origin = textContainerOrigin
        return managedImageMatches.compactMap { match in
            guard match.tokenRange.length > 0 else { return nil }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: match.tokenRange,
                actualCharacterRange: nil
            )
            guard glyphRange.length > 0,
                  glyphRange.location < layoutManager.numberOfGlyphs
            else { return nil }
            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil
            )
            let glyphLocation = layoutManager.location(forGlyphAt: glyphRange.location)
            let layoutSize = managedImageLayoutSize(
                atUTF16Offset: match.tokenRange.location,
                in: textContainer
            )
            let previewRect = NSRect(
                x: origin.x + lineRect.minX + glyphLocation.x,
                y: origin.y + lineRect.minY + 6,
                width: layoutSize.width,
                height: max(1, layoutSize.height - 12)
            )
            let fileURL = managedImageURLsByDestination[match.markdownDestination]
            return ManagedImageGeometry(
                match: match,
                previewRect: previewRect,
                hitRect: previewRect.insetBy(dx: -2, dy: -2),
                fileURL: fileURL,
                preview: fileURL.flatMap { managedImagePreviews[$0] }
            )
        }
    }

    private func drawManagedImagePreview(_ geometry: ManagedImageGeometry) {
        let rect = geometry.previewRect
        if geometry.preview == nil,
           let fileURL = geometry.fileURL,
           let documentIdentity = imageConfiguration?.documentIdentity {
            requestManagedImagePreviewIfNeeded(
                fileURL,
                documentIdentity: documentIdentity
            )
        }
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()

        if let preview = geometry.preview {
            let imageSize = NSSize(
                width: CGFloat(preview.pixelWidth),
                height: CGFloat(preview.pixelHeight)
            )
            let scale = min(
                rect.width / max(imageSize.width, 1),
                rect.height / max(imageSize.height, 1)
            )
            let drawSize = NSSize(
                width: imageSize.width * scale,
                height: imageSize.height * scale
            )
            let drawRect = NSRect(
                x: rect.midX - drawSize.width / 2,
                y: rect.midY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            NSColor.windowBackgroundColor.setFill()
            rect.fill()
            preview.image.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        } else {
            NSColor.controlBackgroundColor.setFill()
            rect.fill()
            let symbol = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            let symbolSize = NSSize(width: 28, height: 28)
            symbol?.draw(
                in: NSRect(
                    x: rect.midX - symbolSize.width / 2,
                    y: rect.midY - symbolSize.height / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        completedTextColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func checkboxGeometry(at point: NSPoint) -> CheckboxGeometry? {
        checkboxGeometries()
            .filter { $0.hitRect.contains(point) }
            .min { lhs, rhs in
                let lhsX = lhs.boxRect.midX - point.x
                let lhsY = lhs.boxRect.midY - point.y
                let rhsX = rhs.boxRect.midX - point.x
                let rhsY = rhs.boxRect.midY - point.y
                let lhsDistance = lhsX * lhsX + lhsY * lhsY
                let rhsDistance = rhsX * rhsX + rhsY * rhsY
                return lhsDistance < rhsDistance
            }
    }

    private func drawCheckbox(
        in rect: NSRect,
        isChecked: Bool,
        isHovered: Bool
    ) {
        let cornerRadius = min(4, rect.width * 0.22)
        let boxPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

        if isChecked {
            successColor.setFill()
            boxPath.fill()
        } else {
            if isHovered {
                hoverBackgroundColor.withAlphaComponent(0.75).setFill()
                boxPath.fill()
                accentColor.setStroke()
            } else {
                completedTextColor.setStroke()
            }
            boxPath.lineWidth = 1.5
            boxPath.stroke()
        }

        guard isChecked else { return }
        let checkPath = NSBezierPath()
        checkPath.move(to: NSPoint(x: rect.minX + rect.width * 0.23, y: rect.midY))
        checkPath.line(to: NSPoint(x: rect.minX + rect.width * 0.43, y: rect.maxY - rect.height * 0.25))
        checkPath.line(to: NSPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.25))
        checkPath.lineWidth = max(1.8, rect.width * 0.12)
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkmarkColor.setStroke()
        checkPath.stroke()
    }

    private func selectedLogicalLineStarts() -> [Int] {
        let source = string as NSString
        let selection = selectedRange()
        guard selection.location != NSNotFound,
              selection.location <= source.length,
              selection.length <= source.length - selection.location
        else { return [] }

        let effectiveEnd = selection.length > 0
            ? NSMaxRange(selection) - 1
            : selection.location
        var firstStart = 0
        var firstEnd = 0
        var firstContentsEnd = 0
        source.getLineStart(
            &firstStart,
            end: &firstEnd,
            contentsEnd: &firstContentsEnd,
            for: NSRange(location: selection.location, length: 0)
        )
        var lastStart = 0
        var lastEnd = 0
        var lastContentsEnd = 0
        source.getLineStart(
            &lastStart,
            end: &lastEnd,
            contentsEnd: &lastContentsEnd,
            for: NSRange(location: effectiveEnd, length: 0)
        )

        var starts: [Int] = []
        var location = firstStart
        while location <= lastStart {
            starts.append(location)
            if location == lastStart { break }
            var start = 0
            var end = 0
            var contentsEnd = 0
            source.getLineStart(
                &start,
                end: &end,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )
            guard end > location else { break }
            location = end
        }
        return starts
    }

    private func selectionRangeSnapshot() -> NSRange? {
        guard selectedRanges.count == 1 else { return nil }
        let range = selectedRange()
        let sourceLength = (string as NSString).length
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length > 0,
              range.location <= sourceLength,
              range.length <= sourceLength - range.location
        else { return nil }
        return range
    }
}
