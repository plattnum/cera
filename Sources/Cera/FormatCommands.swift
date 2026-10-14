import AppKit

/// Block-level formatting: headings, lists, quotes, and inserted blocks. Each
/// command works on every line the selection touches, and toggles: applying a
/// format the lines already have removes it.
extension MarkdownTextView {

    private static let headingPrefix = try! NSRegularExpression(pattern: "^#{1,6}[ \\t]+")
    /// Groups: 1 indentation, 2 the marker with its trailing space.
    private static let listPrefix = try! NSRegularExpression(
        pattern: "^([ \\t]*)([-*+][ \\t]+\\[[ xX]\\][ \\t]+|[-*+][ \\t]+|\\d+[.)][ \\t]+)")
    private static let quotePrefix = try! NSRegularExpression(pattern: "^[ \\t]*>[ \\t]?")

    enum ListKind { case bulleted, numbered, task }

    // MARK: - Headings

    @objc func paragraph(_ sender: Any?) { applyHeading { _ in 0 } }
    @objc func heading1(_ sender: Any?) { toggleHeading(1) }
    @objc func heading2(_ sender: Any?) { toggleHeading(2) }
    @objc func heading3(_ sender: Any?) { toggleHeading(3) }
    @objc func heading4(_ sender: Any?) { toggleHeading(4) }
    @objc func heading5(_ sender: Any?) { toggleHeading(5) }
    @objc func heading6(_ sender: Any?) { toggleHeading(6) }

    /// Paragraph → Heading 6 → … → Heading 1.
    @objc func makeHeadingLarger(_ sender: Any?) {
        applyHeading { level in level == 0 ? 6 : max(1, level - 1) }
    }

    /// Heading 1 → … → Heading 6 → Paragraph.
    @objc func makeHeadingSmaller(_ sender: Any?) {
        applyHeading { level in level == 0 || level == 6 ? 0 : level + 1 }
    }

    /// Choosing the level the lines already have turns them back into paragraphs.
    private func toggleHeading(_ level: Int) {
        let levels = selectedLines().filter { !isBlank($0) }.map(headingLevel)
        let alreadyThere = !levels.isEmpty && levels.allSatisfy { $0 == level }
        applyHeading { _ in alreadyThere ? 0 : level }
    }

    private func applyHeading(_ newLevel: @escaping (Int) -> Int) {
        transformSelectedLines { lines in
            lines.map { line in
                guard !self.isBlank(line) else { return line }
                let level = newLevel(self.headingLevel(line))
                let content = self.removing(Self.headingPrefix, from: line)
                return level == 0 ? content : String(repeating: "#", count: level) + " " + content
            }
        }
    }

