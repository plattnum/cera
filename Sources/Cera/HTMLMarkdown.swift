import Foundation

/// HTML from the clipboard (a web page, Google Docs, Slack, Notion, an email) as Markdown, so a paste keeps its
/// headings, emphasis, links, lists, code, quotes, and tables. Colors, fonts, and sizes are dropped, and text that
/// would read as Markdown syntax is escaped, so pasted words can't turn into formatting.
enum HTMLMarkdown {
    /// The Markdown for `html`, or nil when there is nothing to convert: no text, or only code, as a code editor
    /// or Terminal copies it, which reads better pasted as the plain text.
    static func markdown(fromHTML html: String) -> String? {
        guard let document = try? XMLDocument(xmlString: html, options: [.documentTidyHTML]),
              let root = document.rootElement() else { return nil }
        // A fragment that is one well-formed element (`<b>bold</b>`) comes back as that element, not a page,
        // so it goes in a body of its own; its own formatting counts.
        let body: XMLElement
        if root.name?.lowercased() == "html" {
            body = root.elements(forName: "body").first ?? root
        } else {
            body = XMLElement(name: "body")
            body.addChild(root.copy() as! XMLNode)
        }
        let converter = Converter()
        let blocks = Converter.nestedByLevel(converter.blocks(in: body, style: Style()))
        guard converter.otherCharacters > 0 else { return nil }
        let markdown = Writer.write(blocks)
        return markdown.isEmpty ? nil : markdown
    }

    /// The HTML in a web archive, which Safari can put on the clipboard instead of HTML.
    static func html(fromWebArchive data: Data) -> String? {
        guard let archive = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let main = archive["WebMainResource"] as? [String: Any],
              let html = main["WebResourceData"] as? Data else { return nil }
        let encoding = (main["WebResourceTextEncodingName"] as? String).map {
            CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding($0 as CFString))
        }
        if let encoding, encoding != UInt(kCFStringEncodingInvalidId), let string = String(data: html, encoding: String.Encoding(rawValue: encoding)) {
            return string
        }
        return String(data: html, encoding: .utf8)
    }
}

// MARK: - Model

/// Inline formatting in effect for a run of text.
private struct Style: Equatable {
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var link: String?
}

private enum Run {
    case text(String, Style)
    case lineBreak
    case image(alt: String, source: String, link: String?)
}

private indirect enum Block {
    case paragraph([Run])
    case heading(Int, [Run])
    case code(language: String?, text: String)
    case list(ordered: Bool, start: Int, items: [Item])
    case quote([Block])
    case table([[[Run]]])
    case rule
}

private struct Item {
    /// nil for an ordinary item, or whether its checkbox is checked.
    var checked: Bool?
    var blocks: [Block]
    /// Google Docs gives list items a level (`aria-level`) instead of nesting lists.
    var level: Int?
}

// MARK: - Reading HTML

private final class Converter {
    /// Characters of text outside code, to tell prose from a code editor's copy.
    var otherCharacters = 0

