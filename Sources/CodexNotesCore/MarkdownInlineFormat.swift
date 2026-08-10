import Foundation

public enum MarkdownInlineFormat: String, CaseIterable, Equatable, Sendable {
    case bold
    case highlight

    public var delimiter: String {
        switch self {
        case .bold:
            return "**"
        case .highlight:
            return "=="
        }
    }

    public func selectionState(
        in text: String,
        selection: NSRange
    ) -> MarkdownInlineFormatSelectionState {
        MarkdownInlineFormatScanner.selectionAnalysis(
            in: text,
            selection: selection,
            format: self
        ).state
    }

    public func togglePlan(
        in text: String,
        selection: NSRange
    ) -> MarkdownTextEditPlan? {
        let analysis = MarkdownInlineFormatScanner.selectionAnalysis(
            in: text,
            selection: selection,
            format: self
        )
        guard analysis.state != .unavailable,
              let targetRange = analysis.targetRange
        else { return nil }

        let source = text as NSString
        if let activeMatch = analysis.activeMatch {
            let replacement = source.substring(with: activeMatch.contentRange)
            let resultingSelection: NSRange
            if targetRange == activeMatch.tokenRange {
                resultingSelection = NSRange(
                    location: activeMatch.tokenRange.location,
                    length: activeMatch.contentRange.length
                )
            } else {
                resultingSelection = NSRange(
                    location: targetRange.location - delimiter.utf16.count,
                    length: targetRange.length
                )
            }
            return MarkdownTextEditPlan(
                replacementRange: activeMatch.tokenRange,
                replacementString: replacement,
                resultingSelection: resultingSelection
            )
        }

        let selectedText = source.substring(with: targetRange)
        let allMatches = MarkdownInlineFormatScanner.matches(in: text)
        let leftNeighbor = allMatches.first {
            $0.format == self && NSMaxRange($0.tokenRange) == targetRange.location
        }
        let rightNeighbor = allMatches.first {
            $0.format == self && $0.tokenRange.location == NSMaxRange(targetRange)
        }
        if leftNeighbor != nil || rightNeighbor != nil {
            let replacementStart = leftNeighbor?.tokenRange.location ?? targetRange.location
            let replacementEnd = rightNeighbor.map { NSMaxRange($0.tokenRange) }
                ?? NSMaxRange(targetRange)
            let leftContent = leftNeighbor.map {
                source.substring(with: $0.contentRange)
            } ?? ""
            let rightContent = rightNeighbor.map {
                source.substring(with: $0.contentRange)
            } ?? ""
            return MarkdownTextEditPlan(
                replacementRange: NSRange(
                    location: replacementStart,
                    length: replacementEnd - replacementStart
                ),
                replacementString: delimiter
                    + leftContent
                    + selectedText
                    + rightContent
                    + delimiter,
                resultingSelection: NSRange(
                    location: replacementStart
                        + delimiter.utf16.count
                        + leftContent.utf16.count,
                    length: targetRange.length
                )
            )
        }
        return MarkdownTextEditPlan(
            replacementRange: targetRange,
            replacementString: delimiter + selectedText + delimiter,
            resultingSelection: NSRange(
                location: targetRange.location + delimiter.utf16.count,
                length: targetRange.length
            )
        )
    }

    public static func matches(in markdown: String) -> [MarkdownInlineFormatMatch] {
        MarkdownInlineFormatScanner.matches(in: markdown)
    }
}

public enum MarkdownInlineFormatSelectionState: Equatable, Sendable {
    case inactive
    case active
    case unavailable
}

public struct MarkdownInlineFormatMatch: Equatable, Sendable {
    public let format: MarkdownInlineFormat
    public let tokenRange: NSRange
    public let openingDelimiterRange: NSRange
    public let contentRange: NSRange
    public let closingDelimiterRange: NSRange

    public init(
        format: MarkdownInlineFormat,
        tokenRange: NSRange,
        openingDelimiterRange: NSRange,
        contentRange: NSRange,
        closingDelimiterRange: NSRange
    ) {
        self.format = format
        self.tokenRange = tokenRange
        self.openingDelimiterRange = openingDelimiterRange
        self.contentRange = contentRange
        self.closingDelimiterRange = closingDelimiterRange
    }
}

