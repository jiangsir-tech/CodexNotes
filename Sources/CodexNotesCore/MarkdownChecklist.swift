import Foundation

public struct MarkdownDisplayLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let rawText: String
    public let displayText: String
    public let isCheckbox: Bool
    public let isChecked: Bool

    public init(
        id: Int,
        rawText: String,
        displayText: String,
        isCheckbox: Bool,
        isChecked: Bool
    ) {
        self.id = id
        self.rawText = rawText
        self.displayText = displayText
        self.isCheckbox = isCheckbox
        self.isChecked = isChecked
    }
}

public struct MarkdownTextEditPlan: Equatable, Sendable {
    public let replacementRange: NSRange
    public let replacementString: String
    public let resultingSelection: NSRange

    public init(
        replacementRange: NSRange,
        replacementString: String,
        resultingSelection: NSRange
    ) {
        self.replacementRange = replacementRange
        self.replacementString = replacementString
        self.resultingSelection = resultingSelection
    }

    public func applying(to text: String) -> String? {
        let source = text as NSString
        guard replacementRange.location != NSNotFound,
              replacementRange.location >= 0,
              replacementRange.length >= 0,
              replacementRange.location <= source.length,
              replacementRange.length <= source.length - replacementRange.location
        else { return nil }
        return source.replacingCharacters(in: replacementRange, with: replacementString)
    }
}

public struct MarkdownCheckboxMatch: Equatable, Sendable {
    public let lineRange: NSRange
    public let prefixRange: NSRange
    public let tokenRange: NSRange
    public let markerRange: NSRange
    public let contentRange: NSRange
    public let isChecked: Bool

    public init(
        lineRange: NSRange,
        prefixRange: NSRange,
        tokenRange: NSRange,
        markerRange: NSRange,
        contentRange: NSRange,
        isChecked: Bool
    ) {
        self.lineRange = lineRange
        self.prefixRange = prefixRange
        self.tokenRange = tokenRange
        self.markerRange = markerRange
        self.contentRange = contentRange
        self.isChecked = isChecked
    }
}

public struct MarkdownChecklistProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}

public enum MarkdownReturnAction: Equatable, Sendable {
    case insertNextTodo
    case exitTodoList
}

public enum MarkdownTodoCycleState: Equatable, Sendable {
    case plain
    case incomplete
    case complete
}

public struct MarkdownReturnPlan: Equatable, Sendable {
    public let action: MarkdownReturnAction
    public let edit: MarkdownTextEditPlan

    public init(action: MarkdownReturnAction, edit: MarkdownTextEditPlan) {
        self.action = action
        self.edit = edit
    }
}

public enum MarkdownChecklist {
    private static let checkboxPattern =
        #"^([ \t]*)([-*+])([ \t]+)(\[([ xX])\])(?:([ \t]+)|$)"#
    private static let bulletPattern = #"^([ \t]*)([-*+])([ \t]+)"#
    private static let checkboxRegex = try! NSRegularExpression(pattern: checkboxPattern)
    private static let bulletRegex = try! NSRegularExpression(pattern: bulletPattern)

    public static func lines(in text: String) -> [MarkdownDisplayLine] {
        let source = text as NSString
        let matchesByLocation = Dictionary(
            uniqueKeysWithValues: checkboxMatches(in: text).map { ($0.lineRange.location, $0) }
        )

        return lineInfos(in: source).enumerated().map { index, line in
            let rawText = source.substring(with: line.lineRange)
            guard let match = matchesByLocation[line.lineRange.location] else {
                return MarkdownDisplayLine(
                    id: index,
                    rawText: rawText,
                    displayText: rawText,
                    isCheckbox: false,
                    isChecked: false
                )
            }

            return MarkdownDisplayLine(
                id: index,
                rawText: rawText,
                displayText: source.substring(with: match.contentRange),
                isCheckbox: true,
                isChecked: match.isChecked
            )
        }
    }

