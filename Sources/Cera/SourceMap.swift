import Foundation
import Markdown

/// Converts swift-markdown source positions (1-based line, 1-based UTF-8 byte
/// column) into UTF-16 offsets in the string the text view edits.
///
/// Only line start offsets are stored, so building the map stays cheap for large
/// documents; columns are converted on demand from the line's text.
struct SourceMap {
    private let text: NSString
    /// UTF-16 offset of the start of each line. Line breaks are \n, \r\n, or \r, as in CommonMark.
    let lineStarts: [Int]

    init(_ text: NSString) {
        self.text = text
        var starts = [0]
        let length = text.length
        let chunk = 8192
        var buffer = [unichar](repeating: 0, count: chunk)
        var index = 0
        var previousWasCarriageReturn = false
        while index < length {
            let count = min(chunk, length - index)
            text.getCharacters(&buffer, range: NSRange(location: index, length: count))
            for offset in 0..<count {
                switch buffer[offset] {
                case 10: // \n, or the second half of \r\n
                    if previousWasCarriageReturn {
                        starts[starts.count - 1] = index + offset + 1
                    } else {
                        starts.append(index + offset + 1)
                    }
                    previousWasCarriageReturn = false
                case 13: // \r
                    starts.append(index + offset + 1)
                    previousWasCarriageReturn = true
                default:
                    previousWasCarriageReturn = false
                }
            }
            index += count
        }
        lineStarts = starts
    }

    func offset(_ location: SourceLocation) -> Int {
        let line = location.line - 1
        guard line >= 0, line < lineStarts.count else { return text.length }
        let start = lineStarts[line]
        let bytes = location.column - 1
        guard bytes > 0 else { return start }

        let content = contentRange(ofLine: line)
        let lineText = text.substring(with: content)
        let utf8 = lineText.utf8
        guard bytes < utf8.count,
              let index = utf8.index(utf8.startIndex, offsetBy: bytes, limitedBy: utf8.endIndex)
        else { return NSMaxRange(content) }
        return start + lineText.utf16.distance(from: lineText.utf16.startIndex, to: index)
    }

    func range(_ range: SourceRange?) -> NSRange? {
        guard let range else { return nil }
        let start = offset(range.lowerBound)
        let end = max(start, offset(range.upperBound))
        return NSRange(location: start, length: end - start)
    }

    /// The text range of a node. Use this, not `range(_:)`, for inline nodes (emphasis, code, links, text):
    /// on a paragraph's later lines the parser gives their columns as if each line's text started where the
    /// paragraph's first line does. A line that leaves out the quote's `>` or the list item's indentation
    /// (a lazy continuation line), or has more of it, would put them in the wrong place.
    func range(of markup: Markup) -> NSRange? {
        guard let range = markup.range else { return nil }
        guard markup is Markdown.InlineMarkup else { return self.range(range) }
        var block = markup.parent
        while let current = block, current is Markdown.InlineMarkup { block = current.parent }
        guard let blockStart = block?.range?.lowerBound else { return self.range(range) }
        let start = offset(range.lowerBound, inBlockStartingAt: blockStart)
        let end = max(start, offset(range.upperBound, inBlockStartingAt: blockStart))
        return NSRange(location: start, length: end - start)
    }

    /// Quote markers and indentation before a paragraph line's text.
    private static let linePrefixRegex = try! NSRegularExpression(pattern: "^[ \\t]*(?:>[ \\t]*)*")

    /// `location` in a block that starts at `blockStart`, measured from where its line's text starts.
    private func offset(_ location: SourceLocation, inBlockStartingAt blockStart: SourceLocation) -> Int {
        let line = location.line - 1
        guard location.line > blockStart.line, line < lineStarts.count else { return offset(location) }
        let lineText = text.substring(with: contentRange(ofLine: line))
        let prefix = Self.linePrefixRegex.firstMatch(in: lineText, range: NSRange(location: 0, length: (lineText as NSString).length))?
            .range.length ?? 0
        // The prefix is ASCII, so its length in UTF-16 is its length in UTF-8 bytes, as columns count.
        let column = prefix + 1 + location.column - blockStart.column
        return offset(SourceLocation(line: location.line, column: column, source: nil))
    }

    /// The line's characters, without its line break.
    private func contentRange(ofLine line: Int) -> NSRange {
        let start = lineStarts[line]
        var end = line + 1 < lineStarts.count ? lineStarts[line + 1] : text.length
        while end > start, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}
