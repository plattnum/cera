import AppKit
import Markdown

/// Styles Markdown source in place, so it reads as a rendered document while
/// remaining plain text on disk. The text is parsed with swift-markdown
/// (CommonMark plus GitHub tables, task lists, and strikethrough). Syntax markers
/// (`**`, `#`, `[`, `](url)`, table pipes) are hidden on every line except the one
/// holding the insertion point.
struct MarkdownStyler {
    var theme: Theme = .midnight
    /// Flow hard-wrapped paragraphs into one (see `markSoftBreaks`). Off by default:
    /// Typora keeps a paragraph's line breaks as written.
    var joinsHardWrappedLines = false

    /// Used in place of hidden markers. Near-zero size keeps them out of the way
    /// without removing characters, so the text offsets never change.
    static let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    /// A paragraph with a fixed line height, like CSS `line-height`.
    static func paragraph(lineHeight: CGFloat, indent: CGFloat = 0, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0,
                          alignment: NSTextAlignment = .natural) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.alignment = alignment
        return style
    }

    /// Raises text so it sits in the middle of a fixed-height line, as CSS does,
    /// instead of at the bottom.
    static func baselineOffset(for font: NSFont, lineHeight: CGFloat) -> CGFloat {
        max(0, (lineHeight - (font.ascender - font.descender)) / 2)
    }

    func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: theme.bodyFont,
            .foregroundColor: theme.text,
            .paragraphStyle: Self.paragraph(lineHeight: theme.lineHeight, alignment: theme.bodyAlignment),
            .baselineOffset: Self.baselineOffset(for: theme.bodyFont, lineHeight: theme.lineHeight)
        ]
    }

    /// Styles the whole document.
    ///
    /// The work is done one region at a time (see `styleRegion`), because many small
    /// attribute changes in one huge text storage get slower as the document grows.
    ///
    /// - Parameters:
    ///   - caret: the insertion point; markers on its line stay visible.
    ///   - baseURL: the document's folder, for relative image paths.
    ///   - availableWidth: the text column's width, for sizing images and tables.
    func style(_ storage: NSTextStorage, caret: Int, baseURL: URL? = nil, availableWidth: CGFloat = 760,
               regionLength: Int = Self.regionLength) {
        let text = NSString(string: storage.string)
        guard text.length > 0 else {
            storage.setAttributes(bodyAttributes(), range: NSRange(location: 0, length: 0))
            return
        }
        let (blocks, found) = Self.structure(in: text)
        let definitions = Self.definitionText(found)
        for region in Self.regions(covering: blocks, length: text.length, target: regionLength) {
            styleRegion(storage, text: text, region: region, caret: caret, baseURL: baseURL,
                        availableWidth: availableWidth, definitions: definitions)
        }
    }

    /// The size of the pieces a document is styled in.
    static let regionLength = 32_000

    /// Styles one region of the document. `region` must start and end on boundaries
    /// between top-level blocks (as returned by `topLevelBlocks`).
    ///
    /// The region is parsed and styled on its own, in a small scratch copy, and the
    /// result is copied into `storage` in one ordered pass. `definitions` are the
    /// document's link reference definitions, so references in the region still resolve.
    func styleRegion(_ storage: NSTextStorage, text: NSString, region: NSRange, caret: Int, baseURL: URL?,
                     availableWidth: CGFloat, definitions: String) {
        guard region.length > 0, NSMaxRange(region) <= text.length else { return }
        let body = text.substring(with: region)
        let source = definitions.isEmpty ? body : body + "\n\n" + definitions
        // The parser reads front matter as blank lines; it is styled on its own.
        let (parsable, frontMatter) = FrontMatter.parsable(text, region: region)
        let parsed = definitions.isEmpty ? parsable : parsable + "\n\n" + definitions
        let scratch = NSTextStorage(string: source)
        let inRegion = caret >= region.location
            && (caret < NSMaxRange(region) || (caret == text.length && NSMaxRange(region) == text.length))
        let localCaret = inRegion ? caret - region.location : -1

        scratch.beginEditing()
        scratch.setAttributes(bodyAttributes(), range: NSRange(location: 0, length: scratch.length))
        let context = StyleContext(storage: scratch, theme: theme, caret: localCaret, baseURL: baseURL, availableWidth: availableWidth)
        context.joinsHardWrappedLines = joinsHardWrappedLines
        context.regionLength = region.length
        // Whether the line just before this region has text (so its first block follows a block).
        if region.location > 0 {
            let previous = text.lineRange(for: NSRange(location: region.location - 1, length: 0))
            context.precededByLine = !text.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        context.styleBlankLines()
        let document = Document(parsing: parsed)
        context.blockRanges = Self.blockRanges(of: document, in: context.text, map: context.map)
        // A table that interrupts a paragraph leaves the paragraph, and everything in it, without positions,
        // so none of it could be styled. Parsed apart, at the table's first line, both have them.
        if let split = Self.interruptedTableStart(in: document, blocks: context.blockRanges), split > 0, split < region.length {
            scratch.endEditing()
            for part in [NSRange(location: region.location, length: split),
                         NSRange(location: region.location + split, length: region.length - split)] {
                styleRegion(storage, text: text, region: part, caret: caret, baseURL: baseURL,
                            availableWidth: availableWidth, definitions: definitions)
            }
            return
        }
        var walker = StyleWalker(context: context)
        walker.visit(document)
        if let frontMatter { context.styleFrontMatter(frontMatter) }
        context.dimDefinitionLines()
        context.finish()
        scratch.endEditing()

        storage.beginEditing()
        scratch.enumerateAttributes(in: NSRange(location: 0, length: region.length)) { attributes, range, _ in
            storage.setAttributes(attributes, range: NSRange(location: region.location + range.location, length: range.length))
        }
        storage.endEditing()
    }

    // MARK: - Block structure

    /// The line ranges (including line breaks) of the top-level blocks in `region`
    /// (the whole text by default), in document coordinates.
    static func topLevelBlocks(in text: NSString, region: NSRange? = nil) -> [NSRange] {
        structure(in: text, region: region).blocks
    }

    /// A link reference definition found in the document: where it is, and its text
    /// with any list or quote prefix removed, ready to append to a region before parsing.
    struct Definition: Equatable {
        var location: Int
        var text: String
    }

    /// The top-level blocks of `region` (the whole text by default) and the link
    /// reference definitions in it, both in document coordinates.
    static func structure(in text: NSString, region: NSRange? = nil) -> (blocks: [NSRange], definitions: [Definition]) {
        let region = region ?? NSRange(location: 0, length: text.length)
        // Front matter is blank to the parser, and a block of its own.
        let (parsable, frontMatter) = FrontMatter.parsable(text, region: region)
        let piece = NSString(string: parsable)
        let map = SourceMap(piece)
        let document = Document(parsing: parsable)
        let ranges = blockRanges(of: document, in: piece, map: map)
        var definitions: [Definition] = []
        collectDefinitions(in: document, range: NSRange(location: 0, length: piece.length), childRanges: ranges,
                           text: piece, map: map, into: &definitions)
        let blocks = (frontMatter.map { [$0] } ?? [])
            + ranges.filter { $0.length > 0 }.map { NSRange(location: region.location + $0.location, length: $0.length) }
        let shifted = definitions.map { Definition(location: region.location + $0.location, text: $0.text) }
        return (blocks, shifted.sorted { $0.location < $1.location })
    }

    /// The definitions joined into Markdown text to append to a parsed region.
    static func definitionText(_ definitions: [Definition]) -> String {
        definitions.map(\.text).joined(separator: "\n\n")
    }

    /// Finds link reference definitions. The parser removes them without leaving a node,
    /// so they are found from what is missing:
    /// - lines in a container (document, list item, quote) that no child block covers, and
    /// - lines at the start of a paragraph beyond its count of text lines (the parser
    ///   reports the remaining text at the wrong lines, so positions can't be used).
    private static func collectDefinitions(in container: Markup, range: NSRange, childRanges: [NSRange],
                                           text: NSString, map: SourceMap, into definitions: inout [Definition]) {
        // Uncovered lines: runs that start like a definition are definitions.
        var run: [(range: NSRange, line: String)] = []
        var found: [Definition] = []
        func flush() {
            if let first = run.first, definitionRegex.firstMatch(in: first.line, range: NSRange(location: 0, length: (first.line as NSString).length)) != nil {
                found.append(Definition(location: first.range.location, text: run.map(\.line).joined(separator: "\n")))
            }
            run = []
        }
        // Child ranges are in order, so lines and children are walked together in one pass.
        let children = childRanges.filter { $0.length > 0 }.sorted { $0.location < $1.location }
        var next = 0
        text.enumerateSubstrings(in: range, options: .byLines) { line, lineRange, _, _ in
            while next < children.count, NSMaxRange(children[next]) <= lineRange.location { next += 1 }
            let covered = next < children.count && NSIntersectionRange(children[next], lineRange).length > 0
            let content = covered ? "" : strippingContainerPrefix(line ?? "")
            if covered || content.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                run.append((lineRange, content))
            }
        }
        flush()
        definitions += found

        for (child, childRange) in zip(container.children, childRanges) where childRange.length > 0 {
            if child is Paragraph || child is Heading {
                leadingDefinitions(of: child, range: childRange, text: text, into: &definitions)
            } else if child is ListItem || child is BlockQuote || child is UnorderedList || child is OrderedList {
                let grandchildren = child.children.map { grandchild -> NSRange in
                    guard let r = map.range(grandchild.range) else { return NSRange(location: childRange.location, length: 0) }
                    let start = text.lineRange(for: NSRange(location: min(r.location, text.length), length: 0)).location
                    let end = NSMaxRange(text.lineRange(for: NSRange(location: min(max(start, NSMaxRange(r) - 1), text.length), length: 0)))
                    let clampedStart = max(start, childRange.location)
                    return NSRange(location: clampedStart, length: max(0, min(end, NSMaxRange(childRange)) - clampedStart))
                }
                collectDefinitions(in: child, range: childRange, childRanges: grandchildren, text: text, map: map, into: &definitions)
            }
        }
    }

    /// Definitions at the start of a paragraph: one text line per line break inside
    /// it, plus one; source lines beyond that, at the start, were definitions.
    private static func leadingDefinitions(of block: Markup, range: NSRange, text: NSString, into definitions: inout [Definition]) {
        var sourceLines: [NSRange] = []
        text.enumerateSubstrings(in: range, options: .byLines) { line, lineRange, _, _ in
            if !(line ?? "").trimmingCharacters(in: .whitespaces).isEmpty { sourceLines.append(lineRange) }
        }
        if block is Heading, let last = sourceLines.last, isSetextUnderline(strippingContainerPrefix(text.substring(with: last))) {
            sourceLines.removeLast()
        }
        let consumed = sourceLines.count - (1 + lineBreaks(in: block))
        guard consumed > 0 else { return }
        let lines = sourceLines.prefix(consumed).map { strippingContainerPrefix(text.substring(with: $0)) }
        guard let first = lines.first,
              definitionRegex.firstMatch(in: first, range: NSRange(location: 0, length: (first as NSString).length)) != nil
        else { return }
        definitions.append(Definition(location: sourceLines[0].location, text: lines.joined(separator: "\n")))
    }

    private static let containerPrefixRegex = try! NSRegularExpression(pattern: "^[ \\t]*(?:>[ \\t]?)*(?:(?:[-*+]|\\d+[.)])[ \\t]+)?")

    /// A line without leading quote markers, list marker, and indentation.
    private static func strippingContainerPrefix(_ line: String) -> String {
        let ns = line as NSString
        guard let match = containerPrefixRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return line }
        return ns.substring(from: NSMaxRange(match.range))
    }

    private static let setextUnderlineRegex = try! NSRegularExpression(pattern: "^ {0,3}(=+|-+)[ \\t]*$")

    /// Whether a line is a === or --- heading underline.
    static func isSetextUnderline(_ line: String) -> Bool {
        setextUnderlineRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    private static func lineBreaks(in markup: Markup) -> Int {
        markup.children.reduce(0) { count, child in
            count + ((child is SoftBreak || child is LineBreak) ? 1 : lineBreaks(in: child))
        }
    }

    /// Where the first table that interrupts a paragraph starts, if there is one (see `blockRanges`).
    private static func interruptedTableStart(in document: Document, blocks: [NSRange]) -> Int? {
        let children = Array(document.children)
        for index in children.indices.dropFirst() where index < blocks.count {
            if children[index] is Table, children[index - 1] is Paragraph, children[index - 1].range == nil,
               blocks[index - 1].length > 0 {
                return blocks[index].location
            }
        }
        return nil
    }

    /// The line ranges of a parsed document's top-level blocks, one per child in order
    /// (zero length when a child has no position). A block ends where the next begins: the parser
    /// can report an end position on the following line (seen with underlined headings
    /// and unclosed code fences), and overlapping blocks would make the result depend
    /// on where parsing started.
    static func blockRanges(of document: Document, in text: NSString, map: SourceMap) -> [NSRange] {
        let children = Array(document.children)
        var spans: [(start: Int, end: Int)?] = children.map { child in
            guard let range = map.range(child.range) else { return nil }
            let start = text.lineRange(for: NSRange(location: min(range.location, text.length), length: 0)).location
            let lastCharacter = max(start, NSMaxRange(range) - 1)
            let end = NSMaxRange(text.lineRange(for: NSRange(location: min(lastCharacter, text.length), length: 0)))
            return (start, end)
        }
        // A table that interrupts a paragraph is reported from the paragraph's first line, and the paragraph
        // has no position. The table is its last lines (one per body row, the delimiter, and the header), so
        // it starts there, and the paragraph gets the lines before it.
        for (index, child) in children.enumerated() {
            guard let table = child as? Table, let span = spans[index] else { continue }
            var start = text.lineRange(for: NSRange(location: span.end - 1, length: 0)).location
            for _ in 0..<(table.body.childCount + 1) where start > span.start {
                start = text.lineRange(for: NSRange(location: start - 1, length: 0)).location
            }
            spans[index] = (start, span.end)
            if start > span.start, index > 0, spans[index - 1] == nil, children[index - 1] is Paragraph {
                spans[index - 1] = (span.start, start)
            }
        }
        // The start of the next positioned block after each index, found in one backward pass.
        var nextStarts = [Int](repeating: Int.max, count: spans.count)
        var following = Int.max
        for index in spans.indices.reversed() {
            nextStarts[index] = following
            if let span = spans[index] { following = span.start }
        }
        var blocks: [NSRange] = []
        var previousEnd = 0
        for (index, span) in spans.enumerated() {
            guard let span else {
                blocks.append(NSRange(location: previousEnd, length: 0))
                continue
            }
            let nextStart = nextStarts[index]
            let start = max(span.start, previousEnd)
            let end = max(start, min(span.end, nextStart))
            blocks.append(NSRange(location: start, length: end - start))
            previousEnd = end
        }
        return blocks
    }

    /// Splits `[0, length)` into regions of about `target` characters, cutting only
    /// between blocks. The regions cover the text with no gaps.
    static func regions(covering blocks: [NSRange], length: Int, target: Int) -> [NSRange] {
        var regions: [NSRange] = []
        var start = 0
        for block in blocks where block.location - start >= target {
            regions.append(NSRange(location: start, length: block.location - start))
            start = block.location
        }
        if length > start { regions.append(NSRange(location: start, length: length - start)) }
        return regions
    }

    fileprivate static let definitionRegex = try! NSRegularExpression(pattern: "^ {0,3}\\[[^\\]\\n]+\\]:")

    /// Whether `region` holds an odd number of code fence lines, i.e. leaves a fence
    /// open, which can change how everything after it parses.
    static func leavesFenceOpen(_ text: NSString, region: NSRange) -> Bool {
        var fences = 0
        text.enumerateSubstrings(in: region, options: .byLines) { line, _, _, _ in
            let trimmed = (line ?? "").drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { fences += 1 }
        }
        return fences % 2 == 1
    }
}