    private static let blockNames: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "pre", "ul", "ol", "li", "blockquote", "table", "hr",
        "section", "article", "header", "footer", "main", "nav", "aside", "figure", "figcaption", "details",
        "summary", "dl", "dt", "dd", "address", "center", "form", "fieldset", "body", "html", "tbody", "thead",
        "tfoot", "tr", "td", "th", "caption"
    ]
    private static let skippedNames: Set<String> = [
        "head", "script", "style", "title", "meta", "link", "noscript", "template", "select", "option", "textarea",
        "iframe", "object", "svg", "canvas", "button"
    ]
    private static let monospaceFonts = ["monospace", "courier", "consolas", "menlo", "monaco", "mono", "source code",
                                         "fira code", "inconsolata"]

    /// The blocks in a container element, with inline content between block children becoming paragraphs,
    /// as a browser lays it out.
    func blocks(in node: XMLNode, style: Style) -> [Block] {
        var blocks: [Block] = []
        var runs: [Run] = []
        func flush() {
            if Writer.hasContent(runs) { blocks.append(.paragraph(runs)) }
            runs = []
        }
        for child in node.children ?? [] {
            guard let element = child as? XMLElement, let name = element.name?.lowercased() else {
                runs += self.runs(in: child, style: style)
                continue
            }
            if Self.skippedNames.contains(name) { continue }
            if Self.blockNames.contains(name) || containsBlock(element) {
                flush()
                blocks += block(element, name: name, style: self.style(for: element, name: name, base: style))
            } else {
                runs += self.runs(in: element, style: style)
            }
        }
        flush()
        return blocks
    }

    private func block(_ element: XMLElement, name: String, style: Style) -> [Block] {
        switch name {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            // A heading's own weight isn't bold text.
            var heading = style
            heading.bold = false
            let runs = inlineRuns(of: element, style: heading).map { run -> Run in
                guard case .text(let text, var runStyle) = run else { return run }
                runStyle.bold = false
                return .text(text, runStyle)
            }
            return Writer.hasContent(runs) ? [.heading(Int(String(name.last!))!, runs)] : []
        case "pre":
            let text = element.stringValue ?? ""
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.code(language: language(of: element), text: text)]
        case "ul", "ol":
            let start = Int(element.attribute(forName: "start")?.stringValue ?? "") ?? 1
            var items: [Item] = []
            for child in (element.children ?? []).compactMap({ $0 as? XMLElement }) {
                switch child.name?.lowercased() {
                case "li":
                    let item = item(from: child, style: style)
                    // An item holding only a list (tidy wraps a list written right inside a list this way)
                    // belongs to the item before it.
                    let onlyLists = !item.blocks.isEmpty && item.blocks.allSatisfy { if case .list = $0 { return true }; return false }
                    if onlyLists, item.checked == nil, !items.isEmpty {
                        items[items.count - 1].blocks += item.blocks
                    } else {
                        items.append(item)
                    }
                case "ul", "ol":
                    // A list directly inside a list, as some editors write it, belongs to the item before it.
                    let nested = block(child, name: child.name!.lowercased(), style: style)
                    if items.isEmpty { items.append(Item(checked: nil, blocks: nested, level: nil)) } else { items[items.count - 1].blocks += nested }
                default:
                    break
                }
            }
            return items.isEmpty ? [] : [.list(ordered: name == "ol", start: start, items: items)]
        case "li":
            return [.list(ordered: false, start: 1, items: [item(from: element, style: style)])]
        case "blockquote":
            let inner = Self.nestedByLevel(blocks(in: element, style: style))
            return inner.isEmpty ? [] : [.quote(inner)]
        case "table":
            let rows = tableRows(of: element).map { row in
                row.map { cell in inlineRuns(of: cell, style: self.style(for: cell, name: cell.name ?? "", base: style)) }
            }
            return rows.isEmpty ? [] : [.table(rows)]
        case "hr":
            return [.rule]
        default:
            return blocks(in: element, style: style)
        }
    }

    private func item(from element: XMLElement, style: Style) -> Item {
        // GitHub writes `<input type="checkbox" checked>`; Google Docs `role="checkbox" aria-checked="true"`.
        var checked: Bool?
        if element.attribute(forName: "role")?.stringValue == "checkbox" {
            checked = element.attribute(forName: "aria-checked")?.stringValue == "true"
        } else if let box = firstCheckbox(in: element) {
            checked = box.attribute(forName: "checked") != nil
        }
        let level = Int(element.attribute(forName: "aria-level")?.stringValue ?? "")
        return Item(checked: checked, blocks: Self.nestedByLevel(blocks(in: element, style: style)), level: level)
    }

    private func firstCheckbox(in element: XMLElement) -> XMLElement? {
        for child in element.children ?? [] {
            guard let child = child as? XMLElement, let name = child.name?.lowercased() else { continue }
            if name == "ul" || name == "ol" { continue }
            if name == "input", child.attribute(forName: "type")?.stringValue?.lowercased() == "checkbox" { return child }
            if let found = firstCheckbox(in: child) { return found }
        }
        return nil
    }

    private func tableRows(of element: XMLElement) -> [[XMLElement]] {
        var rows: [[XMLElement]] = []
        for child in element.children ?? [] {
            guard let child = child as? XMLElement, let name = child.name?.lowercased() else { continue }
            if name == "tr" {
                let cells = (child.children ?? []).compactMap { $0 as? XMLElement }
                    .filter { ["td", "th"].contains($0.name?.lowercased() ?? "") }
                if !cells.isEmpty { rows.append(cells) }
            } else if ["thead", "tbody", "tfoot"].contains(name) {
                rows += tableRows(of: child)
            }
        }
        return rows
    }

    /// A code block's language: `class="language-swift"` (or `lang-`) on the `pre` or its `code`, or GitHub's
    /// `highlight-source-swift` on the element around the `pre`.
    private func language(of pre: XMLElement) -> String? {
        let candidates = [pre, pre.elements(forName: "code").first, pre.parent as? XMLElement].compactMap { $0 }
        for element in candidates {
            for name in (element.attribute(forName: "class")?.stringValue ?? "").split(separator: " ") {
                for prefix in ["language-", "lang-", "highlight-source-"] where name.hasPrefix(prefix) {
                    let language = String(name.dropFirst(prefix.count))
                    if !language.isEmpty { return language }
                }
            }
        }
        return nil
    }

    private func containsBlock(_ element: XMLElement) -> Bool {
        (element.children ?? []).contains { child in
            guard let child = child as? XMLElement, let name = child.name?.lowercased() else { return false }
            return Self.blockNames.contains(name) || containsBlock(child)
        }
    }

    /// An element's inline content, with any blocks inside it (a `p` in a table cell) run together.
    private func inlineRuns(of element: XMLElement, style: Style) -> [Run] {
        var runs: [Run] = []
        for child in element.children ?? [] {
            if let child = child as? XMLElement, let name = child.name?.lowercased(),
               Self.blockNames.contains(name) || containsBlock(child) {
                if Writer.hasContent(runs) { runs.append(.text(" ", style)) }
                runs += inlineRuns(of: child, style: self.style(for: child, name: name, base: style))
            } else {
                runs += self.runs(in: child, style: style)
            }
        }
        return runs
    }

    private func runs(in node: XMLNode, style: Style) -> [Run] {
        if node.kind == .text {
            let text = node.stringValue ?? ""
            let count = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
            if !style.code { otherCharacters += count }
            return [.text(text, style)]
        }
        guard let element = node as? XMLElement, let name = element.name?.lowercased(),
              !Self.skippedNames.contains(name) else { return [] }
        switch name {
        case "br":
            return [.lineBreak]
        case "img":
            guard let source = element.attribute(forName: "src")?.stringValue, Self.isWebURL(source) else { return [] }
            otherCharacters += 1
            return [.image(alt: element.attribute(forName: "alt")?.stringValue ?? "", source: source, link: style.link)]
        case "input":
            return []
        default:
            let inner = self.style(for: element, name: name, base: style)
            return (element.children ?? []).flatMap { runs(in: $0, style: inner) }
        }
    }

    /// The style inside an element: its tag, and the parts of its `style` attribute Markdown can show.
    func style(for element: XMLElement, name: String, base: Style) -> Style {
        var style = base
        switch name {
        case "b", "strong": style.bold = true
        case "i", "em", "cite", "dfn", "var": style.italic = true
        case "s", "strike", "del": style.strike = true
        case "code", "kbd", "samp", "tt": style.code = true
        case "a":
            if let href = element.attribute(forName: "href")?.stringValue, Self.isWebURL(href) || href.lowercased().hasPrefix("mailto:") {
                style.link = href
            }
        default: break
        }
        for declaration in (element.attribute(forName: "style")?.stringValue ?? "").split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard parts.count == 2 else { continue }
            let (property, value) = (parts[0], parts[1])
            switch property {
            case "font-weight":
                if value == "bold" || value == "bolder" || (Int(value) ?? 0) >= 600 { style.bold = true }
                if value == "normal" || value == "lighter" || (1..<600).contains(Int(value) ?? 0) { style.bold = false }
            case "font-style":
                style.italic = value.hasPrefix("italic") || value.hasPrefix("oblique")
            case "text-decoration", "text-decoration-line":
                if value.contains("line-through") { style.strike = true }
            case "font-family":
                if Self.monospaceFonts.contains(where: { value.contains($0) }) { style.code = true }
            default: break
            }
        }
        return style
    }

    private static func isWebURL(_ string: String) -> Bool {
        let lower = string.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// Lists whose items carry levels (Google Docs) nested the way the levels say, merging the separate lists
    /// Docs writes for each level.
    static func nestedByLevel(_ blocks: [Block]) -> [Block] {
        var result: [Block] = []
        var pending: [(ordered: Bool, start: Int, item: Item)] = []
        func flush() {
            guard !pending.isEmpty else { return }
            result += nest(pending[...], level: pending.map { $0.item.level ?? 1 }.min() ?? 1)
            pending = []
        }
        for block in blocks {
            if case .list(let ordered, let start, let items) = block, items.allSatisfy({ $0.level != nil }) {
                pending += items.enumerated().map { (ordered, start + $0.offset, $0.element) }
            } else {
                flush()
                result.append(block)
            }
        }
        flush()
        return result
    }

    private static func nest(_ entries: ArraySlice<(ordered: Bool, start: Int, item: Item)>, level: Int) -> [Block] {
        var lists: [Block] = []
        var items: [Item] = []
        var ordered = entries.first?.ordered ?? false
        var start = entries.first?.start ?? 1
        var index = entries.startIndex
        while index < entries.endIndex {
            let entry = entries[index]
            if (entry.item.level ?? level) <= level || items.isEmpty {
                if !items.isEmpty, entry.ordered != ordered {
                    lists.append(.list(ordered: ordered, start: start, items: items))
                    items = []
                    start = entry.start
                }
                if items.isEmpty { ordered = entry.ordered; start = entry.start }
                items.append(entry.item)
                index += 1
            } else {
                // Deeper items belong to the item before them.
                var end = index
                while end < entries.endIndex, (entries[end].item.level ?? level) > level { end += 1 }
                items[items.count - 1].blocks += nest(entries[index..<end], level: level + 1)
                index = end
            }
        }
        if !items.isEmpty { lists.append(.list(ordered: ordered, start: start, items: items)) }
        return lists
    }
}