    private func headingLevel(_ line: String) -> Int {
        guard let match = Self.headingPrefix.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return 0 }
        return (line as NSString).substring(with: match.range).filter { $0 == "#" }.count
    }

    // MARK: - Lists and quotes

    @objc func toggleBulletedList(_ sender: Any?) { toggleList(.bulleted) }
    @objc func toggleNumberedList(_ sender: Any?) { toggleList(.numbered) }
    @objc func toggleTaskList(_ sender: Any?) { toggleList(.task) }

    /// Makes the lines a list of `kind`, converting other list kinds; if they already are one, removes the markers.
    func toggleList(_ kind: ListKind) {
        let lines = selectedLines().filter { !isBlank($0) }
        let alreadyThere = !lines.isEmpty && lines.allSatisfy { listKind(of: $0) == kind }
        transformSelectedLines { lines in
            var number = 0
            return lines.map { line in
                guard !self.isBlank(line) else { return line }
                let (indent, content) = self.splitListMarker(line)
                if alreadyThere { return indent + content }
                number += 1
                switch kind {
                case .bulleted: return indent + "- " + content
                case .numbered: return indent + "\(number). " + content
                case .task: return indent + "- [ ] " + content
                }
            }
        }
    }

    @objc func toggleQuote(_ sender: Any?) {
        let lines = selectedLines().filter { !isBlank($0) }
        let alreadyQuoted = !lines.isEmpty && lines.allSatisfy { self.matches(Self.quotePrefix, $0) }
        transformSelectedLines { lines in
            lines.map { line in
                if alreadyQuoted { return self.removing(Self.quotePrefix, from: line) }
                return self.isBlank(line) ? ">" : "> " + line
            }
        }
    }

    /// Nests list items one level deeper. Lines that aren't list items are left alone.
    @objc func indentList(_ sender: Any?) {
        transformSelectedLines { lines in
            lines.map { self.listKind(of: $0) == nil ? $0 : "    " + $0 }
        }
    }

    @objc func outdentList(_ sender: Any?) {
        transformSelectedLines { lines in
            lines.map { line in
                guard self.listKind(of: line) != nil else { return line }
                let spaces = line.prefix(4).prefix { $0 == " " }.count
                if spaces > 0 { return String(line.dropFirst(spaces)) }
                return line.hasPrefix("\t") ? String(line.dropFirst()) : line
            }
        }
    }

    /// Tab and Shift-Tab indent and outdent while the cursor is in a list.
    override func insertTab(_ sender: Any?) {
        if selectedLines().contains(where: { listKind(of: $0) != nil }) {
            indentList(sender)
        } else {
            super.insertTab(sender)
        }
    }

    override func insertBacktab(_ sender: Any?) {
        if selectedLines().contains(where: { listKind(of: $0) != nil }) {
            outdentList(sender)
        } else {
            super.insertBacktab(sender)
        }
    }

    func listKind(of line: String) -> ListKind? {
        guard let match = Self.listPrefix.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return nil }
        let marker = (line as NSString).substring(with: match.range(at: 2))
        if marker.contains("[") { return .task }
        return marker.first?.isNumber == true ? .numbered : .bulleted
    }

    private func splitListMarker(_ line: String) -> (indent: String, content: String) {
        let ns = line as NSString
        if let match = Self.listPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
            return (ns.substring(with: match.range(at: 1)), ns.substring(from: NSMaxRange(match.range)))
        }
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        return (indent, String(line.dropFirst(indent.count)))
    }

    // MARK: - Inserted blocks

    @objc func insertCodeBlock(_ sender: Any?) {
        if selectedRange().length > 0 {
            let start = (string as NSString).lineRange(for: selectedRange()).location
            transformSelectedLines { ["```"] + $0 + ["```"] }
            // Leave the cursor after the opening fence, ready for a language name.
            setSelectedRange(NSRange(location: start + 3, length: 0))
        } else {
            insertBlock("```\n\n```", selecting: NSRange(location: 4, length: 0))
        }
    }

    @objc func insertTable(_ sender: Any?) {
        let table = """
        | Column 1 | Column 2 | Column 3 |
        | -------- | -------- | -------- |
        |          |          |          |
        """
        insertBlock(table, selecting: NSRange(location: 2, length: 8)) // "Column 1"
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        insertBlock("---")
    }

    /// Removes bold, italic, strikethrough, code, and link syntax from the selection, keeping the text.
    @objc func clearFormatting(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        var text = (string as NSString).substring(with: range)
        text = text.replacingOccurrences(of: "!?\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        for marker in ["**", "~~", "`", "*"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        edit(range, with: text, selection: NSRange(location: range.location, length: (text as NSString).length))
    }

    /// Inserts `block` as its own paragraph at the selection, adding blank lines
    /// around it when it lands inside other text. `selecting` is relative to `block`.
    func insertBlock(_ block: String, replacing range: NSRange? = nil, selecting: NSRange? = nil) {
        let text = string as NSString
        let range = range ?? selectedRange()
        let line = text.lineRange(for: NSRange(location: range.location, length: 0))
        let atLineStart = range.location == line.location
        let atLineEnd = NSMaxRange(range) >= text.length || text.character(at: NSMaxRange(range)) == 10

        let before = atLineStart ? "" : "\n\n"
        let after = atLineEnd ? "" : "\n\n"
        let insertion = before + block + after
        guard shouldChangeText(in: range, replacementString: insertion) else { return }
        replaceCharacters(in: range, with: insertion)
        didChangeText()

        let blockStart = range.location + (before as NSString).length
        if let selecting {
            setSelectedRange(NSRange(location: blockStart + selecting.location, length: selecting.length))
        } else {
            setSelectedRange(NSRange(location: blockStart + (block as NSString).length, length: 0))
        }
    }

    // MARK: - Line helpers

    /// The full lines the selection touches, without their line breaks.
    func selectedLines() -> [String] {
        let text = string as NSString
        let block = text.substring(with: text.lineRange(for: selectedRange()))
        var lines = block.components(separatedBy: "\n")
        if block.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    /// Replaces the lines the selection touches. Afterwards the new lines are selected,
    /// or, if nothing was selected, the cursor goes to the end of the first line.
    func transformSelectedLines(_ transform: ([String]) -> [String]) {
        let text = string as NSString
        let hadSelection = selectedRange().length > 0
        let range = text.lineRange(for: selectedRange())
        let block = text.substring(with: range)
        let trailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if trailingNewline { lines.removeLast() }

        let newLines = transform(lines)
        let body = newLines.joined(separator: "\n")
        let replacement = body + (trailingNewline ? "\n" : "")
        let selection = hadSelection
            ? NSRange(location: range.location, length: (body as NSString).length)
            : NSRange(location: range.location + ((newLines.first ?? "") as NSString).length, length: 0)
        edit(range, with: replacement, selection: selection)
    }

    private func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func matches(_ regex: NSRegularExpression, _ line: String) -> Bool {
        regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    private func removing(_ regex: NSRegularExpression, from line: String) -> String {
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
        else { return line }
        return (line as NSString).substring(from: NSMaxRange(match.range))
    }
}