// MARK: - Tree walk

private struct StyleWalker: MarkupWalker {
    let context: StyleContext

    mutating func visitHeading(_ heading: Heading) {
        context.styleHeading(heading)
        descendInto(heading)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        if !context.styleImageParagraph(paragraph) {
            context.hideLineIndentation(in: paragraph)
            context.markSoftBreaks(in: paragraph)
            descendInto(paragraph)
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        context.styleBlockQuote(blockQuote)
        descendInto(blockQuote)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        context.styleListItem(listItem)
        descendInto(listItem)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        context.styleCodeBlock(codeBlock)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        context.styleHTML(html)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        context.styleRule(thematicBreak)
    }

    mutating func visitTable(_ table: Table) {
        context.styleTable(table)
        descendInto(table)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        context.styleInlineCode(inlineCode)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        context.styleDelimited(emphasis, as: .italic)
        descendInto(emphasis)
    }

    mutating func visitStrong(_ strong: Strong) {
        context.styleDelimited(strong, as: .bold)
        descendInto(strong)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        context.styleDelimited(strikethrough, as: .strikethrough)
        descendInto(strikethrough)
    }

    mutating func visitLink(_ link: Link) {
        context.styleLink(link)
        descendInto(link)
    }

    mutating func visitImage(_ image: Image) {
        context.styleInlineImage(image)
        descendInto(image)
    }

    mutating func visitInlineHTML(_ html: InlineHTML) {
        context.styleHTML(html)
    }

    mutating func visitText(_ text: Text) {
        context.hideEscapes(in: text)
        context.styleBareURLs(in: text)
    }
}

// MARK: - Styling state and rules

private final class StyleContext {
    enum Emphasis { case italic, bold, strikethrough }

