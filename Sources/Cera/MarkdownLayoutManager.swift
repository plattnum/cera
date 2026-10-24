import AppKit

extension NSAttributedString.Key {
    /// On the hidden marker of a list item: the bullet or number to draw in its place.
    static let listBullet = NSAttributedString.Key("CeraListBullet")
    /// Marks a code block, drawn as one panel behind its lines. The value is the
    /// panel's left edge (NSNumber), measured from the column's left edge.
    static let codeBlock = NSAttributedString.Key("CeraCodeBlock")
    /// On a fenced code block's first character: the language name (String) to show in the
    /// panel's top-right corner.
    static let codeLanguage = NSAttributedString.Key("CeraCodeLanguage")
    /// Marks a quote line. The value lists the x of each quote bar ([CGFloat]), one per nesting level.
    static let quoteBar = NSAttributedString.Key("CeraQuoteBar")
    /// Marks an image paragraph. The value is an `ImageBlock`.
    static let imageBlock = NSAttributedString.Key("CeraImageBlock")
    /// Marks a table row. The value is a `TableRowInfo`.
    static let tableRow = NSAttributedString.Key("CeraTableRow")
    /// Marks a whole table, header to last row. The value is a `TableBlock`.
    static let tableBlock = NSAttributedString.Key("CeraTableBlock")
    /// Marks a horizontal rule line, drawn as a line across the column.
    static let horizontalRule = NSAttributedString.Key("CeraHorizontalRule")
    /// Marks a heading drawn with a rule underneath: "full" across the column or a "short" centered stroke.
    static let headingUnderline = NSAttributedString.Key("CeraHeadingUnderline")
    /// Inline code text, drawn on a background box with the theme's padding.
    static let inlineCode = NSAttributedString.Key("CeraInlineCode")
    /// A line break inside a paragraph that is laid out as a space, so the paragraph flows.
    static let softBreak = NSAttributedString.Key("CeraSoftBreak")
    /// Text drawn in capitals without changing the characters, like CSS `text-transform: uppercase`.
    static let uppercase = NSAttributedString.Key("CeraUppercase")
}

/// An image drawn in place of its Markdown source.
final class ImageBlock: NSObject {
    let image: NSImage
    let size: NSSize
    /// Left edge, measured from the column's left edge.
    let x: CGFloat
    /// What the image shows, when it can be drawn again as a new image: a diagram's theme and
    /// source. Two blocks with the same key draw the same thing, whichever image they hold.
    let key: String?

    init(image: NSImage, size: NSSize, x: CGFloat, key: String? = nil) {
        self.image = image
        self.size = size
        self.x = x
        self.key = key
    }

    /// Equal when they draw the same thing, so restyling with an unchanged value is a no-op.
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ImageBlock, other.size == size, other.x == x else { return false }
        if let key, let otherKey = other.key { return key == otherKey }
        return other.image === image
    }

    override var hash: Int { ObjectIdentifier(ImageBlock.self).hashValue }
}

/// How to draw one table row's grid.
final class TableRowInfo: NSObject {
    /// Column boundaries, measured from the column's left edge (columns + 1 values).
    let edges: [CGFloat]
    let isHeader: Bool
    let isLast: Bool

    init(edges: [CGFloat], isHeader: Bool, isLast: Bool) {
        self.edges = edges
        self.isHeader = isHeader
        self.isLast = isLast
    }

    /// Equal when they draw the same thing, so restyling with an unchanged value is a no-op.
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TableRowInfo else { return false }
        return other.edges == edges && other.isHeader == isHeader && other.isLast == isLast
    }

    override var hash: Int { ObjectIdentifier(TableRowInfo.self).hashValue }
}

/// A table as a whole. Its characters are the attribute's effective range: tables are always
/// separated by a line that isn't part of one, so two never run together.
final class TableBlock: NSObject {
    /// Whether the table is wider than the text column, so its right side is cut off.
    let overflows: Bool

    init(overflows: Bool) {
        self.overflows = overflows
    }

    /// Equal when they draw the same thing, so restyling with an unchanged value is a no-op.
    override func isEqual(_ object: Any?) -> Bool {
        (object as? TableBlock)?.overflows == overflows
    }

    override var hash: Int { ObjectIdentifier(TableBlock.self).hashValue }
}

