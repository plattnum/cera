import AppKit
import XCTest
@testable import Cera

/// Callouts: a quote that starts with `[!NOTE]` (or another type) drawn as a colored box with an icon and label.
final class CalloutTests: XCTestCase {

    // MARK: Parsing the marker

    func testParsesGitHubTypesInAnyCase() throws {
        for line in ["[!NOTE]", "[!note]", "[!nOtE]"] {
            let marker = try XCTUnwrap(CalloutMarker.parse(line), line)
            XCTAssertEqual(marker.kind, .note, line)
            XCTAssertEqual(marker.label, "Note", line)
            XCTAssertFalse(marker.hasTitle, line)
            XCTAssertEqual(marker.markerLength, 7, line)
        }
    }

    func testParsesAliasesAndUnknownTypes() {
        XCTAssertEqual(CalloutMarker.parse("[!faq]")?.kind, .question)
        XCTAssertEqual(CalloutMarker.parse("[!faq]")?.label, "Faq")
        XCTAssertEqual(CalloutMarker.parse("[!tldr]")?.kind, .abstract)
        XCTAssertEqual(CalloutMarker.parse("[!RECIPE]")?.kind, .note)
        XCTAssertEqual(CalloutMarker.parse("[!RECIPE]")?.label, "Recipe")
        // GitHub's meaning, not another name for tip and warning.
        XCTAssertEqual(CalloutMarker.parse("[!IMPORTANT]")?.kind, .important)
        XCTAssertEqual(CalloutMarker.parse("[!CAUTION]")?.kind, .caution)
    }

    func testParsesTitleAndFoldSign() throws {
        let titled = try XCTUnwrap(CalloutMarker.parse("[!TIP] Save before you quit"))
        XCTAssertTrue(titled.hasTitle)
        XCTAssertEqual(titled.markerLength, 7)
        let folded = try XCTUnwrap(CalloutMarker.parse("[!FAQ]- Why?"))
        XCTAssertTrue(folded.hasTitle)
        XCTAssertEqual(folded.markerLength, 8)
        let open = try XCTUnwrap(CalloutMarker.parse("[!NOTE]+"))
        XCTAssertFalse(open.hasTitle)
        XCTAssertEqual(open.markerLength, 8)
    }

    func testRejectsNonMarkers() {
        for line in ["[! NOTE]", "[NOTE]", "\\[!NOTE]", "text [!NOTE]", "[!]", "[!NOTE]x"] {
            XCTAssertNil(CalloutMarker.parse(line), line)
        }
    }

    func testEveryKindHasAnIconAndBothColors() {
        for kind in CalloutKind.allCases {
            XCTAssertNotNil(kind.icon(color: .red, pointSize: 16), kind.rawValue)
        }
        XCTAssertEqual(CalloutColorFamily.blue.color(dark: true), NSColor(hex: 0x4C8DF6))
        XCTAssertEqual(CalloutColorFamily.blue.color(dark: false), NSColor(hex: 0x1F6FE0))
        XCTAssertEqual(CalloutColorFamily.red.color(dark: true), NSColor(hex: 0xEE5A55))
        XCTAssertEqual(CalloutColorFamily.red.color(dark: false), NSColor(hex: 0xCC2F35))
    }

    // MARK: Styling

    /// `source` styled with `theme`; the caret is at the end unless `caret` names the text it sits before.
    private func styled(_ source: String, theme: Theme = .midnight, caret: String? = nil,
                        joinsHardWrappedLines: Bool = false) -> NSTextStorage {
        let storage = NSTextStorage(string: source)
        var styler = MarkdownStyler(theme: theme)
        styler.joinsHardWrappedLines = joinsHardWrappedLines
        let location = caret.map { (source as NSString).range(of: $0).location } ?? (source as NSString).length
        styler.style(storage, caret: location)
        return storage
    }

    private func at(_ needle: String, in storage: NSTextStorage) -> Int {
        (storage.string as NSString).range(of: needle).location
    }

