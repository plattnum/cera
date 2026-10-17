import AppKit
import Markdown
import SwiftUI

/// A heading in the outline sidebar.
struct OutlineItem: Equatable, Identifiable {
    /// The heading's position in the outline.
    let id: Int
    let level: Int
    let title: String
    /// Where the heading's first line starts in the text, as a UTF-16 offset.
    let location: Int
}

enum Outline {
    /// The document's headings in order: those at the top level of the document, as the
    /// styler sees them, so a `#` line inside a code block or list is not a heading here.
    /// Headings with no text are left out.
    static func items(in text: String) -> [OutlineItem] {
        let source = NSString(string: text)
        let map = SourceMap(source)
        var items: [OutlineItem] = []
        for case let heading as Heading in Document(parsing: text).children {
            guard let range = map.range(heading.range) else { continue }
            let title = plainText(of: heading).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !title.isEmpty else { continue }
            let line = source.lineRange(for: NSRange(location: min(range.location, source.length), length: 0))
            items.append(OutlineItem(id: items.count, level: heading.level, title: title, location: line.location))
        }
        return items
    }

    /// The text a heading shows, without Markdown syntax: emphasis, code spans, and links
    /// keep only their text, and line breaks become spaces.
    private static func plainText(of markup: Markup) -> String {
        switch markup {
        case let text as Markdown.Text: text.string
        case let code as InlineCode: code.code
        case is SoftBreak, is LineBreak: " "
        case let html as InlineHTML: html.rawHTML
        default: markup.children.map(plainText(of:)).joined()
        }
    }

    /// The index of the last item that starts at or before `location`, or nil when the
    /// first item comes after it.
    static func index(in items: [OutlineItem], before location: Int) -> Int? {
        var low = 0, high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].location <= location { low = middle + 1 } else { high = middle }
        }
        return low > 0 ? low - 1 : nil
    }
}

/// Keeps the outline in step with a document: its headings, which one holds the text in
/// view, and jumping to one.
@MainActor
final class OutlineModel: ObservableObject {
    @Published private(set) var items: [OutlineItem] = []
    /// The heading whose section is at the top of the editor, or nil above the first one.
    @Published private(set) var current: Int?

    /// The editor the outline belongs to; set by the editor.
    weak var textView: MarkdownTextView?

    /// The text `items` were found in.
    private var parsedText: String?
    /// The length of that text in UTF-16 units, the editor's measure.
    private var parsedLength = 0
    /// Increments on every update, so a parse that finishes late is dropped.
    private var generation = 0
    /// The generation `items` belong to; behind `generation` while a parse is pending.
    private var parsedGeneration = 0
    private var scheduled: DispatchWorkItem?
    /// The heading last jumped to. It stays highlighted while it is on screen, even when
    /// it is too near the end of the document to scroll to the top.
    private var pinned: Int?

    /// Documents up to this length are parsed right away; longer ones in the background.
    private static let immediateLength = 200_000

    /// Updates the headings for `text`: right away when `immediately` (the outline was just
    /// shown), otherwise after typing pauses for a moment.
    func update(text: String, immediately: Bool = false) {
        // Showing the outline again over unchanged text needs no new parse.
        if immediately, generation == parsedGeneration, text == parsedText {
            visibleAreaChanged()
            return
        }
        generation += 1
        scheduled?.cancel()
        scheduled = nil
        let generation = generation
        if immediately, (text as NSString).length <= Self.immediateLength {
            apply(Outline.items(in: text), from: text, generation: generation)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                let items = Outline.items(in: text)
                DispatchQueue.main.async {
                    guard let self, self.generation == generation else { return }
                    self.apply(items, from: text, generation: generation)
                }
            }
        }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0 : 0.25), execute: work)
    }

    private func apply(_ items: [OutlineItem], from text: String, generation: Int) {
        parsedText = text
        parsedLength = (text as NSString).length
        parsedGeneration = generation
        if items != self.items {
            self.items = items
            pinned = nil // Its number may now belong to a different heading.
        }
        visibleAreaChanged()
    }

    /// Scrolls the editor to the heading at `index` and puts the cursor on it.
    func jump(to index: Int) {
        guard let textView else { return }
        // Headings found before the latest edit may have moved; find them again first.
        if generation != parsedGeneration || textView.textStorage?.length != parsedLength {
            generation += 1
            scheduled?.cancel()
            scheduled = nil
            let text = textView.string
            apply(Outline.items(in: text), from: text, generation: generation)
        }
        guard items.indices.contains(index) else { return }
        pinned = index
        textView.scrollLineToTop(at: items[index].location)
        visibleAreaChanged()
    }

    /// Finds the heading for the text now in view. Called as the editor scrolls or resizes.
    func visibleAreaChanged() {
        guard let textView, !items.isEmpty else {
            setCurrent(nil)
            return
        }
        if let pinned, items.indices.contains(pinned), textView.isLineVisible(at: items[pinned].location) {
            setCurrent(pinned)
            return
        }
        pinned = nil
        // A heading counts once it reaches the top fifth of the view, so the one just
        // scrolled to is current even with a little space above it.
        let location = textView.characterIndex(belowVisibleTop: min(80, textView.unobscuredHeight / 5))
        setCurrent(Outline.index(in: items, before: location))
    }

    private func setCurrent(_ index: Int?) {
        if index != current { current = index }
    }
}