private enum MarkdownInlineFormatScanner {
    private struct OpeningDelimiter {
        let format: MarkdownInlineFormat
        let range: NSRange
    }

    struct SelectionAnalysis {
        let state: MarkdownInlineFormatSelectionState
        let targetRange: NSRange?
        let activeMatch: MarkdownInlineFormatMatch?
    }

    private static let imageExpression = try! NSRegularExpression(
        pattern: #"!\[[^\]\r\n]*\]\([^\)\r\n]*\)"#
    )

    static func matches(in markdown: String) -> [MarkdownInlineFormatMatch] {
        let source = markdown as NSString
        let code = codeRanges(in: source)
        let images = imageRanges(in: markdown, source: source)
        let protected = code
            + images
            + markdownLinkProtectedRanges(
                in: source,
                excluding: code + images
            )
        let delimiterLength = 2
        var stack: [OpeningDelimiter] = []
        var matches: [MarkdownInlineFormatMatch] = []
        var location = 0

        while location + delimiterLength <= source.length {
            if let range = protected.first(where: { NSLocationInRange(location, $0) }) {
                location = max(location + 1, NSMaxRange(range))
                continue
            }

            // Two independently formatted, adjacent spans naturally meet as
            // four identical delimiter characters: `**a****b**`. Treat the
            // first pair as the current close and the second as the next open.
            // Runs at the beginning/end (such as `****text****`) remain
            // deliberately unsupported and visible to the user.
            if let format = adjacentDelimiterBoundaryFormat(
                at: location,
                in: source
            ),
               stack.last?.format == format,
               let opening = stack.popLast()
            {
                let closingRange = NSRange(location: location, length: delimiterLength)
                let contentRange = NSRange(
                    location: NSMaxRange(opening.range),
                    length: closingRange.location - NSMaxRange(opening.range)
                )
                if contentRange.length > 0,
                   !containsLineBreak(contentRange, in: source) {
                    matches.append(
                        MarkdownInlineFormatMatch(
                            format: format,
                            tokenRange: NSRange(
                                location: opening.range.location,
                                length: NSMaxRange(closingRange) - opening.range.location
                            ),
                            openingDelimiterRange: opening.range,
                            contentRange: contentRange,
                            closingDelimiterRange: closingRange
                        )
                    )
                }
                stack.append(
                    OpeningDelimiter(
                        format: format,
                        range: NSRange(
                            location: location + delimiterLength,
                            length: delimiterLength
                        )
                    )
                )
                location += delimiterLength * 2
                continue
            }

            guard let format = format(at: location, in: source),
                  !isEscaped(location, in: source)
            else {
                location += 1
                continue
            }

            let delimiterRange = NSRange(location: location, length: delimiterLength)
            let canOpen = hasNonWhitespaceCharacter(
                at: NSMaxRange(delimiterRange),
                in: source
            )
            let canClose = hasNonWhitespaceCharacter(
                at: delimiterRange.location - 1,
                in: source
            )

            if stack.last?.format == format, canClose,
               let opening = stack.popLast() {
                let contentRange = NSRange(
                    location: NSMaxRange(opening.range),
                    length: delimiterRange.location - NSMaxRange(opening.range)
                )
                if contentRange.length > 0,
                   !containsLineBreak(contentRange, in: source) {
                    matches.append(
                        MarkdownInlineFormatMatch(
                            format: format,
                            tokenRange: NSRange(
                                location: opening.range.location,
                                length: NSMaxRange(delimiterRange) - opening.range.location
                            ),
                            openingDelimiterRange: opening.range,
                            contentRange: contentRange,
                            closingDelimiterRange: delimiterRange
                        )
                    )
                }
            } else if canOpen {
                stack.append(OpeningDelimiter(format: format, range: delimiterRange))
            }
            location += delimiterLength
        }

        let recognizedDelimiterRanges = matches.flatMap {
            [$0.openingDelimiterRange, $0.closingDelimiterRange]
        }
        let unsupportedDelimiterRanges = delimiterRanges(in: source).filter {
            !isEntirelyCovered($0, by: recognizedDelimiterRanges)
        }
        return matches.filter { match in
            !unsupportedDelimiterRanges.contains {
                intersects(match.tokenRange, $0)
            }
        }.sorted {
            if $0.tokenRange.location == $1.tokenRange.location {
                return $0.tokenRange.length > $1.tokenRange.length
            }
            return $0.tokenRange.location < $1.tokenRange.location
        }
    }