    private func blocks(at needle: String, in storage: NSTextStorage) -> [CalloutBlock]? {
        storage.attribute(.callout, at: at(needle, in: storage), effectiveRange: nil) as? [CalloutBlock]
    }

    private func paragraph(at needle: String, in storage: NSTextStorage) -> NSParagraphStyle? {
        storage.attribute(.paragraphStyle, at: at(needle, in: storage), effectiveRange: nil) as? NSParagraphStyle
    }

    private func isHidden(_ needle: String, in storage: NSTextStorage) -> Bool {
        (storage.attribute(.font, at: at(needle, in: storage), effectiveRange: nil) as? NSFont)?.pointSize == MarkdownStyler.hiddenFont.pointSize
    }

    func testCalloutLinesGetTheCalloutAttributeNotAQuoteBar() {
        let theme = Theme.midnight
        let storage = styled("> [!NOTE]\n> Body\n\nlast", theme: theme)
        let note = CalloutBlock(kind: .note, x: theme.quoteBarX, depth: 0, header: 0)
        XCTAssertEqual(blocks(at: "[!NOTE]", in: storage), [note])
        XCTAssertEqual(blocks(at: "Body", in: storage), [note])
        XCTAssertNil(storage.attribute(.quoteBar, at: at("Body", in: storage), effectiveRange: nil))
        XCTAssertEqual(storage.attribute(.calloutHeader, at: 0, effectiveRange: nil) as? CalloutHeader,
                       CalloutHeader(kind: .note, label: "Note"))
        XCTAssertTrue(isHidden("[!NOTE]", in: storage))
        XCTAssertTrue(isHidden("> Body", in: storage))
        XCTAssertNil(blocks(at: "last", in: storage))
    }