// MARK: - Writing Markdown

private enum Writer {
    static func write(_ blocks: [Block]) -> String {
        blocks.map(write).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func hasContent(_ runs: [Run]) -> Bool {
        runs.contains { run in
            switch run {
            case .text(let text, _): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .image: return true
            case .lineBreak: return false
            }
        }
    }

    private static func write(_ block: Block) -> String {
        switch block {
        case .paragraph(let runs):
            return escapingLineStarts(inline(runs, breaks: "\\\n"))
        case .heading(let level, let runs):
            let text = inline(runs, breaks: " ")
            return text.isEmpty ? "" : String(repeating: "#", count: level) + " " + text
        case .code(let language, let text):
            var code = text
            if code.hasSuffix("\n") { code.removeLast() }
            let fence = String(repeating: "`", count: max(3, longestRun(of: "`", in: code) + 1))
            return fence + (language ?? "") + "\n" + code + "\n" + fence
        case .list(let ordered, let start, let items):
            return items.enumerated().map { offset, item in
                var marker = ordered ? "\(start + offset). " : "- "
                if let checked = item.checked { marker += checked ? "[x] " : "[ ] " }
                let indent = String(repeating: " ", count: ordered ? "\(start + offset). ".count : 2)
                // One paragraph and nested lists stay tight; anything more gets blank lines, so paragraphs stay apart.
                let paragraphs = item.blocks.filter { if case .paragraph = $0 { return true }; return false }.count
                let tight = paragraphs <= 1 && item.blocks.allSatisfy { if case .paragraph = $0 { return true }; if case .list = $0 { return true }; return false }
                let body = item.blocks.map(write).filter { !$0.isEmpty }.joined(separator: tight ? "\n" : "\n\n")
                let lines = body.components(separatedBy: "\n")
                return marker + lines[0] + lines.dropFirst().map { $0.isEmpty ? "\n" : "\n" + indent + $0 }.joined()
            }.joined(separator: "\n")
        case .quote(let blocks):
            return write(blocks).components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
        case .table(let rows):
            let columns = rows.map(\.count).max() ?? 0
            guard columns > 0 else { return "" }
            let cells = rows.map { row in
                (0..<columns).map { $0 < row.count ? inline(row[$0], breaks: " ").replacingOccurrences(of: "|", with: "\\|") : "" }
            }
            let line = { (row: [String]) in "| " + row.joined(separator: " | ") + " |" }
            return ([line(cells[0]), line(Array(repeating: "---", count: columns))] + cells.dropFirst().map(line))
                .joined(separator: "\n")
        case .rule:
            return "---"
        }
    }

    // MARK: Inline

    private struct Segment {
        var text: String
        var style: Style
        var image: (alt: String, source: String)?
    }

    /// Runs as Markdown: whitespace collapsed as a browser shows it, emphasis and links around their text,
    /// and line breaks written as `breaks`.
    private static func inline(_ runs: [Run], breaks: String) -> String {
        // Collapse whitespace across runs, and trim it at the ends and around line breaks.
        var lines: [[Segment]] = [[]]
        var pendingSpace = false
        for run in runs {
            switch run {
            case .lineBreak:
                lines.append([])
                pendingSpace = false
            case .image(let alt, let source, let link):
                if pendingSpace, !lines[lines.count - 1].isEmpty { lines[lines.count - 1].append(Segment(text: " ", style: Style(link: link))) }
                pendingSpace = false
                lines[lines.count - 1].append(Segment(text: "", style: Style(link: link), image: (alt, source)))
            case .text(let text, let style):
                var current = ""
                for character in text {
                    if character.isWhitespace {
                        pendingSpace = true
                    } else {
                        if pendingSpace, !(lines[lines.count - 1].isEmpty && current.isEmpty) { current.append(" ") }
                        pendingSpace = false
                        current.append(character)
                    }
                }
                if !current.isEmpty { lines[lines.count - 1].append(Segment(text: current, style: style)) }
            }
        }
        let written = lines.map(writeLine).filter { !$0.isEmpty }
        return written.joined(separator: breaks)
    }

    /// One line of segments, grouped by link, with emphasis opened and closed around the text it covers.
    private static func writeLine(_ segments: [Segment]) -> String {
        var output = ""
        var index = 0
        while index < segments.count {
            let link = segments[index].style.link
            var end = index
            while end < segments.count, segments[end].style.link == link { end += 1 }
            let group = Array(segments[index..<end])
            let text = emphasized(group)
            if let link, !text.trimmingCharacters(in: .whitespaces).isEmpty {
                let leading = String(text.prefix { $0 == " " })
                let trailing = String(text.reversed().prefix { $0 == " " })
                let core = text.trimmingCharacters(in: .whitespaces)
                output += leading + "[" + core + "](" + destination(link) + ")" + trailing
            } else {
                output += text
            }
            index = end
        }
        return output
    }

    private enum Mark: String {
        case strike = "~~", bold = "**", italic = "*"
    }

    private static func marks(_ style: Style) -> [Mark] {
        (style.strike ? [.strike] : []) + (style.bold ? [.bold] : []) + (style.italic ? [.italic] : [])
    }

    /// Segments with their emphasis. Spaces at a segment's edges go outside the markers, where CommonMark
    /// needs them; marks still wanted by the next segment stay open.
    private static func emphasized(_ segments: [Segment]) -> String {
        var output = ""
        var open: [Mark] = []
        var pendingSpace = ""
        for segment in segments {
            let wanted = marks(segment.style)
            let leading = String(segment.text.prefix { $0 == " " })
            let trailing = String(segment.text.reversed().prefix { $0 == " " })
            let core = segment.image == nil ? String(segment.text.dropFirst(leading.count).dropLast(trailing.count)) : ""
            if core.isEmpty, segment.image == nil {
                pendingSpace += segment.text
                continue
            }
            // Close what this segment doesn't want, reopening anything closed on the way that it does.
            if let keep = open.firstIndex(where: { !wanted.contains($0) }) {
                for mark in open[keep...].reversed() { output += mark.rawValue }
                open.removeSubrange(keep...)
            }
            output += pendingSpace + leading
            pendingSpace = ""
            for mark in wanted where !open.contains(mark) {
                output += mark.rawValue
                open.append(mark)
            }
            if let image = segment.image {
                output += "![" + escaped(image.alt) + "](" + destination(image.source) + ")"
            } else if segment.style.code {
                output += codeSpan(core)
            } else {
                output += escaped(core)
            }
            pendingSpace = trailing
        }
        for mark in open.reversed() { output += mark.rawValue }
        return output + pendingSpace
    }

    private static func codeSpan(_ code: String) -> String {
        let fence = String(repeating: "`", count: longestRun(of: "`", in: code) + 1)
        let pad = code.hasPrefix("`") || code.hasSuffix("`") ? " " : ""
        return fence + pad + code + pad + fence
    }

    private static func destination(_ url: String) -> String {
        let spaced = url.replacingOccurrences(of: " ", with: "%20")
        var depth = 0
        for character in spaced {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1; if depth < 0 { break } }
        }
        return depth == 0 ? spaced : "<" + spaced + ">"
    }

