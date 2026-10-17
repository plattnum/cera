import AppKit
import Markdown

/// A fenced code block, with what editing inside it needs: where its lines are, and what
/// each body line starts with when the block is nested in a quote or list.
struct FencedCodeBlock: Equatable {
    /// The opening fence line, without its line break.
    let opening: NSRange
    /// The closing fence line, or nil while the block is unclosed.
    let closing: NSRange?
    /// The lines between the fences, without their line breaks.
    let body: [NSRange]
    /// What starts each body line: the quote markers, and the list indentation as spaces.
    let prefix: String
    /// The opening fence's characters, such as ``` or ~~~~.
    let fence: String
    /// The first word of the info string, if any.
    let language: String?

    /// A fence line, after any quote markers, list markers, and indentation (group 1): the
    /// fence (group 2) and what follows it (group 3).
    private static let fenceRegex = try! NSRegularExpression(
        pattern: "^((?:[ \\t]*>[ \\t]?|[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+|[ \\t])*)(`{3,}|~{3,})(.*)$")

    /// The fenced code block on the line holding `location`. `region` must hold whole
    /// top-level blocks, so the block parses in its real context.
    static func find(in text: NSString, at location: Int, region: NSRange) -> FencedCodeBlock? {
        guard location >= region.location, location <= NSMaxRange(region), NSMaxRange(region) <= text.length else { return nil }
        let source = text.substring(with: region) as NSString
        let starts = SourceMap(source).lineStarts
        let lineIndex = starts.lastIndex { $0 <= location - region.location } ?? 0
        guard let block = CodeBlockText.codeBlock(in: Document(parsing: source as String), onLine: lineIndex + 1),
              let lines = CodeBlockText.lines(of: block)
        else { return nil }

        func contentRange(ofLine number: Int) -> NSRange {
            let start = region.location + starts[min(number - 1, starts.count - 1)]
            var end = number < starts.count ? region.location + starts[number] : NSMaxRange(region)
            while end > start, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
            return NSRange(location: start, length: end - start)
        }

        let opening = contentRange(ofLine: lines.lowerBound)
        let openingText = text.substring(with: opening)
        guard let open = fenceRegex.firstMatch(in: openingText, range: NSRange(location: 0, length: (openingText as NSString).length))
        else { return nil } // An indented code block.
        // An indented code block whose first line looks like a fence keeps that line in its code.
        let fenceLine = (openingText as NSString).substring(from: open.range(at: 2).location)
        guard !block.code.hasPrefix(fenceLine) else { return nil }
        let fence = (openingText as NSString).substring(with: open.range(at: 2))

        let closing = CodeBlockText.closingFence(of: block, in: text, opening: opening)
        let bodyEnd = closing == nil ? lines.upperBound : lines.upperBound - 1
        let body = bodyEnd > lines.lowerBound ? (lines.lowerBound + 1...bodyEnd).map(contentRange) : []

        // List markers become spaces of the same width; quote markers and indentation stay.
        let rawPrefix = (openingText as NSString).substring(with: open.range(at: 1))
        let prefix = String(rawPrefix.map { $0 == ">" || $0 == " " || $0 == "\t" ? $0 : " " })
        let info = (openingText as NSString).substring(with: open.range(at: 3))
        let language = info.split(whereSeparator: \.isWhitespace).first.map(String.init)
        return FencedCodeBlock(opening: opening, closing: closing, body: body, prefix: prefix, fence: fence, language: language)
    }

    /// One level of indentation: a tab if the code uses tabs, else the smallest indentation
    /// the code uses (at most 8 spaces), else the language's usual one (see `CodeLanguages`). A single space is
    /// alignment, not indentation, as in the ` * ` lines of a C comment, so it doesn't count.
    func indentUnit(in text: NSString) -> String {
        var smallest = Int.max
        for line in body {
            let code = codePart(of: text.substring(with: line))
            if code.hasPrefix("\t") { return "\t" }
            let spaces = code.prefix { $0 == " " }.count
            if spaces > 1, spaces < code.count { smallest = min(smallest, spaces) }
        }
        if smallest != .max { return String(repeating: " ", count: min(smallest, 8)) }
        if let language = CodeLanguages.language(info: language) { return language.indent }
        return ["make", "makefile"].contains(language?.lowercased()) ? "\t" : "    "
    }

