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

    /// The line's characters, without its line break.
    private func contentRange(ofLine line: Int) -> NSRange {
        let start = lineStarts[line]
        var end = line + 1 < lineStarts.count ? lineStarts[line + 1] : text.length
        while end > start, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}