    /// A table found in the tree, laid out once inline styling and marker hiding are done.
    struct TablePlan {
        struct Row {
            let line: NSRange
            let isHeader: Bool
            /// Cell content ranges, or nil when the row is being edited and shows its source.
            var cells: [NSRange]?
        }
        var rows: [Row]
        let alignments: [Table.ColumnAlignment?]
        let indent: CGFloat
    }

    let storage: NSTextStorage
    /// One immutable copy of the text per styling pass. Reading `storage.string`
    /// repeatedly would copy the whole document each time.
    let text: NSString
    let source: String
    let theme: Theme
    let map: SourceMap
    let baseURL: URL?
    let availableWidth: CGFloat
    let activeLineStart: Int

    private var markers: [NSRange] = []
    private var tables: [TablePlan] = []
    /// The line ranges of the document's top-level blocks, indexed like its children.
    var blockRanges: [NSRange] = []
    var joinsHardWrappedLines = false
    /// Whether the line just before this region (in the document) has text.
    var precededByLine = false
    /// The region's length, without the link definitions appended after it for parsing.
    var regionLength = Int.max
    /// Space added after hidden code-span backticks, applied once markers are hidden.
    private var paddingKerns: [(location: Int, amount: CGFloat)] = []

    private static let listMarkerRegex = try! NSRegularExpression(pattern: "([-*+]|\\d+[.)])([ \\t]+|$)(\\[[ xX]\\][ \\t]+)?")
    /// Indentation and quote markers at the start of a line.
    private static let lineIndentRegex = try! NSRegularExpression(pattern: "[ \\t]*(?:>[ \\t]?)*[ \\t]*")
    /// Quote markers, then the indentation of an indented code line (group 1).
    private static let codeIndentRegex = try! NSRegularExpression(pattern: "(?:[ \\t]*>[ \\t]?)*( {4}|\\t)")
    private static let quoteMarkerRegex = try! NSRegularExpression(pattern: "^[ \\t]*(>[ \\t]?)+")
    /// A fence line, after any quote markers, list marker, and indentation: the fence
    /// (group 1) and what follows it (group 2).
    private static let fenceRegex = try! NSRegularExpression(
        pattern: "(?:[ \\t]*>[ \\t]?|[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+|[ \\t])*(`{3,}|~{3,})(.*)")
    /// A web address in plain text; trailing punctuation is left out, as in GitHub autolinks.
    private static let bareURLRegex = try! NSRegularExpression(
        pattern: "(?:https?://|www\\.)[^\\s<>\\[\\]()]*[^\\s<>\\[\\]().,;:!?'\"]", options: [.caseInsensitive])

    init(storage: NSTextStorage, theme: Theme, caret: Int, baseURL: URL?, availableWidth: CGFloat) {
        self.storage = storage
        self.text = NSString(string: storage.string)
        self.source = text as String
        self.theme = theme
        self.map = SourceMap(text)
        self.baseURL = baseURL
        self.availableWidth = availableWidth
        // A caret outside this region (-1) means no line in it is being edited.
        self.activeLineStart = caret < 0 ? -1 : text.lineRange(for: NSRange(location: min(caret, text.length), length: 0)).location
    }