    /// A body line without the prefix that nests the block.
    func codePart(of line: String) -> String {
        line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line
    }

    /// How much of a body line is prefix: the expected prefix, or for a line that doesn't
    /// start with it, its leading quote markers (UTF-16 length).
    func prefixLength(of line: String) -> Int {
        if line.hasPrefix(prefix) { return (prefix as NSString).length }
        return (String(line.prefix { $0 == ">" || $0 == " " || $0 == "\t" }).trimmingTrailingWhitespace as NSString).length
    }
}

private extension String {
    var trimmingTrailingWhitespace: String {
        var result = self
        while let last = result.last, last == " " || last == "\t" { result.removeLast() }
        return result
    }
}

/// Typing in code blocks: Return keeps the indentation instead of continuing lists and
/// quotes, Tab and Shift-Tab indent and outdent, and Return after an opening fence closes it.
extension MarkdownTextView {

    /// The fenced code block on the line holding `location`.
    func fencedCodeBlock(at location: Int) -> FencedCodeBlock? {
        let text = string as NSString
        let blocks = topLevelBlocks().filter { NSMaxRange($0) <= text.length }
        let region: NSRange
        if blocks.isEmpty {
            region = NSRange(location: 0, length: text.length) // Not styled yet, as in tests.
        } else if let block = blocks.first(where: { NSLocationInRange(location, $0) })
                    ?? blocks.first(where: { NSMaxRange($0) == location }) {
            region = block
        } else {
            return nil
        }
        return FencedCodeBlock.find(in: text, at: location, region: region)
    }