    static func selectionAnalysis(
        in text: String,
        selection: NSRange,
        format: MarkdownInlineFormat
    ) -> SelectionAnalysis {
        let source = text as NSString
        guard isValidNonempty(selection, in: source),
              source.rangeOfComposedCharacterSequences(for: selection) == selection,
              let targetRange = whitespaceTrimmedRange(selection, in: source),
              targetRange.length > 0,
              !containsLineBreak(targetRange, in: source)
        else {
            return SelectionAnalysis(
                state: .unavailable,
                targetRange: nil,
                activeMatch: nil
            )
        }

        let protected = protectedSelectionRanges(in: text, source: source)
        guard !protected.contains(where: { intersects(targetRange, $0) }) else {
            return SelectionAnalysis(
                state: .unavailable,
                targetRange: targetRange,
                activeMatch: nil
            )
        }

        let matches = matches(in: text)
        let recognizedDelimiterRanges = matches.flatMap {
            [$0.openingDelimiterRange, $0.closingDelimiterRange]
        }
        let targetLineRange = source.lineRange(for: targetRange)
        for delimiterRange in delimiterRanges(in: source)
        where intersects(targetLineRange, delimiterRange) {
            let belongsToProtectedSyntax = protected.contains {
                contains($0, delimiterRange)
            }
            guard belongsToProtectedSyntax
                    || isEntirelyCovered(
                        delimiterRange,
                        by: recognizedDelimiterRanges
                    )
            else {
                return SelectionAnalysis(
                    state: .unavailable,
                    targetRange: targetRange,
                    activeMatch: nil
                )
            }
        }

        if let active = matches.first(where: {
            $0.format == format
                && selectionRepresentsVisibleContent(
                    targetRange,
                    of: $0,
                    allMatches: matches,
                    source: source
                )
        }) {
            return SelectionAnalysis(
                state: .active,
                targetRange: targetRange,
                activeMatch: active
            )
        }

        for match in matches {
            if match.format == format {
                if intersects(targetRange, match.tokenRange)
                    || NSLocationInRange(targetRange.location, match.contentRange)
                    || (targetRange.location == NSMaxRange(match.contentRange)
                        && targetRange.length > 0)
                {
                    return SelectionAnalysis(
                        state: .unavailable,
                        targetRange: targetRange,
                        activeMatch: nil
                    )
                }
                continue
            }

            let relationIsSafe = !intersects(targetRange, match.tokenRange)
                || contains(targetRange, match.tokenRange)
                || contains(match.contentRange, targetRange)
            if !relationIsSafe {
                return SelectionAnalysis(
                    state: .unavailable,
                    targetRange: targetRange,
                    activeMatch: nil
                )
            }
        }

        return SelectionAnalysis(
            state: .inactive,
            targetRange: targetRange,
            activeMatch: nil
        )
    }

    private static func selectionRepresentsVisibleContent(
        _ selection: NSRange,
        of match: MarkdownInlineFormatMatch,
        allMatches: [MarkdownInlineFormatMatch],
        source: NSString
    ) -> Bool {
        if selection == match.tokenRange || selection == match.contentRange {
            return true
        }
        guard contains(match.contentRange, selection) else { return false }

        let nestedDelimiterRanges = allMatches
            .filter {
                $0.tokenRange != match.tokenRange
                    && contains(match.contentRange, $0.tokenRange)
            }
            .flatMap { [$0.openingDelimiterRange, $0.closingDelimiterRange] }
        let prefix = NSRange(
            location: match.contentRange.location,
            length: selection.location - match.contentRange.location
        )
        let suffix = NSRange(
            location: NSMaxRange(selection),
            length: NSMaxRange(match.contentRange) - NSMaxRange(selection)
        )
        return isFullyCovered(prefix, by: nestedDelimiterRanges, source: source)
            && isFullyCovered(suffix, by: nestedDelimiterRanges, source: source)
    }

