import AppKit

/// A horizontal scroll bar for a table too wide for the text column (see `TableBlock`), like
/// CSS `overflow-x: auto`. It lies over the table, whose right side the text view cuts off, and
/// shows a copy of the table laid out at its full width.
final class TableScroller: NSScrollView {
    let snapshot = TableSnapshotView()
    /// The table's first character in the document.
    var location = 0
    /// Whether the current scroll gesture scrolls the page instead of the table, decided once
    /// per gesture so a swipe doesn't switch between the two halfway through.
    private var scrollsPage = false

    init() {
        super.init(frame: .zero)
        hasHorizontalScroller = true
        hasVerticalScroller = false
        drawsBackground = false
        horizontalScrollElasticity = .none
        verticalScrollElasticity = .none
        documentView = snapshot
        // The text view holds the real text; VoiceOver reads it there.
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The height of the scroll bar, which sits in the space under the table.
    var scrollerHeight: CGFloat {
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollerStyle)
    }

    /// How far the table is scrolled.
    var offset: CGFloat {
        get { contentView.bounds.origin.x }
        set {
            let limit = max(0, snapshot.frame.width - contentView.bounds.width)
            contentView.scroll(to: NSPoint(x: min(max(0, newValue), limit), y: 0))
            reflectScrolledClipView(contentView)
        }
    }

    /// A mostly vertical gesture scrolls the page, so the table never traps the reader;
    /// a mostly horizontal one (or Shift with a mouse wheel) scrolls the table.
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
            scrollsPage = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
        }
        if scrollsPage, event.phase != .mayBegin, let page = superview?.enclosingScrollView {
            page.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// Draws a copy of one table with a text system of its own, as wide as the table needs, using
/// the editor's layout manager so it looks exactly like the rest of the document.
final class TableSnapshotView: NSView {
    let layoutManager = MarkdownLayoutManager()
    private let storage = NSTextStorage()
    private let container = NSTextContainer(size: .zero)
    /// Where the copy's text container starts, in this view.
    private(set) var textOrigin = NSPoint.zero
    /// Called with the index (in the table's text) of the character clicked, and the click.
    var onClick: ((Int, NSEvent) -> Void)?
    /// Called on a right-click with the index of the character under it; returns the menu to show.
    var onMenu: ((Int, NSEvent) -> NSMenu?)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        layoutManager.usesFontLeading = false
        storage.addLayoutManager(layoutManager)
        container.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(container)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }

    /// The table's text, as styled in the document.
    var text: NSAttributedString { storage }

    /// Shows `table`, laid out in a container `width` wide with the editor's `padding`, and
    /// returns its first line fragment, in the copy's container coordinates. Only lays the
    /// text out again when it changed.
    func show(_ table: NSAttributedString, theme: Theme, padding: CGFloat, width: CGFloat) -> NSRect {
        if layoutManager.theme.name != theme.name {
            layoutManager.theme = theme
            needsDisplay = true
        }
        if container.lineFragmentPadding != padding || container.size.width != width {
            container.lineFragmentPadding = padding
            container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            needsDisplay = true
        }
        if !storage.isEqual(to: table) {
            storage.setAttributedString(table)
            needsDisplay = true
        }
        guard storage.length > 0 else { return .zero }
        layoutManager.ensureLayout(for: container)
        return layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
    }

    /// Places the copy's text container in this view.
    func setTextOrigin(_ origin: NSPoint) {
        guard origin != textOrigin else { return }
        textOrigin = origin
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Opaque, so the cut-off table in the text view underneath doesn't show through.
        layoutManager.theme.background.setFill()
        dirtyRect.fill()
        let glyphs = layoutManager.glyphRange(for: container)
        layoutManager.drawBackground(forGlyphRange: glyphs, at: textOrigin)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: textOrigin)
    }

    /// The index (in the table's text) of the character where a click at `point` (view
    /// coordinates) puts the insertion point.
    func characterIndex(at point: NSPoint) -> Int? {
        guard storage.length > 0 else { return nil }
        let inContainer = NSPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: inContainer, in: container, fractionOfDistanceThroughGlyph: &fraction)
        var index = layoutManager.characterIndexForGlyph(at: glyph)
        // Past the middle of a character, the insertion point goes after it, as in the text view;
        // never past the end of the row's text onto the next line.
        let line = (storage.string as NSString).lineRange(for: NSRange(location: index, length: 0))
        let lineEnd = NSMaxRange(line) - ((storage.string as NSString).substring(with: line).hasSuffix("\n") ? 1 : 0)
        if fraction > 0.5 { index += 1 }
        return min(index, lineEnd)
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = characterIndex(at: convert(event.locationInWindow, from: nil)) else { return }
        onClick?(index, event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let index = characterIndex(at: convert(event.locationInWindow, from: nil)) else { return nil }
        return onMenu?(index, event)
    }

    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: .iBeam)
    }
}