    /// Return inside a code block. Returns false when the cursor isn't in one, so Return
    /// goes on to continue lists and quotes as usual.
    func insertNewlineInCode() -> Bool {
        let selection = selectedRange()
        guard selectedRanges.count == 1, let block = fencedCodeBlock(at: selection.location) else { return false }
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: selection.location, length: 0))

        // Return at the end of the opening fence line.
        if selection.length == 0, selection.location == NSMaxRange(block.opening) {
            if block.closing == nil {
                // Close the fence, and put the cursor on the empty line between.
                insertText("\n" + block.prefix + "\n" + block.prefix + block.fence, replacementRange: selection)
                setSelectedRange(NSRange(location: selection.location + 1 + (block.prefix as NSString).length, length: 0))
            } else {
                insertText("\n" + block.prefix, replacementRange: selection)
            }
            return true
        }

        // Elsewhere, only inside the body: fence lines keep the usual behavior.
        let end = NSMaxRange(selection)
        guard let first = block.body.first, let last = block.body.last,
              line.location >= first.location, end <= NSMaxRange(last)
        else { return false }

        let lineText = text.substring(with: NSRange(location: line.location, length: selection.location - line.location))
        let fullLine = text.substring(with: NSRange(location: line.location, length: NSMaxRange(line) - line.location))
        let prefixLength = block.prefixLength(of: fullLine)
        let column = (lineText as NSString).length
        let insertion: String
        if column <= prefixLength {
            // In the prefix itself: split it so both lines keep a whole prefix.
            let prefix = (fullLine as NSString).substring(to: prefixLength) as NSString
            insertion = prefix.substring(from: column) + "\n" + prefix.substring(to: column)
        } else {
            // The prefix, then the line's indentation up to the cursor.
            let prefix = (fullLine as NSString).substring(to: prefixLength)
            let afterPrefix = (lineText as NSString).substring(from: prefixLength)
            insertion = "\n" + prefix + afterPrefix.prefix { $0 == " " || $0 == "\t" }
        }
        insertText(insertion, replacementRange: selection)
        return true
    }

    /// The code block whose body the selection is in, and the body lines it touches. Nil when
    /// the selection reaches outside one block, or covers only fence lines.
    private func selectedCodeLines() -> (block: FencedCodeBlock, lines: [NSRange])? {
        let selection = selectedRange()
        guard selectedRanges.count == 1, let block = fencedCodeBlock(at: selection.location) else { return nil }
        // The last character selected; a selection ending at a line's start doesn't touch that line.
        let last = selection.length > 0 ? NSMaxRange(selection) - 1 : selection.location
        let blockEnd = NSMaxRange(block.closing ?? block.body.last ?? block.opening) // Where its last line break is.
        guard selection.location >= block.opening.location, last <= blockEnd else { return nil }
        // A line touches the selection anywhere from its first character to its line break.
        let lines = block.body.filter { $0.location <= last && selection.location <= NSMaxRange($0) }
        return lines.isEmpty ? nil : (block, lines)
    }

    /// Tab in a code block: with no selection, an indent at the cursor; with one, indents the
    /// selected lines. Returns false when the selection isn't in a code block's body.
    func insertTabInCode() -> Bool {
        guard let (block, lines) = selectedCodeLines() else { return false }
        let selection = selectedRange()
        if selection.length == 0 {
            let text = string as NSString
            let line = lines[0]
            let prefixEnd = line.location + block.prefixLength(of: text.substring(with: line))
            let at = max(selection.location, prefixEnd)
            insertText(block.indentUnit(in: text), replacementRange: NSRange(location: at, length: 0))
            return true
        }
        indentCode(block: block, lines: lines, deeper: true)
        return true
    }

    /// Shift-Tab, ⌘[, and ⌘] in a code block: outdent or indent the lines the selection touches.
    func shiftCodeLines(deeper: Bool) -> Bool {
        guard let (block, lines) = selectedCodeLines() else { return false }
        indentCode(block: block, lines: lines, deeper: deeper)
        return true
    }

    /// Indents or outdents `lines` by one unit, after the prefix, as one Undo step. The same
    /// lines stay selected; with no selection, the cursor stays on its text.
    private func indentCode(block: FencedCodeBlock, lines: [NSRange], deeper: Bool) {
        let text = string as NSString
        let unit = block.indentUnit(in: text)
        let span = NSRange(location: lines[0].location, length: NSMaxRange(lines[lines.count - 1]) - lines[0].location)
        let selection = selectedRange()
        var result = ""
        var cursor = span.location
        var shift = 0 // How far the cursor moves, for an empty selection on the first line.
        for line in lines {
            result += text.substring(with: NSRange(location: cursor, length: line.location - cursor)) // Line breaks between.
            let content = text.substring(with: line)
            let prefixLength = block.prefixLength(of: content)
            let prefix = (content as NSString).substring(to: prefixLength)
            var code = (content as NSString).substring(from: prefixLength)
            var change = 0
            if deeper {
                if !code.trimmingCharacters(in: .whitespaces).isEmpty {
                    code = unit + code
                    change = (unit as NSString).length
                }
            } else {
                let removed: Int
                if code.hasPrefix("\t") {
                    removed = 1
                } else {
                    let width = unit == "\t" ? 4 : (unit as NSString).length
                    removed = code.prefix(width).prefix { $0 == " " }.count
                }
                code = String(code.dropFirst(removed))
                change = -removed
            }
            // A cursor in the code moves with it, but never back into the prefix.
            let column = selection.location - line.location
            if selection.length == 0, column >= 0, column <= line.length, column > prefixLength {
                shift = max(prefixLength, column + change) - column
            }
            result += prefix + code
            cursor = NSMaxRange(line)
        }
        guard result != text.substring(with: span) else { return }
        let newSelection = selection.length == 0
            ? NSRange(location: selection.location + shift, length: 0)
            : NSRange(location: span.location, length: (result as NSString).length)
        edit(span, with: result, selection: newSelection)
    }
}