    private static func isFullyCovered(
        _ range: NSRange,
        by allowedRanges: [NSRange],
        source: NSString
    ) -> Bool {
        guard range.length > 0 else { return true }
        var location = range.location
        while location < NSMaxRange(range) {
            if let allowed = allowedRanges.first(where: { NSLocationInRange(location, $0) }) {
                location = min(NSMaxRange(range), NSMaxRange(allowed))
                continue
            }
            let character = source.character(at: location)
            guard isHorizontalWhitespace(character) else { return false }
            location += 1
        }
        return true
    }

    private static func delimiterRanges(in source: NSString) -> [NSRange] {
        guard source.length >= 2 else { return [] }
        var result: [NSRange] = []
        var location = 0
        while location < source.length {
            let character = source.character(at: location)
            guard character == 0x2A || character == 0x3D,
                  !isEscaped(location, in: source)
            else {
                location += 1
                continue
            }
            var end = location + 1
            while end < source.length, source.character(at: end) == character {
                end += 1
            }
            if end - location >= 2 {
                result.append(NSRange(location: location, length: end - location))
            }
            location = end
        }
        return result
    }

    private static func adjacentDelimiterBoundaryFormat(
        at location: Int,
        in source: NSString
    ) -> MarkdownInlineFormat? {
        let runLength = 4
        guard location > 0,
              location + runLength < source.length,
              !isEscaped(location, in: source)
        else { return nil }

        let character = source.character(at: location)
        let format: MarkdownInlineFormat
        switch character {
        case 0x2A: // *
            format = .bold
        case 0x3D: // =
            format = .highlight
        default:
            return nil
        }
        guard source.character(at: location - 1) != character,
              source.character(at: location + runLength) != character,
              (0..<runLength).allSatisfy({
                  source.character(at: location + $0) == character
              }),
              hasNonWhitespaceCharacter(at: location - 1, in: source),
              hasNonWhitespaceCharacter(at: location + runLength, in: source)
        else { return nil }
        return format
    }

    private static func isEntirelyCovered(
        _ range: NSRange,
        by coveringRanges: [NSRange]
    ) -> Bool {
        guard range.length > 0 else { return true }
        var location = range.location
        while location < NSMaxRange(range) {
            guard let covering = coveringRanges.first(where: {
                NSLocationInRange(location, $0)
            }) else { return false }
            location = min(NSMaxRange(range), NSMaxRange(covering))
        }
        return true
    }

    private static func protectedSelectionRanges(
        in text: String,
        source: NSString
    ) -> [NSRange] {
        let code = codeRanges(in: source)
        let images = imageRanges(in: text, source: source)
        return code
            + images
            + markdownLinkProtectedRanges(
                in: source,
                excluding: code + images
            )
            + MarkdownChecklist.checkboxMatches(in: text).map(\.prefixRange)
    }

    private static func codeRanges(in source: NSString) -> [NSRange] {
        let fenced = fencedCodeRanges(in: source)
        return fenced + inlineCodeRanges(in: source, excluding: fenced)
    }