extension MarkdownTextView {
    /// Updates the table scrollers on the next turn of the run loop, once, however many
    /// times it is asked for before then.
    func setNeedsUpdateTableScrollers() {
        guard !tableScrollersNeedUpdate else { return }
        tableScrollersNeedUpdate = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.tableScrollersNeedUpdate else { return }
            self.updateTableScrollers()
        }
    }

    /// Puts a scroller over each table near the visible area that is too wide for the column,
    /// and removes the others. A table holding the insertion point or selection has none: it
    /// shows as text, so its rows can be edited, selected, and found in the usual way.
    func updateTableScrollers() {
        tableScrollersNeedUpdate = false
        guard let layoutManager, let container = textContainer, let storage = textStorage else { return }
        var shown = Set<Int>()
        let nearby = visibleRect.insetBy(dx: 0, dy: -visibleRect.height)
        if storage.length > 0, !nearby.isEmpty {
            let area = nearby.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
            let glyphs = layoutManager.glyphRange(forBoundingRect: area, in: container)
            let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let everything = NSRange(location: 0, length: storage.length)
            storage.enumerateAttribute(.tableBlock, in: characters) { value, range, _ in
                guard (value as? TableBlock)?.overflows == true else { return }
                var table = NSRange()
                storage.attribute(.tableBlock, at: range.location, longestEffectiveRange: &table, in: everything)
                guard !shown.contains(table.location), !selectionTouches(table), showTableScroller(over: table) else { return }
                shown.insert(table.location)
            }
        }
        for (location, scroller) in tableScrollers where !shown.contains(location) {
            tableOffsets[location] = scroller.offset
            scroller.removeFromSuperview()
            tableScrollers[location] = nil
        }
    }

    private func selectionTouches(_ table: NSRange) -> Bool {
        selectedRanges.contains { value in
            let selection = value.rangeValue
            return selection.length == 0
                ? NSLocationInRange(selection.location, table)
                : NSIntersectionRange(selection, table).length > 0
        }
    }

    /// Places (or creates) the scroller over `table`. Returns false when the table can't have one.
    private func showTableScroller(over table: NSRange) -> Bool {
        guard let layoutManager, let container = textContainer, let storage = textStorage else { return false }
        var edges: [CGFloat]?
        storage.enumerateAttribute(.tableRow, in: table) { value, _, stop in
            if let row = value as? TableRowInfo, row.edges.count > 1 {
                edges = row.edges
                stop.pointee = true
            }
        }
        guard let edges, let first = edges.first, let last = edges.last else { return false }

        var lines = NSRect.null
        let glyphs = layoutManager.glyphRange(forCharacterRange: table, actualCharacterRange: nil)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            lines = lines.union(rect)
        }
        guard !lines.isNull else { return false }
        let firstLine = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)

        let isNew = tableScrollers[table.location] == nil
        let scroller = tableScrollers[table.location] ?? {
            let scroller = TableScroller()
            scroller.snapshot.onClick = { [weak self, weak scroller] index, event in
                guard let self, let scroller else { return }
                self.clickTable(at: scroller.location + index, with: event)
            }
            scroller.snapshot.onMenu = { [weak self, weak scroller] index, event in
                guard let self, let scroller else { return nil }
                self.placeCaretInTable(at: scroller.location + index)
                return self.menu(for: event)
            }
            addSubview(scroller)
            tableScrollers[table.location] = scroller
            return scroller
        }()
        scroller.location = table.location
        scroller.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)

        // From the table's left edge to the container's, which covers the line padding the
        // cut-off text can show in, and out to whole points, which covers the grid lines'
        // antialiasing when a theme's line height is fractional.
        let padding = container.lineFragmentPadding
        let left = padding + first
        let top = (textContainerOrigin.y + lines.minY).rounded(.down)
        let bottom = (textContainerOrigin.y + lines.maxY).rounded(.up)
        let frame = NSRect(x: textContainerOrigin.x + left, y: top,
                           width: container.size.width - left, height: bottom - top + scroller.scrollerHeight)
        if scroller.frame != frame { scroller.frame = frame }

        let snapshotFirstLine = scroller.snapshot.show(storage.attributedSubstring(from: table), theme: theme,
                                                       padding: padding, width: last + 2 * padding + 1)
        // Line up the copy's rows with the document's by the bottom of the first row, which
        // doesn't depend on how the space before the table is counted.
        let dy = (textContainerOrigin.y + firstLine.maxY - top) - snapshotFirstLine.maxY
        scroller.snapshot.setTextOrigin(NSPoint(x: -left, y: dy))
        let size = NSSize(width: last + padding + 1 - first, height: bottom - top)
        if scroller.snapshot.frame.size != size { scroller.snapshot.setFrameSize(size) }
        if isNew, let offset = tableOffsets.removeValue(forKey: table.location) { scroller.offset = offset }
        return true
    }

    /// A click on a scrolled table: ⌘-click opens a link, a plain click puts the insertion
    /// point at `index`, which shows that row as text for editing.
    func clickTable(at index: Int, with event: NSEvent) {
        if event.modifierFlags.contains(.command), let storage = textStorage, index < storage.length,
           let url = storage.attribute(.linkTarget, at: index, effectiveRange: nil) as? URL {
            followLink(url)
            return
        }
        placeCaretInTable(at: index)
    }

    private func placeCaretInTable(at index: Int) {
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: min(index, textStorage?.length ?? 0), length: 0))
    }
}
