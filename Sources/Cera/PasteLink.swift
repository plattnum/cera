import AppKit
import Markdown

/// Pasting a URL over selected text makes a link, `[text](url)`, as in Obsidian. Paste and Match Style
/// (⇧⌘V, as in Obsidian) still pastes the URL as text.
extension MarkdownTextView {
    /// Turns the selection into a link to `pasted` when that is one URL and the selection is ordinary text.
    /// Returns whether it did; otherwise the paste goes ahead as usual.
    func pasteLink(_ pasted: String) -> Bool {
        let url = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = selectedRange()
        let text = string as NSString
        guard selectedRanges.count == 1, range.length > 0, Self.isURL(url) else { return false }
        let label = text.substring(with: range)
        guard label.rangeOfCharacter(from: .newlines) == nil, !Self.isURL(label.trimmingCharacters(in: .whitespaces)),
              !touchesMarkup(range, where: { $0 is CodeBlock || $0 is InlineCode || $0 is Link || $0 is Image
                                              || $0 is HTMLBlock || $0 is InlineHTML }) else { return false }

        let link = "[\(Self.escapedLabel(label))](\(Self.destination(url)))"
        edit(range, with: link, selection: NSRange(location: range.location + (link as NSString).length, length: 0))
        undoManager?.setActionName("Paste")
        return true
    }

    /// One URL: no whitespace, and a scheme followed by `://` and more, or a `mailto:` address.
    static func isURL(_ string: String) -> Bool {
        guard !string.isEmpty, string.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: string), let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "mailto" { return string.count > "mailto:".count }
        return string.dropFirst(scheme.count).hasPrefix("://") && string.count > scheme.count + 3
    }

    /// Whether `range` is in front matter, or overlaps Markdown that `matches` (a code block, a link). An empty
    /// range, an insertion point, counts when it is inside the markup, not at its edges. Read from the Markdown,
    /// so source view works the same as the rendered view.
    func touchesMarkup(_ range: NSRange, where matches: (Markup) -> Bool) -> Bool {
        let text = string as NSString
        if let frontMatter = FrontMatter.range(in: text), range.location < NSMaxRange(frontMatter) { return true }
        // The top-level blocks around the range, parsed in their real context.
        let blocks = topLevelBlocks().filter {
            NSIntersectionRange($0, range).length > 0 || ($0.location < range.location && range.location < NSMaxRange($0))
        }
        let region = blocks.isEmpty ? text.lineRange(for: range) : NSUnionRange(blocks.first!, blocks.last!)
        let piece = NSString(string: FrontMatter.parsable(text, region: region).text)
        let map = SourceMap(piece)
        let selection = NSRange(location: range.location - region.location, length: range.length)

        func touches(_ markup: Markup) -> Bool {
            if matches(markup), let span = map.range(markup.range) {
                let inside = selection.length > 0 ? NSIntersectionRange(span, selection).length > 0
                    : span.location < selection.location && selection.location < NSMaxRange(span)
                if inside { return true }
            }
            return markup.children.contains(where: touches)
        }
        return touches(Document(parsing: piece as String))
    }

    /// The URL as a link destination: in angle brackets when its parentheses don't balance, which would
    /// otherwise end the link early.
    private static func destination(_ url: String) -> String {
        var depth = 0
        for character in url {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1; if depth < 0 { break } }
        }
        return depth == 0 ? url : "<\(url)>"
    }

    /// The selected text as link text: its square brackets escaped when they don't balance.
    private static func escapedLabel(_ label: String) -> String {
        var depth = 0
        for character in label {
            if character == "[" { depth += 1 }
            if character == "]" { depth -= 1; if depth < 0 { break } }
        }
        guard depth != 0 else { return label }
        return label.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}
