import AppKit
import Markdown

/// Pasting rich text, HTML on the clipboard from a web page, Google Docs, Slack, or an email, as Markdown (see
/// `HTMLMarkdown`). Paste and Match Style (⇧⌘V) still pastes the plain text.
extension MarkdownTextView {
    /// Where Safari can put a selection instead of HTML.
    static let webArchiveType = NSPasteboard.PasteboardType("com.apple.webarchive")

    /// Pastes the clipboard's HTML as Markdown, and returns whether it did. It doesn't in code or front matter,
    /// when the clipboard's text is a single URL, or when the HTML is only code (a code editor's copy); the
    /// plain text is pasted there instead.
    func pasteRichText(from pasteboard: NSPasteboard) -> Bool {
        let range = selectedRange()
        guard selectedRanges.count == 1, let html = Self.html(on: pasteboard) else { return false }
        if let plain = pasteboard.string(forType: .string), Self.isURL(plain.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return false
        }
        guard !touchesMarkup(range, where: { $0 is CodeBlock || $0 is InlineCode }),
              let markdown = HTMLMarkdown.markdown(fromHTML: html) else { return false }
        let pasted = continuingContainer(markdown, at: range.location)
        edit(range, with: pasted, selection: NSRange(location: range.location + (pasted as NSString).length, length: 0))
        undoManager?.setActionName("Paste")
        return true
    }

    private static func html(on pasteboard: NSPasteboard) -> String? {
        if let html = pasteboard.string(forType: .html), !html.isEmpty { return html }
        return pasteboard.data(forType: webArchiveType).flatMap(HTMLMarkdown.html(fromWebArchive:))
    }

    /// Groups: 1 quote markers, 2 indentation, 3 a list marker (and task box) with its space.
    private static let containerPrefix = try! NSRegularExpression(
        pattern: "^((?:[ \\t]*>[ \\t]?)*)([ \\t]*)((?:[-*+]|\\d{1,9}[.)])[ \\t]+(?:\\[[ xX]\\][ \\t]+)?)?")

    /// `markdown` with its lines after the first prefixed so they stay in the quote or list item the insertion
    /// point is in: the quote markers, and spaces as wide as the item's marker and indentation.
    private func continuingContainer(_ markdown: String, at location: Int) -> String {
        let text = string as NSString
        let line = text.substring(with: text.lineRange(for: NSRange(location: location, length: 0)))
        let ns = line as NSString
        guard markdown.contains("\n"),
              let match = Self.containerPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        else { return markdown }
        let quote = ns.substring(with: match.range(at: 1))
        let indent = ns.substring(with: match.range(at: 2))
        let marker = match.range(at: 3).location == NSNotFound ? "" : ns.substring(with: match.range(at: 3))
        let prefix = quote + indent + String(repeating: " ", count: (marker as NSString).length)
        guard !prefix.isEmpty else { return markdown }
        let blank = quote.trimmingCharacters(in: .whitespaces)
        let lines = markdown.components(separatedBy: "\n")
        return lines[0] + lines.dropFirst().map { "\n" + ($0.isEmpty ? blank : prefix + $0) }.joined()
    }
}