    public static func checkboxMatches(in text: String) -> [MarkdownCheckboxMatch] {
        let source = text as NSString
        return lineInfos(in: source).compactMap { checkboxMatch(in: $0, source: source) }
    }

    public static func toggleTodoFormat(
        in text: String,
        selection: NSRange
    ) -> MarkdownTextEditPlan? {
        let source = text as NSString
        guard let selectedLines = selectedLineInfos(in: source, selection: selection) else {
            return nil
        }

        let matches = checkboxMatches(in: text)
        let matchesByLocation = Dictionary(
            uniqueKeysWithValues: matches.map { ($0.lineRange.location, $0) }
        )
        let isMultilineSelection = selectedLines.count > 1 || selection.length > 0
        let candidateLines = selectedLines.filter { line in
            if matchesByLocation[line.lineRange.location] != nil { return true }
            if !isMultilineSelection { return true }
            return !source.substring(with: line.lineRange)
                .trimmingCharacters(in: .whitespaces)
                .isEmpty
        }
        guard !candidateLines.isEmpty else { return nil }

        let shouldRemoveTodo = candidateLines.allSatisfy {
            matchesByLocation[$0.lineRange.location] != nil
        }
        var replacements: [Replacement] = []

        for line in candidateLines {
            if let match = matchesByLocation[line.lineRange.location] {
                if shouldRemoveTodo {
                    replacements.append(
                        Replacement(range: match.prefixRange, string: "")
                    )
                }
                continue
            }

            if let bullet = ordinaryBulletMatch(in: line, source: source) {
                replacements.append(
                    Replacement(range: bullet, string: "- [ ] ")
                )
            } else {
                let insertionLocation = line.lineRange.location
                    + leadingWhitespaceLength(in: line, source: source)
                replacements.append(
                    Replacement(
                        range: NSRange(location: insertionLocation, length: 0),
                        string: "- [ ] "
                    )
                )
            }
        }

        return editPlan(
            in: source,
            replacements: replacements,
            originalSelection: selection
        )
    }

    /// Cycles the current line through ordinary text, an unchecked todo, and a
    /// checked todo. A selection is accepted only when it belongs to one line;
    /// multi-line selections are intentionally left unchanged.
    public static func cycleTodoState(
        in text: String,
        selection: NSRange
    ) -> MarkdownTextEditPlan? {
        let source = text as NSString
        guard let selectedLines = selectedLineInfos(in: source, selection: selection),
              selectedLines.count == 1,
              let line = selectedLines.first
        else { return nil }

        let replacement: Replacement
        if let match = checkboxMatch(in: line, source: source) {
            replacement = match.isChecked
                ? Replacement(range: match.prefixRange, string: "")
                : Replacement(range: match.markerRange, string: "x")
        } else if let bullet = ordinaryBulletMatch(in: line, source: source) {
            replacement = Replacement(range: bullet, string: "- [ ] ")
        } else {
            replacement = Replacement(
                range: NSRange(
                    location: line.lineRange.location
                        + leadingWhitespaceLength(in: line, source: source),
                    length: 0
                ),
                string: "- [ ] "
            )
        }

        return editPlan(
            in: source,
            replacements: [replacement],
            originalSelection: selection
        )
    }

    public static func todoCycleState(
        in text: String,
        selection: NSRange
    ) -> MarkdownTodoCycleState? {
        let source = text as NSString
        guard let selectedLines = selectedLineInfos(in: source, selection: selection),
              selectedLines.count == 1,
              let line = selectedLines.first
        else { return nil }

        guard let match = checkboxMatch(in: line, source: source) else {
            return .plain
        }
        return match.isChecked ? .complete : .incomplete
    }