extension MarkdownTextView {
    /// How much of the top of the text is under the window's title bar: the editor runs
    /// up beneath it so the document's color fills the window.
    var obscuredTop: CGFloat {
        guard let window, let scrollView = enclosingScrollView else { return 0 }
        let frame = scrollView.convert(scrollView.bounds, to: nil)
        return max(0, frame.maxY - window.contentLayoutRect.maxY)
    }

    /// The height of the editor's area not under the title bar.
    var unobscuredHeight: CGFloat {
        max(0, visibleRect.height - obscuredTop)
    }

    /// The character at `offset` points below the top edge of the text not under the title bar.
    func characterIndex(belowVisibleTop offset: CGFloat) -> Int {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return 0 }
        let y = visibleRect.minY + obscuredTop + offset - textContainerOrigin.y
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: max(0, y)), in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    /// Whether the line holding `location` is on screen, below the title bar.
    func isLineVisible(at location: Int) -> Bool {
        guard let layoutManager, let length = textStorage?.length, length > 0 else { return false }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(max(0, location), length - 1))
        let line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            .offsetBy(dx: 0, dy: textContainerOrigin.y)
        let top = visibleRect.minY + obscuredTop
        return line.maxY > top && line.minY < visibleRect.maxY
    }

    /// Scrolls so the line holding `location` sits at the top, just below the title bar,
    /// and puts the cursor at its start.
    func scrollLineToTop(at location: Int) {
        guard let length = textStorage?.length else { return }
        let location = min(max(0, location), length)
        setSelectedRange(NSRange(location: location, length: 0))
        window?.makeFirstResponder(self)
        guard length > 0 else { return }
        let target = min(location, length - 1)
        heldReadingPosition = nil // Going somewhere new; don't put back an older position.
        // Bring the line into view first, as Find does. A large document is laid out only
        // where it has been seen, so this places the line consistently with what is drawn,
        // without laying out everything above it.
        scrollRangeToVisible(NSRange(location: target, length: 0))
        restore(ReadingPosition(character: target, offset: 0))
    }
}

/// Where the reader is: the first character below the title bar, and how far its line
/// starts above that edge.
struct ReadingPosition {
    var character: Int
    var offset: CGFloat
}

extension MarkdownTextView {
    /// The reading position now, or nil at the very top of the document, where staying at
    /// the top is what keeps the reader's place.
    func readingPosition() -> ReadingPosition? {
        // The scroll view may leave room for the title bar above the text when scrolled to the top.
        let topmost = -(enclosingScrollView?.contentInsets.top ?? 0)
        guard let layoutManager, let textContainer, let length = textStorage?.length, length > 0,
              visibleRect.minY > topmost + 0.5 else { return nil }
        let top = visibleRect.minY + obscuredTop
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: max(0, top - textContainerOrigin.y)), in: textContainer)
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return ReadingPosition(character: layoutManager.characterIndexForGlyph(at: glyph),
                               offset: top - (line.minY + textContainerOrigin.y))
    }

    /// Scrolls back to `position`. Drawing lays out the text around the view, which can
    /// refine the estimated heights above it and nudge the line, so draw and check again,
    /// a few times at most.
    func restore(_ position: ReadingPosition) {
        guard let layoutManager, let length = textStorage?.length, length > 0 else { return }
        let character = min(max(0, position.character), length - 1)
        for _ in 0..<4 {
            window?.displayIfNeeded()
            let line = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: character), effectiveRange: nil)
            let y = max(0, line.minY + textContainerOrigin.y + position.offset - obscuredTop)
            if abs(visibleRect.minY - y) < 1 { break }
            scroll(NSPoint(x: visibleRect.minX, y: y))
        }
    }

    /// Keeps the text in view in place through a change that lays the text out again, such
    /// as a new width or a restyle: notes the reading position now and puts it back once
    /// the change is done, on the next turn of the run loop.
    func keepReadingPosition() {
        guard heldReadingPosition == nil, let position = readingPosition() else { return }
        heldReadingPosition = position
        DispatchQueue.main.async { [weak self] in
            guard let self, let position = self.heldReadingPosition else { return }
            self.heldReadingPosition = nil
            self.restore(position)
        }
    }
}

/// The outline sidebar: the document's headings, indented by level, with the current
/// section highlighted. Clicking a heading jumps to it.
struct OutlineSidebar: View {
    @ObservedObject var model: OutlineModel
    var theme: Theme

    static let width: CGFloat = 230

    var body: some View {
        Group {
            if model.items.isEmpty {
                Text("No headings")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: theme.marker))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 16)
            } else {
                list
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: theme.background).ignoresSafeArea())
        // The divider stops at the title bar, so it doesn't cut through the window title.
        .overlay(alignment: .trailing) {
            Color(nsColor: theme.rule).frame(width: 1)
        }
    }

    private var list: some View {
        // Indent relative to the largest heading used, so a document starting at ## isn't pushed right.
        let topLevel = model.items.map(\.level).min() ?? 1
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.items) { item in
                        row(item, indent: item.level - topLevel)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .onChange(of: model.current) {
                if let current = model.current { proxy.scrollTo(current) }
            }
        }
    }

    private func row(_ item: OutlineItem, indent: Int) -> some View {
        let isCurrent = item.id == model.current
        return Button {
            model.jump(to: item.id)
        } label: {
            Text(item.title)
                .font(.system(size: 13, weight: indent == 0 ? .semibold : .regular))
                .foregroundStyle(Color(nsColor: theme.text).opacity(indent >= 2 ? 0.75 : 1))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, CGFloat(min(indent, 5)) * 12)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isCurrent ? Color(nsColor: theme.selection) : .clear,
                            in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .id(item.id)
    }
}