    func testBodyUsesTextColorAndIsNotItalic() {
        let theme = Theme.broadsheet
        XCTAssertTrue(theme.quoteItalic)
        let storage = styled("> [!NOTE]\n> Body\n>\n> > Plain\n\nlast", theme: theme)
        let body = at("Body", in: storage)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: body, effectiveRange: nil) as? NSColor, theme.text)
        let font = storage.attribute(.font, at: body, effectiveRange: nil) as? NSFont
        XCTAssertFalse(font!.fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertEqual(storage.attribute(.foregroundColor, at: at("Plain", in: storage), effectiveRange: nil) as? NSColor, theme.quoteText)
    }

    func testTitleIsShownBoldInTheTypeColor() {
        let theme = Theme.midnight
        let storage = styled("> [!TIP] Save first\n> Body\n\nlast", theme: theme)
        XCTAssertEqual(storage.attribute(.calloutHeader, at: 0, effectiveRange: nil) as? CalloutHeader,
                       CalloutHeader(kind: .tip, label: nil))
        let title = at("Save first", in: storage)
        let font = storage.attribute(.font, at: title, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font!.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(storage.attribute(.foregroundColor, at: title, effectiveRange: nil) as? NSColor,
                       CalloutColorFamily.green.color(dark: theme.isDark))
        XCTAssertEqual(storage.attribute(.kern, at: title - 1, effectiveRange: nil) as? CGFloat,
                       CalloutStyle.iconSize + CalloutStyle.iconGap)
    }

    func testCaretOnHeaderShowsRawMarkerButKeepsTheBox() {
        let theme = Theme.midnight
        let storage = styled("> [!NOTE]\n> Body\n\nlast", theme: theme, caret: "NOTE]")
        XCTAssertNil(storage.attribute(.calloutHeader, at: 0, effectiveRange: nil))
        XCTAssertFalse(isHidden("[!NOTE]", in: storage))
        XCTAssertEqual(storage.attribute(.foregroundColor, at: at("[!NOTE]", in: storage), effectiveRange: nil) as? NSColor, theme.marker)
        XCTAssertNotNil(blocks(at: "[!NOTE]", in: storage))
        XCTAssertNotNil(blocks(at: "Body", in: storage))
    }

    func testNotCallouts() {
        for source in ["> Text\n> [!NOTE]", "> [! NOTE]\n> x", "> [NOTE]\n> x", "> \\[!NOTE]\n> x"] {
            let storage = styled(source + "\n\nlast")
            XCTAssertNotNil(storage.attribute(.quoteBar, at: 0, effectiveRange: nil), source)
            XCTAssertNil(storage.attribute(.callout, at: (source as NSString).length - 1, effectiveRange: nil), source)
        }
        // A quote whose first line holds a nested quote isn't a callout; the inner quote is.
        let nested = styled("> > [!NOTE]\n> > x\n\nlast")
        let bars = nested.attribute(.quoteBar, at: at("x", in: nested), effectiveRange: nil) as? [CGFloat]
        XCTAssertEqual(bars?.count, 1)
        XCTAssertEqual(blocks(at: "x", in: nested)?.map(\.kind), [.note])
    }

    func testSecondMarkerInOneQuoteIsBody() {
        let storage = styled("> [!NOTE]\n> [!TIP]\n> x\n\nlast")
        XCTAssertEqual(blocks(at: "x", in: storage)?.map(\.kind), [.note])
        XCTAssertFalse(isHidden("[!TIP]", in: storage))
    }

    func testNestedCallouts() {
        let theme = Theme.midnight
        let storage = styled("> [!NOTE]\n> outer\n>\n> > [!TIP]\n> > inner\n\nlast", theme: theme)
        let inner = blocks(at: "inner", in: storage)
        XCTAssertEqual(inner, [CalloutBlock(kind: .note, x: theme.quoteBarX, depth: 0, header: 0),
                               CalloutBlock(kind: .tip, x: theme.quoteIndent + theme.quoteBarX, depth: 1,
                                            header: at("> > [!TIP]", in: storage))])
        XCTAssertEqual(paragraph(at: "inner", in: storage)?.tailIndent, -2 * CalloutStyle.rightPadding)
        XCTAssertEqual(paragraph(at: "outer", in: storage)?.tailIndent, -CalloutStyle.rightPadding)
    }

    func testCalloutInsideAListItem() {
        let theme = Theme.midnight
        let storage = styled("- item\n\n  > [!WARNING]\n  > body\n\nlast", theme: theme)
        XCTAssertEqual(blocks(at: "body", in: storage),
                       [CalloutBlock(kind: .warning, x: theme.listIndent + theme.quoteBarX, depth: 0,
                                     header: at("  > [!WARNING]", in: storage))])
        XCTAssertTrue(isHidden("[!WARNING]", in: storage))
    }

    func testPaddingIsAddedOnTopOfTheBlockGap() {
        let theme = Theme.midnight
        let callout = styled("Intro\n> [!NOTE]\n> body\n\nlast", theme: theme)
        let plain = styled("Intro\n> Quote\n> body\n\nlast", theme: theme)
        XCTAssertEqual(paragraph(at: "[!NOTE]", in: callout)?.paragraphSpacingBefore, theme.blockSpacing + CalloutStyle.topPadding)
        XCTAssertEqual(paragraph(at: "body", in: callout)!.paragraphSpacing,
                       paragraph(at: "body", in: plain)!.paragraphSpacing + CalloutStyle.bottomPadding)
    }

    func testChangingTheTypeChangesTheKind() {
        let storage = styled("> [!NOTE]\n> x\n\nlast")
        storage.replaceCharacters(in: (storage.string as NSString).range(of: "NOTE"), with: "WARNING")
        MarkdownStyler(theme: .midnight).style(storage, caret: (storage.string as NSString).length)
        XCTAssertEqual(blocks(at: "x", in: storage)?.map(\.kind), [.warning])
    }

    // MARK: Drawing

    private var window: NSWindow?

    override func tearDown() {
        window?.close()
    }

    /// A styled, laid-out editor in a window, as in the app, with the caret on the last line.
    private func editor(_ text: String, theme: Theme = .midnight) -> MarkdownTextView {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        self.window = window
        textView.apply(theme)
        textView.string = text
        let caret = (text as NSString).length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        let width = textView.textContainer!.size.width - 2 * textView.textContainer!.lineFragmentPadding
        MarkdownStyler(theme: theme).style(textView.textStorage!, caret: caret, availableWidth: width)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        return textView
    }

    private func boxes(_ view: MarkdownTextView) -> [NSRect] {
        let manager = view.layoutManager as! MarkdownLayoutManager
        return manager.calloutBoxes(in: NSRange(location: 0, length: (view.string as NSString).length)).map(\.rect)
    }

    /// The line holding `needle`, without spacing before it, in container coordinates.
    private func textLine(of needle: String, in view: MarkdownTextView) -> NSRect {
        let manager = view.layoutManager as! MarkdownLayoutManager
        return manager.lineRect(forGlyphAt: manager.glyphIndexForCharacter(at: (view.string as NSString).range(of: needle).location))
    }

    func testBoxSpansTheCalloutWithPadding() throws {
        let view = editor("Intro\n\n> [!NOTE]\n> one\n> two\n\nlast")
        let box = try XCTUnwrap(boxes(view).first)
        XCTAssertEqual(boxes(view).count, 1)
        XCTAssertEqual(box.minY, textLine(of: "[!NOTE]", in: view).minY - CalloutStyle.topPadding, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(box.maxY, textLine(of: "two", in: view).minY + view.theme.lineHeight + CalloutStyle.bottomPadding - 0.5)
        XCTAssertLessThan(box.maxY, textLine(of: "last", in: view).minY)
        XCTAssertEqual(box.minX, view.textContainer!.lineFragmentPadding + view.theme.quoteBarX, accuracy: 0.5)
    }

    func testAdjacentCalloutsDoNotTouchInPlain() {
        let view = editor("> [!NOTE]\n> a\n\n> [!TIP]\n> b\n\nlast", theme: .plain)
        let found = boxes(view)
        XCTAssertEqual(found.count, 2)
        guard found.count == 2 else { return }
        XCTAssertGreaterThanOrEqual(found[1].minY - found[0].maxY, view.theme.blockSpacing - 0.5)
    }

    func testNestedBoxIsInsideTheOuterBox() {
        let view = editor("> [!NOTE]\n> outer\n>\n> > [!TIP]\n> > inner\n\nlast")
        let found = boxes(view)
        XCTAssertEqual(found.count, 2)
        guard found.count == 2 else { return }
        let (outer, inner) = found[0].width > found[1].width ? (found[0], found[1]) : (found[1], found[0])
        XCTAssertTrue(outer.contains(inner))
        XCTAssertEqual(inner.maxX, outer.maxX - CalloutStyle.rightPadding, accuracy: 0.5)
    }

    func testNestedBoxEndsInsideTheOuterBox() {
        let view = editor("> [!NOTE]\n> outer\n>\n> > [!TIP]\n> > inner\n\nlast")
        let found = boxes(view)
        XCTAssertEqual(found.count, 2)
        guard found.count == 2 else { return }
        let (outer, inner) = found[0].width > found[1].width ? (found[0], found[1]) : (found[1], found[0])
        XCTAssertLessThanOrEqual(inner.maxY, outer.maxY - CalloutStyle.bottomPadding + 0.5)
    }

    func testCalloutsInConsecutiveListItemsAreSeparateBoxes() {
        for second in ["NOTE", "TIP"] {
            let view = editor("- > [!NOTE]\n  > a\n- > [!\(second)]\n  > b\n\nlast")
            let found = boxes(view).sorted { $0.minY < $1.minY }
            XCTAssertEqual(found.count, 2, second)
            guard found.count == 2 else { continue }
            XCTAssertGreaterThanOrEqual(found[1].minY - found[0].maxY, CalloutStyle.adjacentGap - 0.5, second)
        }
    }

    func testIconSitsAtTheTextStart() {
        let view = editor("> [!NOTE]\n> body\n\nlast")
        let manager = view.layoutManager as! MarkdownLayoutManager
        let icon = manager.calloutIconRect(atHeader: 0)
        let line = textLine(of: "[!NOTE]", in: view)
        XCTAssertEqual(icon.minX, line.minX + view.textContainer!.lineFragmentPadding + view.theme.quoteIndent, accuracy: 0.5)
        XCTAssertEqual(icon.midY, line.minY + view.theme.lineHeight / 2, accuracy: 0.5)
        XCTAssertEqual(icon.width, CalloutStyle.iconSize)
    }

    func testTitleStartsWhereALabelWould() {
        let view = editor("> [!TIP] Save first\n> body\n\nlast")
        let manager = view.layoutManager as! MarkdownLayoutManager
        let icon = manager.calloutIconRect(atHeader: 0)
        let title = (view.string as NSString).range(of: "Save").location
        let glyph = manager.glyphIndexForCharacter(at: title)
        let x = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minX + manager.location(forGlyphAt: glyph).x
        XCTAssertEqual(x, icon.maxX + CalloutStyle.iconGap, accuracy: 0.5)
    }

    func testTableEndingACalloutKeepsItsRowHeight() throws {
        // The callout's bottom padding is spacing after the table's last line; the grid must not grow into it.
        let view = editor("> [!WARNING]\n>\n> | Setting | Value |\n> |---|---|\n> | Mode | Strict |\n\nlast")
        let manager = view.layoutManager as! MarkdownLayoutManager
        let header = manager.tableRowRect(at: (view.string as NSString).range(of: "Setting").location)
        let last = manager.tableRowRect(at: (view.string as NSString).range(of: "Mode").location)
        XCTAssertEqual(last.height, header.height, accuracy: 0.5)
        let box = try XCTUnwrap(boxes(view).first)
        XCTAssertLessThanOrEqual(last.maxY, box.maxY - CalloutStyle.bottomPadding + 0.5)
    }

    func testCodePanelInsideACalloutStaysInsideTheBox() throws {
        let view = editor("> [!NOTE]\n> ```\n> code\n> ```\n\nlast")
        let manager = view.layoutManager as! MarkdownLayoutManager
        let box = try XCTUnwrap(boxes(view).first)
        let panel = try XCTUnwrap(manager.codePanel(at: (view.string as NSString).range(of: "code").location))
        XCTAssertLessThanOrEqual(panel.rect.maxX, box.maxX - CalloutStyle.rightPadding + 0.5)
    }

    func testTableInsideACalloutStaysInsideTheBox() throws {
        let source = "> [!WARNING]\n> | Setting | Value |\n> |---|---|\n> | Mode | Strict |\n\nlast"
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: .plain).style(storage, caret: (source as NSString).length, availableWidth: 700)
        let row = try XCTUnwrap(storage.attribute(.tableRow, at: (source as NSString).range(of: "Mode").location,
                                                  effectiveRange: nil) as? TableRowInfo)
        XCTAssertLessThanOrEqual(try XCTUnwrap(row.edges.last), 700 - CalloutStyle.rightPadding + 0.5)
        // The table interrupts the marker's paragraph, which the parser then gives no position; still a callout.
        XCTAssertNotNil(storage.attribute(.callout, at: (source as NSString).range(of: "Mode").location, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.calloutHeader, at: 0, effectiveRange: nil))
    }

    func testHeaderLineIsNotJoinedToTheBody() {
        let storage = styled("> [!NOTE]\n> body\n> more\n\nlast", joinsHardWrappedLines: true)
        let headerBreak = (storage.string as NSString).range(of: "\n").location
        XCTAssertNil(storage.attribute(.softBreak, at: headerBreak, effectiveRange: nil))
    }
}