    private static func fencedCodeRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        var opening: (location: Int, marker: unichar, length: Int)?

        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            if let fence = fenceMarker(in: lineRange, source: source) {
                if let current = opening {
                    if fence.marker == current.marker,
                       fence.length >= current.length,
                       fence.isClosing {
                        ranges.append(
                            NSRange(
                                location: current.location,
                                length: NSMaxRange(lineRange) - current.location
                            )
                        )
                        opening = nil
                    }
                } else {
                    opening = (lineRange.location, fence.marker, fence.length)
                }
            }
            location = NSMaxRange(lineRange)
        }

        if let opening {
            ranges.append(
                NSRange(
                    location: opening.location,
                    length: source.length - opening.location
                )
            )
        }
        return ranges
    }

    private static func fenceMarker(
        in lineRange: NSRange,
        source: NSString
    ) -> (marker: unichar, length: Int, isClosing: Bool)? {
        let contentsRange = lineContentsRange(lineRange, source: source)
        var location = contentsRange.location
        var spaces = 0
        while location < NSMaxRange(contentsRange), source.character(at: location) == 0x20,
              spaces < 4 {
            spaces += 1
            location += 1
        }
        guard spaces <= 3, location < NSMaxRange(contentsRange) else { return nil }
        let marker = source.character(at: location)
        guard marker == 0x60 || marker == 0x7E else { return nil }
        let start = location
        while location < NSMaxRange(contentsRange), source.character(at: location) == marker {
            location += 1
        }
        let length = location - start
        guard length >= 3 else { return nil }
        let remainder = NSRange(location: location, length: NSMaxRange(contentsRange) - location)
        let isClosing = remainder.length == 0
            || source.substring(with: remainder).trimmingCharacters(in: .whitespaces).isEmpty
        return (marker, length, isClosing)
    }

    private static func inlineCodeRanges(
        in source: NSString,
        excluding excludedRanges: [NSRange]
    ) -> [NSRange] {
        var result: [NSRange] = []
        var location = 0
        while location < source.length {
            if let excluded = excludedRanges.first(where: { NSLocationInRange(location, $0) }) {
                location = NSMaxRange(excluded)
                continue
            }
            guard source.character(at: location) == 0x60 else {
                location += 1
                continue
            }

            let opening = backtickRun(at: location, in: source)
            let lineRange = source.lineRange(for: opening)
            var candidate = NSMaxRange(opening)
            var closing: NSRange?
            while candidate < NSMaxRange(lineContentsRange(lineRange, source: source)) {
                if source.character(at: candidate) == 0x60 {
                    let run = backtickRun(at: candidate, in: source)
                    if run.length == opening.length {
                        closing = run
                        break
                    }
                    candidate = NSMaxRange(run)
                } else {
                    candidate += 1
                }
            }

            let end = closing.map(NSMaxRange)
                ?? NSMaxRange(lineContentsRange(lineRange, source: source))
            result.append(NSRange(location: opening.location, length: end - opening.location))
            location = max(end, location + 1)
        }
        return result
    }

    private static func backtickRun(at location: Int, in source: NSString) -> NSRange {
        var end = location
        while end < source.length, source.character(at: end) == 0x60 {
            end += 1
        }
        return NSRange(location: location, length: end - location)
    }

    private static func imageRanges(in text: String, source: NSString) -> [NSRange] {
        let fullRange = NSRange(location: 0, length: source.length)
        let code = codeRanges(in: source)
        return imageExpression.matches(in: text, range: fullRange).compactMap { match in
            guard !isEscaped(match.range.location, in: source),
                  !code.contains(where: { intersects(match.range, $0) })
            else { return nil }
            return match.range
        }
    }

    /// Returns only the structural portions of ordinary inline links, leaving
    /// their visible labels available for formatting. Link destinations and
    /// autolinks are protected in full so a format toggle can never rewrite a
    /// URL into `[label](**https://example.com**)` or `<**https://...**>`.
    private static func markdownLinkProtectedRanges(
        in source: NSString,
        excluding excludedRanges: [NSRange]
    ) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0

        while location < source.length {
            if let excluded = excludedRanges.first(where: {
                NSLocationInRange(location, $0)
            }) {
                location = max(location + 1, NSMaxRange(excluded))
                continue
            }

            let character = source.character(at: location)
            if character == 0x5B, // [
               !isEscaped(location, in: source),
               (location == 0 || source.character(at: location - 1) != 0x21), // !
               let closingLabel = matchingSquareBracket(
                   openingAt: location,
                   in: source
               )
            {
                var openingParenthesis = closingLabel + 1
                while openingParenthesis < source.length,
                      isHorizontalWhitespace(source.character(at: openingParenthesis)) {
                    openingParenthesis += 1
                }
                if openingParenthesis < source.length,
                   source.character(at: openingParenthesis) == 0x28, // (
                   !excludedRanges.contains(where: {
                       NSLocationInRange(openingParenthesis, $0)
                   })
                {
                    let lineRange = source.lineRange(
                        for: NSRange(location: openingParenthesis, length: 0)
                    )
                    let lineEnd = NSMaxRange(
                        lineContentsRange(lineRange, source: source)
                    )
                    let closingParenthesis = matchingParenthesis(
                        openingAt: openingParenthesis,
                        before: lineEnd,
                        in: source
                    )
                    // An incomplete destination is protected through the end of
                    // its line. This intentionally prefers refusing a format
                    // toggle over making already-fragile Markdown worse.
                    let protectedEnd = closingParenthesis.map { $0 + 1 } ?? lineEnd
                    ranges.append(NSRange(location: location, length: 1))
                    ranges.append(
                        NSRange(
                            location: closingLabel,
                            length: protectedEnd - closingLabel
                        )
                    )
                    location = max(protectedEnd, location + 1)
                    continue
                }
            }

            if character == 0x3C, // <
               !isEscaped(location, in: source)
            {
                let lineRange = source.lineRange(
                    for: NSRange(location: location, length: 0)
                )
                let lineEnd = NSMaxRange(
                    lineContentsRange(lineRange, source: source)
                )
                let closing = firstUnescapedCharacter(
                    0x3E, // >
                    after: location,
                    before: lineEnd,
                    in: source
                )
                let contentsEnd = closing ?? lineEnd
                let contentsRange = NSRange(
                    location: location + 1,
                    length: max(0, contentsEnd - location - 1)
                )
                if looksLikeAutolink(contentsRange, in: source) {
                    let protectedEnd = closing.map { $0 + 1 } ?? lineEnd
                    ranges.append(
                        NSRange(
                            location: location,
                            length: protectedEnd - location
                        )
                    )
                    location = max(protectedEnd, location + 1)
                    continue
                }
            }

            location += 1
        }
        return ranges
    }

    private static func matchingSquareBracket(
        openingAt opening: Int,
        in source: NSString
    ) -> Int? {
        let lineRange = source.lineRange(
            for: NSRange(location: opening, length: 0)
        )
        let end = NSMaxRange(lineContentsRange(lineRange, source: source))
        var depth = 1
        var location = opening + 1
        while location < end {
            guard !isEscaped(location, in: source) else {
                location += 1
                continue
            }
            switch source.character(at: location) {
            case 0x5B: // [
                depth += 1
            case 0x5D: // ]
                depth -= 1
                if depth == 0 { return location }
            default:
                break
            }
            location += 1
        }
        return nil
    }

    private static func matchingParenthesis(
        openingAt opening: Int,
        before end: Int,
        in source: NSString
    ) -> Int? {
        var depth = 1
        var location = opening + 1
        while location < end {
            guard !isEscaped(location, in: source) else {
                location += 1
                continue
            }
            switch source.character(at: location) {
            case 0x28: // (
                depth += 1
            case 0x29: // )
                depth -= 1
                if depth == 0 { return location }
            default:
                break
            }
            location += 1
        }
        return nil
    }

    private static func firstUnescapedCharacter(
        _ character: unichar,
        after start: Int,
        before end: Int,
        in source: NSString
    ) -> Int? {
        var location = start + 1
        while location < end {
            if source.character(at: location) == character,
               !isEscaped(location, in: source) {
                return location
            }
            location += 1
        }
        return nil
    }

    private static func looksLikeAutolink(
        _ range: NSRange,
        in source: NSString
    ) -> Bool {
        guard range.length > 0 else { return false }
        let end = NSMaxRange(range)
        var atLocation: Int?
        var colonLocation: Int?
        for location in range.location..<end {
            let character = source.character(at: location)
            if isHorizontalWhitespace(character)
                || character == 0x0A
                || character == 0x0D
                || character == 0x3C
                || character == 0x3E
            {
                return false
            }
            if character == 0x40 { // @
                if atLocation != nil { return false }
                atLocation = location
            } else if character == 0x3A, colonLocation == nil { // :
                colonLocation = location
            }
        }

        if let colonLocation {
            let schemeLength = colonLocation - range.location
            guard (2...32).contains(schemeLength), colonLocation + 1 < end,
                  isASCIIAlpha(source.character(at: range.location))
            else { return false }
            for location in (range.location + 1)..<colonLocation {
                let character = source.character(at: location)
                guard isASCIIAlpha(character)
                        || isASCIIDigit(character)
                        || character == 0x2B // +
                        || character == 0x2D // -
                        || character == 0x2E // .
                else { return false }
            }
            return true
        }

        if let atLocation,
           atLocation > range.location,
           atLocation + 1 < end {
            var hasDomainDot = false
            for location in (atLocation + 1)..<end {
                if source.character(at: location) == 0x2E { // .
                    hasDomainDot = true
                }
            }
            return hasDomainDot
        }
        return false
    }

    private static func isASCIIAlpha(_ character: unichar) -> Bool {
        (0x41...0x5A).contains(character) || (0x61...0x7A).contains(character)
    }

    private static func isASCIIDigit(_ character: unichar) -> Bool {
        (0x30...0x39).contains(character)
    }

    private static func whitespaceTrimmedRange(
        _ range: NSRange,
        in source: NSString
    ) -> NSRange? {
        let value = source.substring(with: range) as NSString
        let nonWhitespace = CharacterSet.whitespaces.inverted
        let first = value.rangeOfCharacter(from: nonWhitespace)
        guard first.location != NSNotFound else { return nil }
        let last = value.rangeOfCharacter(from: nonWhitespace, options: .backwards)
        return NSRange(
            location: range.location + first.location,
            length: NSMaxRange(last) - first.location
        )
    }

    private static func containsLineBreak(_ range: NSRange, in source: NSString) -> Bool {
        guard range.length > 0 else { return false }
        for location in range.location..<NSMaxRange(range) {
            let character = source.character(at: location)
            if character == 0x0A || character == 0x0D {
                return true
            }
        }
        return false
    }

    private static func lineContentsRange(_ lineRange: NSRange, source: NSString) -> NSRange {
        var end = NSMaxRange(lineRange)
        while end > lineRange.location {
            let character = source.character(at: end - 1)
            guard character == 0x0A || character == 0x0D else { break }
            end -= 1
        }
        return NSRange(location: lineRange.location, length: end - lineRange.location)
    }

    private static func format(at location: Int, in source: NSString) -> MarkdownInlineFormat? {
        guard location >= 0, location + 2 <= source.length else { return nil }
        let first = source.character(at: location)
        let second = source.character(at: location + 1)
        if first == 0x2A, second == 0x2A {
            guard (location == 0 || source.character(at: location - 1) != 0x2A),
                  (location + 2 == source.length || source.character(at: location + 2) != 0x2A)
            else { return nil }
            return .bold
        }
        if first == 0x3D, second == 0x3D {
            guard (location == 0 || source.character(at: location - 1) != 0x3D),
                  (location + 2 == source.length || source.character(at: location + 2) != 0x3D)
            else { return nil }
            return .highlight
        }
        return nil
    }

    private static func isEscaped(_ location: Int, in source: NSString) -> Bool {
        guard location > 0 else { return false }
        var slashCount = 0
        var index = location - 1
        while index >= 0, source.character(at: index) == 0x5C {
            slashCount += 1
            if index == 0 { break }
            index -= 1
        }
        return slashCount % 2 == 1
    }

    private static func hasNonWhitespaceCharacter(
        at location: Int,
        in source: NSString
    ) -> Bool {
        guard location >= 0, location < source.length else { return false }
        let character = source.character(at: location)
        return !isHorizontalWhitespace(character)
            && character != 0x0A
            && character != 0x0D
    }

    private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 0x20 || character == 0x09
    }

    private static func isValidNonempty(_ range: NSRange, in source: NSString) -> Bool {
        range.location != NSNotFound
            && range.location >= 0
            && range.length > 0
            && range.location <= source.length
            && range.length <= source.length - range.location
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private static func intersects(_ first: NSRange, _ second: NSRange) -> Bool {
        NSIntersectionRange(first, second).length > 0
    }
}