    // MARK: Escaping

    /// Text with the characters that would start Markdown syntax escaped.
    private static func escaped(_ text: String) -> String {
        let characters = Array(text)
        var output = ""
        for (index, character) in characters.enumerated() {
            let before = index > 0 ? characters[index - 1] : " "
            let after = index + 1 < characters.count ? characters[index + 1] : " "
            switch character {
            case "\\", "*", "`", "[":
                output += "\\" + String(character)
            case "_":
                // Inside a word an underscore can't make emphasis, so snake_case stays as it is.
                output += before.isLetter || before.isNumber ? (after.isLetter || after.isNumber ? "_" : "\\_") : "\\_"
            case "~":
                output += before == "~" || after == "~" ? "\\~" : "~"
            case "<":
                output += after.isLetter || after == "/" || after == "!" || after == "?" ? "\\<" : "<"
            case "&":
                output += isEntityStart(characters, at: index) ? "\\&" : "&"
            default:
                output.append(character)
            }
        }
        return output
    }

    private static func isEntityStart(_ characters: [Character], at index: Int) -> Bool {
        var end = index + 1
        while end < characters.count, end - index <= 32, characters[end].isLetter || characters[end].isNumber || characters[end] == "#" { end += 1 }
        return end > index + 1 && end < characters.count && characters[end] == ";"
    }

    private static let lineStartSyntax = try! NSRegularExpression(
        pattern: "^(#{1,6}(?=\\s|$)|>|[-+](?=\\s|$)|=+\\s*$|-+\\s*$|\\d{1,9}(?=[.)](\\s|$)))")

    /// Lines that would start a heading, quote, list, or underline escaped at their first character.
    private static func escapingLineStarts(_ text: String) -> String {
        text.components(separatedBy: "\n").map { line in
            let ns = line as NSString
            guard let match = lineStartSyntax.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
            if let first = line.first, first.isNumber {
                // `1.` → `1\.`
                let end = NSMaxRange(match.range)
                return ns.substring(to: end) + "\\" + ns.substring(from: end)
            }
            return "\\" + line
        }.joined(separator: "\n")
    }

    private static func longestRun(of character: Character, in text: String) -> Int {
        var longest = 0, current = 0
        for each in text {
            current = each == character ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
}