    // MARK: Helpers

    /// The node's text range, without trailing line breaks: whether the parser
    /// includes the final line break depends on what follows, which must not matter.
    func range(_ markup: Markup) -> NSRange? {
        guard var range = map.range(markup.range), NSMaxRange(range) <= text.length else { return nil }
        // Keep every node inside its top-level block: the parser can report an end
        // position in the next block, which would style text that isn't part of the node.
        var root = markup
        while let parent = root.parent, !(parent is Document) { root = parent }
        if root.parent is Document, root.indexInParent < blockRanges.count {
            let block = blockRanges[root.indexInParent]
            let start = min(max(range.location, block.location), NSMaxRange(block))
            let end = max(start, min(NSMaxRange(range), NSMaxRange(block)))
            range = NSRange(location: start, length: end - start)
        }
        while range.length > 0, [10, 13].contains(text.character(at: NSMaxRange(range) - 1)) {
            range.length -= 1
        }
        return range
    }

    func onActiveLine(_ location: Int) -> Bool {
        text.lineRange(for: NSRange(location: min(location, text.length), length: 0)).location == activeLineStart
    }

    func addMarker(_ range: NSRange) {
        if range.length > 0 { markers.append(range) }
    }

    func setParagraph(_ style: NSParagraphStyle, over range: NSRange) {
        storage.addAttribute(.paragraphStyle, value: style, range: text.lineRange(for: range))
    }

    func transformFont(_ range: NSRange, _ transform: (NSFont) -> NSFont) {
        var runs: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            runs.append((subrange, transform((value as? NSFont) ?? theme.bodyFont)))
        }
        for (subrange, font) in runs {
            storage.addAttribute(.font, value: font, range: subrange)
        }
    }

    /// The source lines covering `range`, each without its line break.
    func lines(in range: NSRange) -> [NSRange] {
        var result: [NSRange] = []
        text.enumerateSubstrings(in: text.lineRange(for: range), options: .byLines) { _, line, _, _ in
            result.append(line)
        }
        return result
    }

    /// How far a block is indented by the quotes and list items around it (and itself).
    func indent(for markup: Markup?) -> CGFloat {
        var total: CGFloat = 0
        var node = markup
        while let current = node {
            if current is BlockQuote { total += theme.quoteIndent }
            if current is ListItem { total += theme.listIndent }
            node = current.parent
        }
        return total
    }

    // MARK: Blocks

    /// Blank lines are the gaps between blocks, like CSS margins.
    /// Front matter (see `FrontMatter`): source for other tools, muted, in the code font.
    func styleFrontMatter(_ range: NSRange) {
        storage.addAttributes([
            .font: theme.codeFont,
            .foregroundColor: theme.marker,
            .paragraphStyle: MarkdownStyler.paragraph(lineHeight: theme.codeLineHeight),
            .baselineOffset: MarkdownStyler.baselineOffset(for: theme.codeFont, lineHeight: theme.codeLineHeight)
        ], range: range)
    }

    func styleBlankLines() {
        text.enumerateSubstrings(in: NSRange(location: 0, length: text.length), options: .byLines) { line, _, enclosing, _ in
            guard (line ?? "").trimmingCharacters(in: .whitespaces).isEmpty else { return }
            self.storage.addAttributes([
                .paragraphStyle: MarkdownStyler.paragraph(lineHeight: self.theme.blockSpacing),
                .baselineOffset: 0
            ], range: enclosing)
        }
    }

    func styleHeading(_ heading: Heading) {
        guard let range = range(heading), range.length > 0 else { return }
        let style = theme.headings[min(max(heading.level, 1), 6) - 1]
        let lineStart = text.lineRange(for: NSRange(location: range.location, length: 0)).location
        var content = range

        if text.character(at: range.location) == 35 { // "#": ATX heading
            var end = range.location
            while end < NSMaxRange(range), text.character(at: end) == 35 { end += 1 }
            while end < NSMaxRange(range), [32, 9].contains(text.character(at: end)) { end += 1 }
            addMarker(NSRange(location: lineStart, length: end - lineStart))
            content = NSRange(location: end, length: NSMaxRange(range) - end)
        } else if let underline = lines(in: range).dropFirst().first(where: { MarkdownStyler.isSetextUnderline(text.substring(with: $0)) })
                    .map({ text.lineRange(for: $0) }) {
            // Setext heading: text lines, then a === or --- underline. The underline is
            // found by its shape: the parser may report the heading's end a line too far.
            content = NSRange(location: range.location, length: underline.location - range.location)
            if !onActiveLine(underline.location) {
                addMarker(underline)
                storage.addAttribute(.paragraphStyle, value: MarkdownStyler.paragraph(lineHeight: 1), range: underline)
            }
        } else {
            let underline = text.lineRange(for: NSRange(location: NSMaxRange(range) - 1, length: 0))
            if underline.location > range.location {
                content = NSRange(location: range.location, length: underline.location - range.location)
                if !onActiveLine(underline.location) {
                    addMarker(underline)
                    storage.addAttribute(.paragraphStyle, value: MarkdownStyler.paragraph(lineHeight: 1), range: underline)
                }
            }
        }

        let headingText = NSRange(location: lineStart, length: NSMaxRange(content) - lineStart)
        storage.addAttributes([
            .font: style.font,
            .foregroundColor: style.color,
            .kern: style.kern,
            .baselineOffset: MarkdownStyler.baselineOffset(for: style.font, lineHeight: style.lineHeight)
        ], range: headingText)
        setParagraph(MarkdownStyler.paragraph(lineHeight: style.lineHeight, indent: indent(for: heading),
                                              spacingBefore: style.spaceBefore, alignment: style.alignment), over: content)
        switch style.rule {
        case .none: break
        case .full: storage.addAttribute(.headingUnderline, value: "full", range: content)
        case .short: storage.addAttribute(.headingUnderline, value: "short", range: content)
        }
        if style.uppercase {
            storage.addAttribute(.uppercase, value: true, range: content)
        }
    }

    /// Leading spaces on a paragraph's lines don't change its meaning in Markdown (the
    /// text is indented by its list or quote instead), so they hide like syntax.
    func hideLineIndentation(in paragraph: Paragraph) {
        guard let range = range(paragraph) else { return }
        for line in lines(in: range) {
            if let match = Self.lineIndentRegex.firstMatch(in: source, options: .anchored, range: line), match.range.length > 0 {
                addMarker(match.range)
            }
        }
    }

    /// Whether any line of `range` is the line being edited.
    func containsActiveLine(_ range: NSRange) -> Bool {
        activeLineStart >= 0 && lines(in: range).contains { $0.location == activeLineStart }
    }