/// Draws what text attributes can't: list bullets and numbers in place of hidden
/// markers, code block panels, quote bars, horizontal rules, heading rules, and
/// uppercase headings.
final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    var theme: Theme = .midnight
    /// The first character of the code block showing the copy button, whose corner the button
    /// takes over from the language label.
    var codeBlockWithCopyButton: Int?
    /// Called when a pass of layout finishes.
    var onLayoutComplete: (() -> Void)?

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        onLayoutComplete?()
    }

    /// Lays out soft line breaks (see `.softBreak`) as a space, so a hard-wrapped paragraph
    /// flows as one. For a two-character \r\n break, the second character takes no space.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = textStorage, charIndex < storage.length,
              storage.attribute(.softBreak, at: charIndex, effectiveRange: nil) != nil
        else { return action }
        let previousIsBreak = charIndex > 0 && storage.attribute(.softBreak, at: charIndex - 1, effectiveRange: nil) != nil
        return previousIsBreak ? .zeroAdvancement : .whitespace
    }

    /// Adjusts glyphs without changing the characters:
    /// - a soft line break (see `.softBreak`) gets a space glyph, so the words on either
    ///   side stay apart when the paragraph flows (a line break glyph has no width), and
    /// - text marked `.uppercase` gets capital-letter glyphs.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = textStorage else { return 0 }
        // Read characters from the storage itself; `storage.string` would copy the whole document.
        let text = storage.mutableString
        let count = glyphRange.length
        var replaced: [CGGlyph]?
        var newProperties: [NSLayoutManager.GlyphProperty]?
        func prepare() {
            if replaced == nil {
                replaced = Array(UnsafeBufferPointer(start: glyphs, count: count))
                newProperties = Array(UnsafeBufferPointer(start: properties, count: count))
            }
        }

        for i in 0..<count {
            let index = characterIndexes[i]
            guard index < storage.length else { continue }
            if storage.attribute(.softBreak, at: index, effectiveRange: nil) != nil {
                prepare()
                let secondOfPair = index > 0 && storage.attribute(.softBreak, at: index - 1, effectiveRange: nil) != nil
                if secondOfPair {
                    newProperties![i] = .null // the \n of \r\n: no glyph
                } else {
                    var space: UniChar = 32
                    var glyph: CGGlyph = 0
                    if CTFontGetGlyphsForCharacters(font as CTFont, &space, &glyph, 1) {
                        replaced![i] = glyph
                        // An ordinary, stretchable space: no longer a control character, so it
                        // takes a space's width and doesn't end the line.
                        newProperties![i].remove(.controlCharacter)
                        newProperties![i].insert(.elastic)
                    }
                }
            } else if storage.attribute(.uppercase, at: index, effectiveRange: nil) != nil {
                guard let scalar = Unicode.Scalar(text.character(at: index)) else { continue }
                let upper = Array(String(Character(scalar)).uppercased().utf16)
                guard upper.count == 1 else { continue }
                var unit = upper[0]
                var glyph: CGGlyph = 0
                if CTFontGetGlyphsForCharacters(font as CTFont, &unit, &glyph, 1) {
                    prepare()
                    replaced![i] = glyph
                }
            }
        }
        guard let replaced, let newProperties else { return 0 }
        setGlyphs(replaced, properties: newProperties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return count
    }

    /// The panel drawn behind the code block holding `characterIndex`, in text container
    /// coordinates, and the block's characters (whole lines, fences included).
    func codePanel(at characterIndex: Int) -> (rect: NSRect, block: NSRange)? {
        guard let storage = textStorage, let container = textContainers.first,
              characterIndex >= 0, characterIndex < storage.length
        else { return nil }
        var block = NSRange()
        guard let panelX = (storage.attribute(.codeBlock, at: characterIndex, longestEffectiveRange: &block,
                                              in: NSRange(location: 0, length: storage.length)) as? NSNumber)
                .map({ CGFloat($0.doubleValue) })
        else { return nil }
        var panel = unionOfLines(for: block)
        guard !panel.isNull else { return nil }
        panel.origin.x = container.lineFragmentPadding + panelX
        panel.size.width = container.size.width - 2 * container.lineFragmentPadding - panelX
        return (panel, block)
    }

    /// The rectangle (text container coordinates) of the language label of the code block whose
    /// panel is `panel`, sized for `label`. It shares the copy button's corner: right-aligned with
    /// it and centered on it.
    static func languageLabelRect(for label: String, in panel: NSRect) -> NSRect {
        let size = (label as NSString).size(withAttributes: [.font: languageLabelFont])
        let width = ceil(size.width) + 12, height: CGFloat = 18
        let buttonCenterY = panel.minY + 6 + CodeCopyButton.size.height / 2
        return NSRect(x: panel.maxX - 6 - width, y: buttonCenterY - height / 2, width: width, height: height)
    }

    static let languageLabelFont = NSFont.systemFont(ofSize: 11)

    /// Draws each code block's language label on top of its text, so it stays readable over a
    /// long first line, as the copy button does.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var drawn = Set<Int>()
        storage.enumerateAttribute(.codeBlock, in: characters) { value, range, _ in
            guard value != nil, let panel = codePanel(at: range.location), drawn.insert(panel.block.location).inserted,
                  panel.block.location != codeBlockWithCopyButton,
                  let label = storage.attribute(.codeLanguage, at: panel.block.location, effectiveRange: nil) as? String
            else { return }
            let chip = Self.languageLabelRect(for: label, in: panel.rect).offsetBy(dx: origin.x, dy: origin.y)
            (theme.codePanel.alphaComponent > 0 ? theme.codePanel : theme.background).setFill()
            NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
            let attributes: [NSAttributedString.Key: Any] = [.font: Self.languageLabelFont, .foregroundColor: theme.marker]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(at: NSPoint(x: chip.midX - size.width / 2, y: chip.midY - size.height / 2), withAttributes: attributes)
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }

        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let columnX = origin.x + container.lineFragmentPadding
        let columnWidth = container.size.width - 2 * container.lineFragmentPadding

        // Code panels span the whole block, not just the visible part, so their shape is stable while scrolling.
        storage.enumerateAttribute(.codeBlock, in: characters) { value, range, _ in
            guard value != nil, let panel = codePanel(at: range.location)?.rect else { return }
            let shape = NSBezierPath(roundedRect: panel.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: 0.5, dy: 0.5),
                                     xRadius: theme.codeRadius, yRadius: theme.codeRadius)
            theme.codePanel.setFill()
            shape.fill()
            if let border = theme.codeBorder {
                border.setStroke()
                shape.lineWidth = 1
                shape.stroke()
            }
        }

        if theme.inlineCode.alphaComponent > 0, let container = textContainers.first {
            let codeFont = theme.codeFont
            let boxHeight = codeFont.ascender - codeFont.descender + 4
            storage.enumerateAttribute(.inlineCode, in: characters) { value, range, _ in
                guard value != nil else { return }
                let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                        in: container) { rect, _ in
                    let line = self.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                    let height = min(boxHeight, line.height)
                    let box = NSRect(x: origin.x + rect.minX - self.theme.inlineCodePadding,
                                     y: origin.y + rect.midY - height / 2,
                                     width: rect.width + 2 * self.theme.inlineCodePadding, height: height)
                    self.theme.inlineCode.setFill()
                    NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
                }
            }
        }

        storage.enumerateAttribute(.quoteBar, in: characters) { value, range, _ in
            guard let bars = value as? [CGFloat] else { return }
            let lines = unionOfLines(for: range)
            guard !lines.isNull else { return }
            theme.quoteBar.setFill()
            for x in bars {
                NSRect(x: columnX + x, y: origin.y + lines.minY, width: theme.quoteBarWidth, height: lines.height).fill()
            }
        }

        storage.enumerateAttribute(.imageBlock, in: characters) { value, range, _ in
            guard let block = value as? ImageBlock else { return }
            let line = lineRect(forGlyphAt: glyphIndexForCharacter(at: range.location))
            let frame = NSRect(x: columnX + block.x, y: origin.y + line.minY, width: block.size.width, height: block.size.height)
            block.image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        storage.enumerateAttribute(.tableRow, in: characters) { value, range, _ in
            guard let row = value as? TableRowInfo, let left = row.edges.first, let right = row.edges.last else { return }
            let line = lineRect(forGlyphAt: glyphIndexForCharacter(at: range.location))
            let top = origin.y + line.minY
            theme.rule.setFill()
            // Top border of every row, bottom border of the last, and the column lines.
            NSRect(x: columnX + left, y: top, width: right - left, height: 1).fill()
            if row.isLast {
                NSRect(x: columnX + left, y: top + line.height - 1, width: right - left, height: 1).fill()
            }
            for edge in row.edges {
                NSRect(x: columnX + min(edge, right - 1), y: top, width: 1, height: line.height).fill()
            }
        }

        storage.enumerateAttribute(.horizontalRule, in: characters) { value, range, _ in
            guard value != nil else { return }
            let line = unionOfLines(for: range)
            guard !line.isNull else { return }
            theme.rule.setFill()
            NSRect(x: columnX, y: origin.y + line.midY - 1, width: columnWidth, height: 2).fill()
        }

        storage.enumerateAttribute(.headingUnderline, in: characters) { value, range, _ in
            guard let kind = value as? String else { return }
            let line = unionOfLines(for: range)
            guard !line.isNull else { return }
            if kind == "short" {
                theme.text.setFill()
                NSRect(x: columnX + columnWidth / 2 - 50, y: origin.y + line.maxY + 8, width: 100, height: 1).fill()
            } else {
                theme.rule.setFill()
                NSRect(x: columnX, y: origin.y + line.maxY + 4, width: columnWidth, height: 1).fill()
            }
        }

        storage.enumerateAttribute(.listBullet, in: characters) { value, range, _ in
            guard let symbol = value as? String else { return }
            let position = markerPosition(at: range.location)
            let textStart = origin.x + position.textStart
            let centerY = origin.y + position.centerY

            if symbol == "☐" || symbol == "☑" {
                drawCheckbox(checked: symbol == "☑", in: checkboxRect(at: range.location).offsetBy(dx: origin.x, dy: origin.y))
                return
            }
            if symbol == "◦" {
                let diameter: CGFloat = 5.5
                theme.text.setStroke()
                let circle = NSBezierPath(ovalIn: NSRect(x: textStart - 13 - diameter / 2, y: centerY - diameter / 2,
                                                         width: diameter, height: diameter))
                circle.lineWidth = 1
                circle.stroke()
                return
            }
            if symbol == "▪" {
                let side: CGFloat = 5.5
                theme.text.setFill()
                NSRect(x: textStart - 13 - side / 2, y: centerY - side / 2, width: side, height: side).fill()
                return
            }
            if symbol == "•" {
                // A filled disc, like a rendered list bullet.
                let diameter: CGFloat = 5.5
                theme.text.setFill()
                NSBezierPath(ovalIn: NSRect(x: textStart - 13 - diameter / 2, y: centerY - diameter / 2,
                                            width: diameter, height: diameter)).fill()
                return
            }
            let font = theme.bodyFont
            let marker = NSAttributedString(string: symbol, attributes: [.font: font, .foregroundColor: theme.text])
            // Right-align the marker a little before the text, like a rendered list.
            let size = marker.size()
            marker.draw(at: NSPoint(x: textStart - size.width - 8, y: centerY - size.height / 2))
        }
    }

    /// Where the list item whose marker starts at `location` draws its marker, in container coordinates:
    /// the x where the item's text starts, and the middle of its first line of text.
    func markerPosition(at location: Int) -> (textStart: CGFloat, centerY: CGFloat) {
        guard let storage = textStorage, location < storage.length else { return (0, 0) }
        let glyph = glyphIndexForCharacter(at: location)
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let paragraph = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        let textStart = line.minX + (paragraph?.firstLineHeadIndent ?? theme.listIndent)
        // Center on the text line, not the fragment, which also holds the spacing after the item.
        let lineHeight = paragraph?.minimumLineHeight ?? theme.lineHeight
        return (textStart, lineRect(forGlyphAt: glyph).minY + lineHeight / 2)
    }

    /// The line fragment holding a glyph, without the spacing before its paragraph, in container coordinates.
    /// A block that directly follows another, with no blank line between them, gets the block gap as
    /// spacing before it (`MarkdownStyler.separateAdjacentBlocks`), and that space is part of the fragment.
    /// Anything drawn for the block (its marker, image, table grid, code panel or quote bar) starts below it.
    func lineRect(forGlyphAt glyph: Int) -> NSRect {
        Self.withoutSpacingBefore(lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil),
                                  used: lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil))
    }

    /// A fragment cut down to start where its used rectangle does, which is where the text starts,
    /// after any spacing before the paragraph (none at the document's start).
    private static func withoutSpacingBefore(_ fragment: NSRect, used: NSRect) -> NSRect {
        let top = min(max(used.minY, fragment.minY), fragment.maxY)
        return NSRect(x: fragment.minX, y: top, width: fragment.width, height: fragment.maxY - top)
    }

    /// The checkbox drawn for the task item whose marker starts at `location`, in container coordinates.
    func checkboxRect(at location: Int) -> NSRect {
        let side: CGFloat = 13
        let position = markerPosition(at: location)
        return NSRect(x: position.textStart - 10 - side, y: position.centerY - side / 2, width: side, height: side)
    }

    private func drawCheckbox(checked: Bool, in box: NSRect) {
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        theme.marker.setStroke()
        path.lineWidth = 1
        path.stroke()
        guard checked else { return }
        let tick = NSBezierPath()
        tick.move(to: NSPoint(x: box.minX + 3, y: box.midY))
        tick.line(to: NSPoint(x: box.minX + 5.5, y: box.maxY - 3.5))
        tick.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 3.5))
        tick.lineWidth = 1.6
        theme.text.setStroke()
        tick.stroke()
    }

    /// The union of the line fragment rectangles covering a character range, in container coordinates,
    /// without the spacing before the first line (see `lineRect(forGlyphAt:)`).
    func unionOfLines(for characters: NSRange) -> NSRect {
        let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        var union = NSRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { rect, used, _, _, _ in
            union = union.union(Self.withoutSpacingBefore(rect, used: used))
        }
        return union
    }
}