    public static func toggleCheckbox(
        in text: String,
        clickUTF16Offset: Int
    ) -> MarkdownTextEditPlan? {
        let source = text as NSString
        guard clickUTF16Offset >= 0, clickUTF16Offset <= source.length,
              let match = checkboxMatches(in: text).first(where: {
                  clickUTF16Offset >= $0.tokenRange.location
                      && clickUTF16Offset < NSMaxRange($0.tokenRange)
              })
        else { return nil }

        return MarkdownTextEditPlan(
            replacementRange: match.markerRange,
            replacementString: match.isChecked ? " " : "x",
            resultingSelection: NSRange(
                location: match.markerRange.location + 1,
                length: 0
            )
        )
    }

    public static func checkedContentRanges(in text: String) -> [NSRange] {
        checkboxMatches(in: text)
            .filter(\.isChecked)
            .map(\.contentRange)
            .filter { $0.length > 0 }
    }

    public static func progress(in text: String) -> MarkdownChecklistProgress {
        let matches = checkboxMatches(in: text)
        return MarkdownChecklistProgress(
            completed: matches.filter(\.isChecked).count,
            total: matches.count
        )
    }

    /// Converts the current todo into ordinary text when Backspace is pressed
    /// at its visually collapsed prefix or the start of its content. This mirrors
    /// native outline editors while preserving indentation and content.
    public static func deleteBackwardPlan(
        in text: String,
        selection: NSRange
    ) -> MarkdownTextEditPlan? {
        let source = text as NSString
        guard selection.length == 0,
              selection.location >= 0,
              selection.location <= source.length,
              let line = lineInfo(containing: selection.location, in: source),
              let match = checkboxMatch(in: line, source: source)
        else { return nil }

        guard selection.location >= match.prefixRange.location,
              selection.location <= match.contentRange.location
        else { return nil }

        return MarkdownTextEditPlan(
            replacementRange: match.prefixRange,
            replacementString: "",
            resultingSelection: NSRange(
                location: match.prefixRange.location,
                length: 0
            )
        )
    }

    public static func returnPlan(
        in text: String,
        selection: NSRange
    ) -> MarkdownReturnPlan? {
        let source = text as NSString
        guard selection.length == 0,
              selection.location >= 0,
              selection.location <= source.length,
              let line = selectedLineInfos(in: source, selection: selection)?.first,
              let match = checkboxMatch(in: line, source: source),
              selection.location >= match.contentRange.location,
              selection.location <= NSMaxRange(match.contentRange)
        else { return nil }

        let content = source.substring(with: match.contentRange)
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            return MarkdownReturnPlan(
                action: .exitTodoList,
                edit: MarkdownTextEditPlan(
                    replacementRange: match.prefixRange,
                    replacementString: "",
                    resultingSelection: NSRange(
                        location: match.prefixRange.location,
                        length: 0
                    )
                )
            )
        }