    /// A single line break inside a paragraph is a soft break: Markdown reads it as a
    /// space, so the paragraph flows as one. The layout manager lays marked breaks out as
    /// spaces. The paragraph being edited keeps its real line breaks, so Return and the
    /// arrow keys behave as expected. A hard break (two trailing spaces, or a backslash)
    /// stays a line break.
    func markSoftBreaks(in paragraph: Paragraph) {
        guard joinsHardWrappedLines, let range = range(paragraph), !containsActiveLine(range) else { return }
        let paragraphLines = lines(in: range)
        for line in paragraphLines.dropLast() {
            let content = text.substring(with: line)
            if content.hasSuffix("  ") || content.hasSuffix("\\") { continue }
            let full = text.lineRange(for: line)
            let terminator = NSRange(location: NSMaxRange(line), length: NSMaxRange(full) - NSMaxRange(line))
            if terminator.length > 0 {
                storage.addAttribute(.softBreak, value: true, range: terminator)
            }
        }
    }

    /// A paragraph holding only an image is drawn as the image. Returns false when
    /// it isn't one, the image can't be loaded, or its line is being edited.
    func styleImageParagraph(_ paragraph: Paragraph) -> Bool {
        guard paragraph.childCount == 1,
              let image = paragraph.child(at: 0) as? Image,
              let source = image.source,
              let range = range(paragraph), range.length > 0,
              !onActiveLine(range.location),
              let url = ImageStore.resolve(source, relativeTo: baseURL),
              let picture = ImageStore.shared.image(for: url),
              picture.size.width > 0, picture.size.height > 0
        else { return false }

        let indent = indent(for: paragraph)
        let maxWidth = max(40, availableWidth - indent)
        var scale: CGFloat = 1
        if let (width, height) = ImageSize.requested(alt: image.plainText) {
            scale = width / picture.size.width
            if let height { scale = min(scale, height / picture.size.height) }
        }
        scale = min(scale, maxWidth / picture.size.width)
        let size = NSSize(width: (picture.size.width * scale).rounded(), height: (picture.size.height * scale).rounded())

        addMarker(range)
        setParagraph(MarkdownStyler.paragraph(lineHeight: size.height, indent: indent), over: range)
        storage.addAttributes([
            .baselineOffset: 0,
            .imageBlock: ImageBlock(image: picture, size: size, x: indent)
        ], range: range)
        return true
    }

    func styleBlockQuote(_ quote: BlockQuote) {
        guard let range = range(quote) else { return }
        let barX = indent(for: quote.parent) + theme.quoteBarX
        let style = MarkdownStyler.paragraph(lineHeight: theme.lineHeight, indent: indent(for: quote), alignment: theme.bodyAlignment)

        for line in lines(in: range) {
            storage.addAttribute(.paragraphStyle, value: style, range: text.lineRange(for: line))
            var bars = storage.attribute(.quoteBar, at: line.location, effectiveRange: nil) as? [CGFloat] ?? []
            bars.append(barX)
            storage.addAttribute(.quoteBar, value: bars, range: text.lineRange(for: line))
            guard line.length > 0 else { continue }
            storage.addAttribute(.foregroundColor, value: theme.quoteText, range: line)
            if theme.quoteItalic {
                transformFont(line) { NSFontManager.shared.convert($0, toHaveTrait: .italicFontMask) }
            }
            if let marker = Self.quoteMarkerRegex.firstMatch(in: source, options: .anchored, range: line) {
                addMarker(marker.range)
            }
        }
    }

    func styleListItem(_ item: ListItem) {
        guard let range = range(item), range.length > 0 else { return }
        let indent = indent(for: item)
        // The gap between items goes after an item's last line only, so a wrapped item reads as one block.
        // Blank lines keep their own gap: the parser sometimes counts blank lines after a
        // list's last item as part of it, depending on what follows.
        // While the item is being edited its lines are separate, so only the last one gets the gap.
        // Otherwise its lines flow as one paragraph (see markSoftBreaks), which takes its spacing
        // from its first line, so every line gets the gap.
        let itemLines = lines(in: range).filter { !text.substring(with: $0).trimmingCharacters(in: .whitespaces).isEmpty }
        let editing = containsActiveLine(range)
        for line in itemLines {
            let style = MarkdownStyler.paragraph(lineHeight: theme.lineHeight, indent: indent,
                                                 spacingAfter: !editing || line == itemLines.last ? theme.listItemSpacing : 0,
                                                 alignment: theme.bodyAlignment)
            storage.addAttribute(.paragraphStyle, value: style, range: text.lineRange(for: line))
        }

        let firstLine = text.lineRange(for: NSRange(location: range.location, length: 0))
        guard let match = Self.listMarkerRegex.firstMatch(
            in: source, options: .anchored,
            range: NSRange(location: range.location, length: NSMaxRange(firstLine) - range.location))
        else { return }
        let marker = NSRange(location: firstLine.location, length: NSMaxRange(match.range) - firstLine.location)
        addMarker(marker)
        guard !onActiveLine(marker.location) else { return }

        // The parser doesn't see task items inside quotes (`> - [ ] a`), so the marker's own checkbox counts too.
        let box = match.range(at: 3)
        let symbol: String
        if let checkbox = item.checkbox {
            symbol = checkbox == .checked ? "☑" : "☐"
        } else if box.location != NSNotFound {
            symbol = text.character(at: box.location + 1) == 32 ? "☐" : "☑"
        } else if let list = item.parent as? OrderedList {
            symbol = "\(Int(list.startIndex) + item.indexInParent)."
        } else {
            var depth = 0
            var node: Markup? = item
            while let current = node {
                if current is ListItem { depth += 1 }
                node = current.parent
            }
            switch depth {
            case 1: symbol = theme.bullet == .square ? "▪" : "•"
            case 2: symbol = "◦"
            default: symbol = "▪"
            }
        }
        storage.addAttribute(.listBullet, value: symbol, range: marker)
    }

