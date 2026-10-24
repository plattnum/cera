import Foundation

/// Front matter: metadata for other tools at the very start of a file, YAML between `---` lines (Jekyll,
/// Obsidian, docs sites) or TOML between `+++` lines (Hugo). It isn't Markdown: read as Markdown, the YAML
/// becomes a rule and a large heading. So it is kept out of every parse, and shown as muted source.
enum FrontMatter {
    /// The front matter's lines, from the start of the text through its closing line, or nil when the text
    /// doesn't start with any. The first line (after a byte order mark) is `---` or `+++`, and the block ends
    /// at the next `---` or `...` line (`+++` for `+++`); unclosed, it isn't front matter. Lines may have
    /// trailing spaces. The closing line is looked for only before `limit`.
    static func range(in text: NSString, limit: Int? = nil) -> NSRange? {
        let end = min(limit ?? text.length, text.length)
        let start = text.length > 0 && text.character(at: 0) == 0xFEFF ? 1 : 0
        guard start < end else { return nil }
        let first = firstLine(of: text, from: start)
        let closings: Set<String>
        switch content(of: first, in: text) {
        case "---": closings = ["---", "..."]
        case "+++": closings = ["+++"]
        default: return nil
        }
        var lineStart = NSMaxRange(first)
        while lineStart < end {
            let line = text.lineRange(for: NSRange(location: lineStart, length: 0))
            if closings.contains(content(of: line, in: text)) { return NSRange(location: 0, length: NSMaxRange(line)) }
            lineStart = NSMaxRange(line)
        }
        return nil
    }

    /// Whether the text's first line opens front matter, closed or not.
    static func opens(_ text: NSString) -> Bool {
        let start = text.length > 0 && text.character(at: 0) == 0xFEFF ? 1 : 0
        guard start < text.length else { return false }
        return ["---", "+++"].contains(content(of: firstLine(of: text, from: start), in: text))
    }

    /// The first line, from `start`: after a byte order mark, which the line itself would include.
    private static func firstLine(of text: NSString, from start: Int) -> NSRange {
        let line = text.lineRange(for: NSRange(location: start, length: 0))
        return NSRange(location: start, length: NSMaxRange(line) - start)
    }

    /// Whether a line could open or close front matter, so typing or removing it can make or break one.
    static func isFence(_ line: String) -> Bool {
        ["---", "...", "+++"].contains(trimmingTrailingSpaces(line))
    }

    /// The text of `region` for the parser, and the front matter in it: when the region starts at the start of
    /// the text, the front matter's characters other than line breaks become spaces, so the parser sees blank
    /// lines there. The length and the lines stay the same, so every position the parser reports still matches
    /// the text.
    static func parsable(_ text: NSString, region: NSRange) -> (text: String, frontMatter: NSRange?) {
        let piece = text.substring(with: region)
        guard region.location == 0, let range = range(in: text, limit: NSMaxRange(region)) else { return (piece, nil) }
        var characters = Array((piece as NSString).substring(with: range).utf16)
        for index in characters.indices where characters[index] != 10 && characters[index] != 13 {
            characters[index] = 32
        }
        let masked = String(utf16CodeUnits: characters, count: characters.count) + (piece as NSString).substring(from: NSMaxRange(range))
        return (masked, range)
    }

    /// A line without its line break and trailing spaces or tabs.
    private static func content(of line: NSRange, in text: NSString) -> String {
        trimmingTrailingSpaces(text.substring(with: line))
    }

    private static func trimmingTrailingSpaces(_ line: String) -> String {
        var line = Substring(line)
        // `isNewline` also covers "\r\n", which Swift counts as one character.
        while let last = line.last, last.isNewline || last == " " || last == "\t" { line.removeLast() }
        return String(line)
    }
}