        let indentationRange = NSRange(
            location: match.lineRange.location,
            length: match.prefixRange.location - match.lineRange.location
        )
        let indentation = source.substring(with: indentationRange)
        let insertionSelection: NSRange
        let contentEnd = NSMaxRange(match.contentRange)
        if selection.location < contentEnd {
            let suffix = source.substring(
                with: NSRange(
                    location: selection.location,
                    length: contentEnd - selection.location
                )
            )
            insertionSelection = suffix.allSatisfy({ $0 == " " || $0 == "\t" })
                ? NSRange(location: contentEnd, length: 0)
                : selection
        } else {
            insertionSelection = selection
        }
        let replacement = preferredNewline(for: line, in: source)
            + indentation
            + "- [ ] "
        return MarkdownReturnPlan(
            action: .insertNextTodo,
            edit: MarkdownTextEditPlan(
                replacementRange: insertionSelection,
                replacementString: replacement,
                resultingSelection: NSRange(
                    location: insertionSelection.location + (replacement as NSString).length,
                    length: 0
                )
            )
        )
    }

    public static func toggle(line index: Int, in text: String) -> String {
        let source = text as NSString
        let lines = lineInfos(in: source)
        guard lines.indices.contains(index),
              let match = checkboxMatches(in: text).first(where: {
                  $0.lineRange.location == lines[index].lineRange.location
              })
        else { return text }
        let plan = MarkdownTextEditPlan(
            replacementRange: match.markerRange,
            replacementString: match.isChecked ? " " : "x",
            resultingSelection: NSRange(location: match.markerRange.location + 1, length: 0)
        )
        return plan.applying(to: text) ?? text
    }

    public static func checkboxCount(in text: String) -> Int {
        progress(in: text).total
    }

    private struct LineInfo {
        let lineRange: NSRange
        let fullRange: NSRange
    }

    private struct Replacement {
        let range: NSRange
        let string: String
    }

    private static func lineInfos(in source: NSString) -> [LineInfo] {
        guard source.length > 0 else {
            return [
                LineInfo(
                    lineRange: NSRange(location: 0, length: 0),
                    fullRange: NSRange(location: 0, length: 0)
                )
            ]
        }

        var result: [LineInfo] = []
        var location = 0
        while location < source.length {
            var start = 0
            var end = 0
            var contentsEnd = 0
            source.getLineStart(
                &start,
                end: &end,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )
            result.append(
                LineInfo(
                    lineRange: NSRange(location: start, length: contentsEnd - start),
                    fullRange: NSRange(location: start, length: end - start)
                )
            )
            guard end > location else { break }
            location = end
        }

        if let last = result.last,
           NSMaxRange(last.fullRange) == source.length,
           NSMaxRange(last.lineRange) < source.length
        {
            result.append(
                LineInfo(
                    lineRange: NSRange(location: source.length, length: 0),
                    fullRange: NSRange(location: source.length, length: 0)
                )
            )
        }
        return result
    }

    private static func lineInfo(
        containing location: Int,
        in source: NSString
    ) -> LineInfo? {
        guard location >= 0, location <= source.length else { return nil }
        guard source.length > 0 else {
            return LineInfo(
                lineRange: NSRange(location: 0, length: 0),
                fullRange: NSRange(location: 0, length: 0)
            )
        }

        var start = 0
        var end = 0
        var contentsEnd = 0
        source.getLineStart(
            &start,
            end: &end,
            contentsEnd: &contentsEnd,
            for: NSRange(location: location, length: 0)
        )
        return LineInfo(
            lineRange: NSRange(location: start, length: contentsEnd - start),
            fullRange: NSRange(location: start, length: end - start)
        )
    }

    private static func selectedLineInfos(
        in source: NSString,
        selection: NSRange
    ) -> [LineInfo]? {
        guard selection.location != NSNotFound,
              selection.location >= 0,
              selection.length >= 0,
              selection.location <= source.length,
              selection.length <= source.length - selection.location
        else { return nil }

        let lines = lineInfos(in: source)
        let endLocation = selection.length > 0
            ? NSMaxRange(selection) - 1
            : selection.location
        guard let firstIndex = lineIndex(containing: selection.location, in: lines, source: source),
              let lastIndex = lineIndex(containing: endLocation, in: lines, source: source)
        else { return nil }
        return Array(lines[min(firstIndex, lastIndex)...max(firstIndex, lastIndex)])
    }

    private static func lineIndex(
        containing location: Int,
        in lines: [LineInfo],
        source: NSString
    ) -> Int? {
        if location == source.length { return lines.indices.last }
        return lines.firstIndex { line in
            location >= line.fullRange.location && location < NSMaxRange(line.fullRange)
        }
    }

    private static func checkboxMatch(
        in line: LineInfo,
        source: NSString
    ) -> MarkdownCheckboxMatch? {
        let text = source.substring(with: line.lineRange)
        guard let match = checkboxRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        )
        else { return nil }

        let indentLength = match.range(at: 1).length
        let tokenLocalRange = match.range(at: 4)
        let markerLocalRange = match.range(at: 5)
        let contentStart = match.range.location + match.range.length
        let absoluteContentStart = line.lineRange.location + contentStart
        let marker = (text as NSString).substring(with: markerLocalRange)
        return MarkdownCheckboxMatch(
            lineRange: line.lineRange,
            prefixRange: NSRange(
                location: line.lineRange.location + indentLength,
                length: contentStart - indentLength
            ),
            tokenRange: NSRange(
                location: line.lineRange.location + tokenLocalRange.location,
                length: tokenLocalRange.length
            ),
            markerRange: NSRange(
                location: line.lineRange.location + markerLocalRange.location,
                length: markerLocalRange.length
            ),
            contentRange: NSRange(
                location: absoluteContentStart,
                length: NSMaxRange(line.lineRange) - absoluteContentStart
            ),
            isChecked: marker.lowercased() == "x"
        )
    }

    private static func ordinaryBulletMatch(
        in line: LineInfo,
        source: NSString
    ) -> NSRange? {
        let text = source.substring(with: line.lineRange)
        guard let match = bulletRegex.firstMatch(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        )
        else { return nil }

        let indentLength = match.range(at: 1).length
        return NSRange(
            location: line.lineRange.location + indentLength,
            length: match.range.length - indentLength
        )
    }

    private static func leadingWhitespaceLength(
        in line: LineInfo,
        source: NSString
    ) -> Int {
        let text = source.substring(with: line.lineRange) as NSString
        var length = 0
        while length < text.length {
            let character = text.character(at: length)
            guard character == 0x20 || character == 0x09 else { break }
            length += 1
        }
        return length
    }

    private static func editPlan(
        in source: NSString,
        replacements: [Replacement],
        originalSelection: NSRange
    ) -> MarkdownTextEditPlan? {
        guard !replacements.isEmpty,
              let minimumLocation = replacements.map(\.range.location).min(),
              let maximumEnd = replacements.map({ NSMaxRange($0.range) }).max()
        else { return nil }

        let replacementRange = NSRange(
            location: minimumLocation,
            length: maximumEnd - minimumLocation
        )
        let mutable = NSMutableString(string: source.substring(with: replacementRange))
        for replacement in replacements.sorted(by: {
            if $0.range.location == $1.range.location {
                return $0.range.length > $1.range.length
            }
            return $0.range.location > $1.range.location
        }) {
            let localRange = NSRange(
                location: replacement.range.location - replacementRange.location,
                length: replacement.range.length
            )
            mutable.replaceCharacters(in: localRange, with: replacement.string)
        }

        let sortedReplacements = replacements.sorted { $0.range.location < $1.range.location }
        let start = map(position: originalSelection.location, through: sortedReplacements)
        let end = map(position: NSMaxRange(originalSelection), through: sortedReplacements)
        return MarkdownTextEditPlan(
            replacementRange: replacementRange,
            replacementString: mutable as String,
            resultingSelection: NSRange(location: start, length: max(0, end - start))
        )
    }

    private static func map(
        position: Int,
        through replacements: [Replacement]
    ) -> Int {
        var delta = 0
        for replacement in replacements {
            let replacementLength = (replacement.string as NSString).length
            if replacement.range.length == 0 {
                if position >= replacement.range.location {
                    delta += replacementLength
                }
                continue
            }

            let end = NSMaxRange(replacement.range)
            if position >= end {
                delta += replacementLength - replacement.range.length
            } else if position > replacement.range.location {
                let relative = position - replacement.range.location
                return replacement.range.location + delta + min(relative, replacementLength)
            }
        }
        return position + delta
    }

    private static func preferredNewline(for line: LineInfo, in source: NSString) -> String {
        let terminatorRange = NSRange(
            location: NSMaxRange(line.lineRange),
            length: NSMaxRange(line.fullRange) - NSMaxRange(line.lineRange)
        )
        if terminatorRange.length > 0 {
            return source.substring(with: terminatorRange)
        }

        if let regex = try? NSRegularExpression(pattern: #"\r\n|\r|\n"#),
           let match = regex.firstMatch(
               in: source as String,
               range: NSRange(location: 0, length: source.length)
           )
        {
            return source.substring(with: match.range)
        }
        return "\n"
    }
}