    func styleCodeBlock(_ block: CodeBlock) {
        guard let range = range(block), range.length > 0 else { return }
        if styleMermaidDiagram(block, range: range) { return }
        let lines = text.lineRange(for: range)
        let base = indent(for: block)
        storage.addAttributes([
            .font: theme.codeFont,
            .foregroundColor: theme.codeText,
            .codeBlock: NSNumber(value: Double(base + theme.codePanelX)),
            .paragraphStyle: MarkdownStyler.paragraph(lineHeight: theme.codeLineHeight, indent: base + theme.codeIndent),
            .baselineOffset: MarkdownStyler.baselineOffset(for: theme.codeFont, lineHeight: theme.codeLineHeight)
        ], range: lines)

        let opening = text.lineRange(for: NSRange(location: lines.location, length: 0))
        guard let openingFence = fence(onLine: opening), !block.code.hasPrefix(openingFence) else {
            // Indented code block: the four spaces of indentation are syntax, like a fence.
            for line in self.lines(in: range) {
                if let match = Self.codeIndentRegex.firstMatch(in: source, options: .anchored, range: line) {
                    addMarker(match.range(at: 1))
                }
            }
            return
        }

        let closing = text.lineRange(for: NSRange(location: NSMaxRange(lines) - 1, length: 0))
        let closed = closing.location > opening.location
            && CodeBlockText.closingFence(of: block, in: text, opening: self.lines(in: opening).first ?? opening) != nil

        // The language, as written, in the panel's corner; not while its fence line shows it.
        if let language = block.language?.split(whereSeparator: \.isWhitespace).first, !onActiveLine(opening.location) {
            storage.addAttribute(.codeLanguage, value: String(language), range: NSRange(location: lines.location, length: 1))
        }
        let bodyEnd = closed ? closing.location : NSMaxRange(lines)
        if bodyEnd > NSMaxRange(opening) {
            colorCode(block, body: NSRange(location: NSMaxRange(opening), length: bodyEnd - NSMaxRange(opening)))
        }

        // Fence lines are syntax. When not being edited they shrink to the panel's padding.
        for fence in closed ? [opening, closing] : [opening] where !onActiveLine(fence.location) {
            addMarker(fence)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyler.paragraph(lineHeight: theme.codePadding), range: fence)
        }
    }

    /// Syntax colors for a fenced block's code: tree-sitter for the languages it has a grammar
    /// for, the simple keyword colorer for a few others and for blocks too long to parse.
    func colorCode(_ block: CodeBlock, body: NSRange) {
        if let language = CodeLanguages.language(info: block.language),
           let runs = SyntaxHighlighter.shared.runs(for: block.code, language: language) {
            apply(runs, code: block.code, body: body)
            return
        }
        CodeHighlighter(colors: theme.syntax).highlight(storage, text: text, range: body,
                                                        language: CodeLanguages.fenceName(info: block.language) ?? "")
    }

    /// Colors the body lines from runs measured in the block's code. The code is each body line
    /// without the quote markers or list indentation that nest the block, so each code line is
    /// the end of its body line; a line that isn't (tabs in a nesting prefix) is left uncolored.
    private func apply(_ runs: [SyntaxRun], code: String, body: NSRange) {
        guard !runs.isEmpty else { return }
        let codeText = code as NSString
        let bodyLines = lines(in: body)
        var codeStart = 0
        var next = 0 // The first run that could reach the current line.
        for bodyLine in bodyLines {
            guard codeStart < codeText.length else { break }
            var codeEnd = codeText.range(of: "\n", range: NSRange(location: codeStart, length: codeText.length - codeStart)).location
            if codeEnd == NSNotFound { codeEnd = codeText.length }
            var contentEnd = codeEnd
            if contentEnd > codeStart, codeText.character(at: contentEnd - 1) == 13 { contentEnd -= 1 } // \r
            let codeLine = NSRange(location: codeStart, length: contentEnd - codeStart)
            defer { codeStart = codeEnd + 1 }
            guard codeLine.length > 0, codeLine.length <= bodyLine.length,
                  text.substring(with: NSRange(location: NSMaxRange(bodyLine) - codeLine.length, length: codeLine.length))
                    == codeText.substring(with: codeLine)
            else { continue }
            let offset = NSMaxRange(bodyLine) - NSMaxRange(codeLine)
            while next < runs.count, runs[next].location + runs[next].length <= codeLine.location { next += 1 }
            var index = next
            while index < runs.count, runs[index].location < NSMaxRange(codeLine) {
                let run = runs[index]
                let start = max(run.location, codeLine.location), end = min(run.location + run.length, NSMaxRange(codeLine))
                if start < end, let color = theme.syntax.color(for: run.role) {
                    storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: start + offset, length: end - start))
                }
                index += 1
            }
        }
    }

    /// The fence on a line, after any quote markers, list marker, and indentation, with what
    /// follows it; nil when the line isn't a fence line. An indented code block whose first
    /// line looks like a fence keeps that line in its code, which tells the two apart.
    private func fence(onLine line: NSRange) -> String? {
        let content = lines(in: line).first ?? line
        guard let match = Self.fenceRegex.firstMatch(in: source, options: .anchored, range: content) else { return nil }
        return text.substring(with: NSRange(location: match.range(at: 1).location,
                                            length: NSMaxRange(content) - match.range(at: 1).location))
    }

    /// A closed ```mermaid block is drawn as its diagram while the cursor is elsewhere, like an
    /// image: its first line takes the diagram's height and the rest collapse, with all the
    /// text hidden. Returns false when the block isn't one, is being edited, or can't be drawn,
    /// so it is styled as code.
    func styleMermaidDiagram(_ block: CodeBlock, range: NSRange) -> Bool {
        guard MermaidDiagrams.isMermaid(info: block.language), !containsActiveLine(range) else { return false }
        let blockLines = lines(in: range)
        guard blockLines.count >= 2, let first = blockLines.first,
              Self.fenceRegex.firstMatch(in: source, options: .anchored, range: first) != nil,
              CodeBlockText.closingFence(of: block, in: text, opening: first) != nil,
              let picture = MermaidDiagrams.shared.image(for: block.code, theme: theme)
        else { return false }

        let indent = indent(for: block)
        // Drawn so node labels match the body text, but never wider than the column.
        let scale = min(MermaidDiagrams.scale(for: theme), max(40, availableWidth - indent) / picture.size.width)
        let size = NSSize(width: (picture.size.width * scale).rounded(), height: (picture.size.height * scale).rounded())
        let collapsed = MarkdownStyler.paragraph(lineHeight: 0.01)
        for line in blockLines {
            addMarker(line)
            setParagraph(line == first ? MarkdownStyler.paragraph(lineHeight: size.height, indent: indent) : collapsed, over: line)
        }
        let key = "mermaid\u{0}" + theme.name + "\u{0}" + block.code
        storage.addAttributes([.baselineOffset: 0, .imageBlock: ImageBlock(image: picture, size: size, x: indent, key: key)], range: first)
        return true
    }

    func styleHTML(_ html: Markup) {
        guard let range = range(html) else { return }
        storage.addAttribute(.foregroundColor, value: theme.marker, range: range)
    }

    func styleRule(_ rule: ThematicBreak) {
        guard let range = range(rule), range.length > 0 else { return }
        if onActiveLine(range.location) {
            storage.addAttribute(.foregroundColor, value: theme.marker, range: range)
        } else {
            addMarker(range)
            storage.addAttribute(.horizontalRule, value: true, range: text.lineRange(for: range))
        }
    }

    func styleTable(_ table: Table) {
        guard let range = range(table) else { return }
        // From the end: a table that interrupts a paragraph is reported from the paragraph's first line.
        let rowLines = Array(lines(in: range).suffix(table.body.childCount + 2))
        guard rowLines.count >= 2 else { return }

        // Line 1 is the header, line 2 the |---| delimiter, the rest the body.
        var rows = [TablePlan.Row(line: rowLines[0], isHeader: true)]
        rows += rowLines.dropFirst(2).map { TablePlan.Row(line: $0, isHeader: false) }
        tables.append(TablePlan(rows: rows, alignments: table.columnAlignments, indent: indent(for: table)))

        let delimiter = rowLines[1]
        if !onActiveLine(delimiter.location) {
            addMarker(delimiter)
            storage.addAttribute(.paragraphStyle, value: MarkdownStyler.paragraph(lineHeight: 1), range: text.lineRange(for: delimiter))
        }
    }

    // MARK: Inline

    func styleInlineCode(_ code: InlineCode) {
        guard let range = range(code), range.length > 1 else { return }
        var ticks = 0
        while ticks < range.length / 2, text.character(at: range.location + ticks) == 96 { ticks += 1 }
        storage.addAttributes([.font: theme.codeFont, .foregroundColor: theme.codeText], range: range)
        let opening = NSRange(location: range.location, length: ticks)
        let closing = NSRange(location: NSMaxRange(range) - ticks, length: ticks)
        addMarker(opening)
        addMarker(closing)
        // The layout manager draws the background box. Padding is space after each hidden
        // run of backticks: inside the box before the code, and outside it after.
        if onActiveLine(range.location) {
            storage.addAttribute(.inlineCode, value: true, range: range)
        } else {
            storage.addAttribute(.inlineCode, value: true, range: NSRange(location: NSMaxRange(opening), length: closing.location - NSMaxRange(opening)))
            if theme.inlineCodePadding > 0 {
                paddingKerns.append((NSMaxRange(opening) - 1, theme.inlineCodePadding))
                paddingKerns.append((NSMaxRange(closing) - 1, theme.inlineCodePadding))
            }
        }
    }

    func styleDelimited(_ markup: Markup, as kind: Emphasis) {
        guard var range = range(markup), range.length > 1 else { return }
        // In ***text***, the parser reports the inner node with its parent's range;
        // step inside the markers of enclosing nodes that start at the same place.
        var inset = 0
        var ancestor = markup.parent
        while let outer = ancestor, outer is Markdown.Emphasis || outer is Strong || outer is Strikethrough,
              self.range(outer)?.location == range.location {
            inset += outer is Markdown.Emphasis ? 1 : 2
            ancestor = outer.parent
        }
        guard range.length > 2 * inset + 1 else { return }
        range = NSRange(location: range.location + inset, length: range.length - 2 * inset)
        let delimiter = text.character(at: range.location)
        var width = 0
        let limit = kind == .italic ? 1 : 2
        while width < limit, width < range.length / 2, text.character(at: range.location + width) == delimiter { width += 1 }
        let content = NSRange(location: range.location + width, length: range.length - 2 * width)

        switch kind {
        case .italic:
            transformFont(content) { NSFontManager.shared.convert($0, toHaveTrait: .italicFontMask) }
        case .bold:
            transformFont(content) { NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask) }
            if let color = theme.strongColor {
                storage.addAttribute(.foregroundColor, value: color, range: content)
            }
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
        }
        addMarker(NSRange(location: range.location, length: width))
        addMarker(NSRange(location: NSMaxRange(range) - width, length: width))
    }

    func styleLink(_ link: Link) {
        guard let range = range(link), range.length > 0 else { return }
        let first = text.character(at: range.location)
        let label: NSRange
        if first == 91 { // "[label](url)"
            label = labelRange(of: link, opening: 1, in: range)
            addMarker(NSRange(location: range.location, length: 1))
            addMarker(NSRange(location: NSMaxRange(label), length: NSMaxRange(range) - NSMaxRange(label)))
        } else if first == 60, range.length > 2 { // "<url>"
            label = NSRange(location: range.location + 1, length: range.length - 2)
            addMarker(NSRange(location: range.location, length: 1))
            addMarker(NSRange(location: NSMaxRange(range) - 1, length: 1))
        } else { // bare URL
            label = range
        }
        storage.addAttribute(.foregroundColor, value: theme.link, range: label)
        if theme.linkUnderline {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: label)
        }
        if let destination = link.destination, let url = LinkResolver.resolve(destination, relativeTo: baseURL), label.length > 0 {
            storage.addAttributes([
                .linkTarget: url,
                .toolTip: "\(destination)\n⌘-click to open"
            ], range: label)
        }
    }

    /// Web addresses typed as plain text become links, like GitHub's autolinks.
    /// A backslash before punctuation escapes it; the backslash is syntax and hides.
    func hideEscapes(in textNode: Text) {
        guard let range = range(textNode), range.length > 1 else { return }
        var index = range.location
        while index < NSMaxRange(range) - 1 {
            if text.character(at: index) == 92, let scalar = Unicode.Scalar(text.character(at: index + 1)),
               CharacterSet.punctuationCharacters.union(.symbols).contains(scalar) {
                addMarker(NSRange(location: index, length: 1))
                index += 2
            } else {
                index += 1
            }
        }
    }

    /// Link reference definitions (`[id]: url`) aren't shown in rendered Markdown; here they
    /// stay visible for editing, dimmed like other syntax.
    func dimDefinitionLines() {
        var gapStart = 0
        func scan(_ gap: NSRange) {
            guard gap.length > 0 else { return }
            for line in lines(in: gap) where line.length > 0 {
                if MarkdownStyler.definitionRegex.firstMatch(in: source, options: .anchored, range: line) != nil {
                    storage.addAttribute(.foregroundColor, value: theme.marker, range: line)
                }
            }
        }
        for block in blockRanges where block.length > 0 {
            scan(NSRange(location: gapStart, length: max(0, block.location - gapStart)))
            gapStart = max(gapStart, NSMaxRange(block))
        }
        scan(NSRange(location: gapStart, length: max(0, text.length - gapStart)))
    }

    func styleBareURLs(in textNode: Text) {
        var node = textNode.parent
        while let current = node {
            if current is Link || current is Image { return }
            node = current.parent
        }
        guard let range = range(textNode), range.length > 3 else { return }
        for match in Self.bareURLRegex.matches(in: source, range: range) {
            let address = text.substring(with: match.range)
            guard let url = LinkResolver.resolve(address, relativeTo: nil) else { continue }
            storage.addAttributes([
                .foregroundColor: theme.link,
                .linkTarget: url,
                .toolTip: "\(address)\n⌘-click to open"
            ], range: match.range)
            if theme.linkUnderline {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            }
        }
    }

    /// An image inside running text shows its alt text, styled like a link.
    func styleInlineImage(_ image: Image) {
        guard let range = range(image), range.length > 2 else { return }
        let label = labelRange(of: image, opening: 2, in: range)
        guard label.length > 0 else { return } // No alt text: leave the source visible.
        storage.addAttribute(.foregroundColor, value: theme.link, range: label)
        addMarker(NSRange(location: range.location, length: 2))
        addMarker(NSRange(location: NSMaxRange(label), length: NSMaxRange(range) - NSMaxRange(label)))
    }

    /// The bracketed label of a link or image: from after the opening bracket to the end of its last child.
    private func labelRange(of markup: Markup, opening: Int, in range: NSRange) -> NSRange {
        let start = range.location + opening
        var end = start
        if markup.childCount > 0, let last = markup.child(at: markup.childCount - 1), let lastRange = self.range(last) {
            end = max(start, min(NSMaxRange(lastRange), NSMaxRange(range)))
        }
        return NSRange(location: start, length: end - start)
    }

    // MARK: Finishing

    func finish() {
        prepareTables()
        hideMarkers()
        for kern in paddingKerns {
            storage.addAttribute(.kern, value: kern.amount, range: NSRange(location: kern.location, length: 1))
        }
        layoutTables()
        separateAdjacentBlocks()
    }

    /// Blocks are separated by the theme's gap, like CSS margins. A blank line provides it;
    /// when a block starts right after a non-blank line (a heading under a heading), it gets
    /// the gap as space before it. Block starts are reliable in the parser's positions, and
    /// the line before is read from the text, so this doesn't depend on where blocks end.
    private func separateAdjacentBlocks() {
        for block in blockRanges where block.length > 0 && block.location < regionLength {
            let preceded: Bool
            if block.location == 0 {
                preceded = precededByLine
            } else {
                let previous = text.lineRange(for: NSRange(location: block.location - 1, length: 0))
                preceded = !text.substring(with: previous).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let firstLine = text.lineRange(for: NSRange(location: block.location, length: 0))
            guard preceded,
                  let style = storage.attribute(.paragraphStyle, at: firstLine.location, effectiveRange: nil) as? NSParagraphStyle
            else { continue }
            let spaced = style.mutableCopy() as! NSMutableParagraphStyle
            spaced.paragraphSpacingBefore = max(spaced.paragraphSpacingBefore, theme.blockSpacing)
            storage.addAttribute(.paragraphStyle, value: spaced, range: firstLine)
        }
    }

    private func hideMarkers() {
        for range in markers {
            if onActiveLine(range.location) {
                storage.addAttribute(.foregroundColor, value: theme.marker, range: range)
            } else {
                storage.addAttributes([.font: MarkdownStyler.hiddenFont, .foregroundColor: NSColor.clear, .kern: 0], range: range)
                storage.removeAttribute(.backgroundColor, range: range)
            }
        }
    }

    /// Finds each row's cells, hides the pipes and padding between them, and bolds the header.
    private func prepareTables() {
        for index in tables.indices {
            for rowIndex in tables[index].rows.indices {
                let row = tables[index].rows[rowIndex]
                guard !onActiveLine(row.line.location) else { continue }
                let cells = cellRanges(in: row.line)
                tables[index].rows[rowIndex].cells = cells

                var cursor = row.line.location
                for cell in cells {
                    addMarker(NSRange(location: cursor, length: cell.location - cursor))
                    cursor = NSMaxRange(cell)
                }
                addMarker(NSRange(location: cursor, length: NSMaxRange(row.line) - cursor))

                if row.isHeader {
                    for cell in cells where cell.length > 0 {
                        transformFont(cell) { NSFontManager.shared.convert($0, toHaveTrait: .boldFontMask) }
                        if let color = theme.strongColor {
                            storage.addAttribute(.foregroundColor, value: color, range: cell)
                        }
                    }
                }
            }
        }
    }

    /// Lines the cells up in columns by adding space before each one, and marks the
    /// rows so the layout manager draws the grid.
    private func layoutTables() {
        let padding: CGFloat = 10
        for table in tables {
            let rows = table.rows.filter { $0.cells != nil }
            guard !rows.isEmpty else { continue }
            let columns = rows.map { $0.cells!.count }.max() ?? 0
            guard columns > 0 else { continue }

            let widths: [[CGFloat]] = rows.map { row in
                row.cells!.map { $0.length > 0 ? storage.attributedSubstring(from: $0).size().width.rounded(.up) : 0 }
            }
            var columnWidths = [CGFloat](repeating: 0, count: columns)
            for row in widths {
                for (column, width) in row.enumerated() {
                    columnWidths[column] = max(columnWidths[column], width + 2 * padding)
                }
            }
            // Tables fill the column, like `width: 100%`, sharing the extra space by content width.
            let available = availableWidth - table.indent
            let natural = columnWidths.reduce(0, +)
            if natural > 0, natural < available {
                columnWidths = columnWidths.map { $0 + (available - natural) * $0 / natural }
            }
            // A wider table keeps its natural width; the text view lets it scroll sideways.
            let whole = NSUnionRange(text.lineRange(for: table.rows[0].line), text.lineRange(for: table.rows[table.rows.count - 1].line))
            storage.addAttribute(.tableBlock, value: TableBlock(overflows: natural > available + 0.5), range: whole)
            var edges: [CGFloat] = [table.indent]
            for width in columnWidths { edges.append(edges.last! + width) }

            let rowHeight = theme.lineHeight + 10
            for (rowIndex, row) in rows.enumerated() {
                let style = NSMutableParagraphStyle()
                style.minimumLineHeight = rowHeight
                style.maximumLineHeight = rowHeight
                style.lineBreakMode = .byClipping
                storage.addAttribute(.paragraphStyle, value: style, range: text.lineRange(for: row.line))
                // Center the text vertically in the taller row.
                storage.addAttribute(.baselineOffset, value: MarkdownStyler.baselineOffset(for: theme.bodyFont, lineHeight: rowHeight),
                                     range: row.line)

                var cursor: CGFloat = 0
                for (column, cell) in row.cells!.enumerated() {
                    let width = widths[rowIndex][column]
                    let inner = columnWidths[column] - 2 * padding
                    let alignment = column < table.alignments.count ? table.alignments[column] : nil
                    let offset: CGFloat
                    switch alignment {
                    case .center: offset = max(0, (inner - width) / 2)
                    case .right: offset = max(0, inner - width)
                    default: offset = 0
                    }
                    let target = edges[column] + padding + offset
                    if cell.location > row.line.location {
                        storage.addAttribute(.kern, value: target - cursor, range: NSRange(location: cell.location - 1, length: 1))
                    }
                    cursor = target + width
                }
                storage.addAttribute(.tableRow, value: TableRowInfo(edges: edges, isHeader: row.isHeader,
                                                                     isLast: rowIndex == rows.count - 1), range: row.line)
            }
        }
    }

    /// The content ranges of a table row's cells, split on unescaped pipes outside code spans.
    private func cellRanges(in line: NSRange) -> [NSRange] {
        var separators: [Int] = []
        var index = line.location
        var inCode = false
        while index < NSMaxRange(line) {
            let character = text.character(at: index)
            if character == 92 { index += 2; continue } // backslash escape
            if character == 96 { inCode.toggle() }
            if character == 124, !inCode { separators.append(index) }
            index += 1
        }

        let trimmed = text.substring(with: line).trimmingCharacters(in: .whitespaces)
        var bounds = [line.location - 1] + separators + [NSMaxRange(line)]
        if trimmed.hasPrefix("|"), bounds.count > 2 { bounds.removeFirst() }
        if trimmed.hasSuffix("|"), trimmed.count > 1, bounds.count > 2 { bounds.removeLast() }

        var cells: [NSRange] = []
        for (left, right) in zip(bounds, bounds.dropFirst()) {
            var start = left + 1
            var end = right
            while start < end, [32, 9].contains(text.character(at: start)) { start += 1 }
            while end > start, [32, 9].contains(text.character(at: end - 1)) { end -= 1 }
            cells.append(NSRange(location: start, length: end - start))
        }
        return cells
    }
}
