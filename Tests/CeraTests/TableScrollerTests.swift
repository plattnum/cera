import AppKit
import XCTest
@testable import Cera

/// Scrollers over tables too wide for the column, in a real editor.
@MainActor
final class TableScrollerTests: XCTestCase {
    private var window: NSWindow!
    private var textView: MarkdownTextView!

    private static let cells = (0..<8).map { "column number \($0) heading" }
    private static let linkCells = cells.map { $0.replacingOccurrences(of: "heading", with: "[value](https://example.com)") }
    private static let wideTable: String = {
        let header = cells.joined(separator: " | ")
        let body = linkCells.joined(separator: " | ")
        let delimiter = String(repeating: "---|", count: 8)
        return "| \(header) |\n|\(delimiter)\n| \(body) |\n"
    }()
    private static let document = "# Notes\n\nIntro text.\n\n" + wideTable + "\n| a | b |\n|---|---|\n| 1 | 2 |\n\nLast line.\n"

    override func setUp() async throws {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        self.textView = textView
        textView.string = Self.document
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        style()
    }

    override func tearDown() async throws {
        window.close()
    }

    private func style(theme: Theme = .midnight) {
        textView.apply(theme)
        let width = textView.textContainer!.size.width - 2 * textView.textContainer!.lineFragmentPadding
        MarkdownStyler(theme: theme).style(textView.textStorage!, caret: textView.selectedRange().location, availableWidth: width)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        textView.updateTableScrollers()
    }

    private func location(of marker: String) -> Int {
        (textView.string as NSString).range(of: marker).location
    }

    private var wideTableRange: NSRange {
        NSRange(location: location(of: "| column number 0"), length: (Self.wideTable as NSString).length)
    }

    private func scroller() throws -> TableScroller {
        try XCTUnwrap(textView.tableScrollers[wideTableRange.location], "a scroller over the wide table")
    }

    func testWideTableGetsAScrollerAndNarrowOneDoesNot() throws {
        XCTAssertEqual(textView.tableScrollers.count, 1)
        let scroller = try scroller()
        XCTAssertTrue(scroller.superview === textView)
        XCTAssertGreaterThan(scroller.snapshot.frame.width, scroller.frame.width, "the table is wider than its scroller")
        XCTAssertEqual(scroller.snapshot.text.string, Self.wideTable, "it shows exactly the table")
    }

    func testScrollerLiesOverTheTableAndReachesTheColumnsRightEdge() throws {
        let scroller = try scroller()
        let layoutManager = textView.layoutManager!, container = textView.textContainer!
        let glyphs = layoutManager.glyphRange(forCharacterRange: wideTableRange, actualCharacterRange: nil)
        var lines = NSRect.null
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in lines = lines.union(rect) }
        let table = lines.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        XCTAssertEqual(scroller.frame.minY, table.minY.rounded(.down))
        XCTAssertEqual(scroller.frame.maxY, table.maxY.rounded(.up) + scroller.scrollerHeight, "room for the bar under it")
        XCTAssertEqual(scroller.frame.minX, textView.textContainerOrigin.x + container.lineFragmentPadding, accuracy: 0.5)
        XCTAssertEqual(scroller.frame.maxX, textView.textContainerOrigin.x + container.size.width, accuracy: 0.5)
    }

    func testCopyLinesUpWithTheTableItCoversWithOverlayScrollBars() throws {
        try checkCopyLinesUp(style: .overlay)
    }

    func testCopyLinesUpWithTheTableItCoversWithLegacyScrollBars() throws {
        try checkCopyLinesUp(style: .legacy)
    }

    private func checkCopyLinesUp(style: NSScroller.Style) throws {
        try scroller().scrollerStyle = style
        textView.updateTableScrollers()
        let scroller = try scroller()
        XCTAssertEqual(scroller.scrollerStyle, style)
        let snapshot = scroller.snapshot
        // The second row's first cell, in the document and in the copy, in text view coordinates.
        let cell = (Self.wideTable as NSString).range(of: "| column number 0 [value]").location + 2
        let layoutManager = textView.layoutManager!
        let inDocument = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: layoutManager.glyphIndexForCharacter(at: wideTableRange.location + cell), length: 1),
            in: textView.textContainer!).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
        let inCopy = snapshot.layoutManager.boundingRect(
            forGlyphRange: NSRange(location: snapshot.layoutManager.glyphIndexForCharacter(at: cell), length: 1),
            in: snapshot.layoutManager.textContainers[0]).offsetBy(dx: snapshot.textOrigin.x, dy: snapshot.textOrigin.y)
        let shown = textView.convert(inCopy, from: snapshot)
        XCTAssertEqual(shown.minY, inDocument.minY, accuracy: 0.5)
        XCTAssertEqual(shown.minX, inDocument.minX, accuracy: 0.5)
        XCTAssertEqual(textView.convert(snapshot.bounds, from: snapshot).minY, scroller.frame.minY, accuracy: 0.5,
                       "the copy starts at the top, leaving the space under it for the scroll bar")
    }

    func testCaretInTheTableRemovesTheScrollerAndLeavingBringsItBack() throws {
        let scroller = try scroller()
        scroller.offset = 120
        textView.setSelectedRange(NSRange(location: location(of: "column number 3"), length: 0))
        style()
        XCTAssertNil(textView.tableScrollers[wideTableRange.location], "the table shows as text while it is edited")
        textView.setSelectedRange(NSRange(location: location(of: "Last line"), length: 0))
        style()
        XCTAssertEqual(try self.scroller().offset, 120, accuracy: 0.5, "it comes back scrolled where it was")
    }

    func testSelectionAcrossTheTableRemovesTheScroller() {
        textView.setSelectedRange(NSRange(location: location(of: "Intro"), length: 10))
        textView.updateTableScrollers()
        XCTAssertEqual(textView.tableScrollers.count, 1, "a selection elsewhere leaves it")
        textView.selectAll(nil)
        textView.updateTableScrollers()
        XCTAssertTrue(textView.tableScrollers.isEmpty)
    }

    func testOffsetSurvivesAThemeChange() throws {
        try scroller().offset = 200
        style(theme: .plain)
        XCTAssertEqual(try scroller().offset, 200, accuracy: 0.5)
        XCTAssertEqual(try scroller().snapshot.layoutManager.theme.name, Theme.plain.name)
    }

    func testOffsetStopsAtTheTablesEnd() throws {
        let scroller = try scroller()
        scroller.offset = 100_000
        XCTAssertEqual(scroller.offset, scroller.snapshot.frame.width - scroller.contentView.bounds.width, accuracy: 0.5)
        scroller.offset = -50
        XCTAssertEqual(scroller.offset, 0)
    }

    func testTableThatNowFitsLosesItsScroller() {
        textView.string = "| a | b |\n|---|---|\n| 1 | 2 |\n\nLast line.\n"
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        style()
        XCTAssertTrue(textView.tableScrollers.isEmpty)
    }

    func testClickingAScrolledCellPutsTheCaretOnThatCharacter() throws {
        let scroller = try scroller()
        scroller.offset = 100_000
        let snapshot = scroller.snapshot
        // The last cell's text, found in the copy's own layout.
        let target = (Self.wideTable as NSString).range(of: "column number 7 heading").location + 7
        let glyph = snapshot.layoutManager.glyphIndexForCharacter(at: target)
        let rect = snapshot.layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                                       in: snapshot.layoutManager.textContainers[0])
        let point = NSPoint(x: rect.minX + 1 + snapshot.textOrigin.x, y: rect.midY + snapshot.textOrigin.y)
        XCTAssertEqual(snapshot.characterIndex(at: point), target)

        textView.clickTable(at: scroller.location + target, with: try clickEvent())
        XCTAssertEqual(textView.selectedRange(), NSRange(location: wideTableRange.location + target, length: 0))
    }

    func testClickPastARowsEndStaysOnThatRow() throws {
        let snapshot = try scroller().snapshot
        let index = try XCTUnwrap(snapshot.characterIndex(at: NSPoint(x: snapshot.frame.width + 500, y: 5)))
        let headerEnd = (Self.wideTable as NSString).range(of: "\n").location
        XCTAssertEqual(index, headerEnd)
    }

    /// A mouse-wheel event (no gesture phase) with the given deltas, in lines.
    private func wheelEvent(dx: Int32, dy: Int32) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    func testVerticalWheelOverTheTableScrollsThePageAndHorizontalScrollsTheTable() throws {
        textView.string = Self.document + String(repeating: "More text.\n\n", count: 200)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        style()
        let scroller = try scroller()
        let page = try XCTUnwrap(textView.enclosingScrollView)
        let pageBefore = page.contentView.bounds.origin.y

        scroller.scrollWheel(with: try wheelEvent(dx: 0, dy: -5))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNotEqual(page.contentView.bounds.origin.y, pageBefore, "the page scrolls")
        XCTAssertEqual(scroller.offset, 0, "the table doesn't")

        let pageAfter = page.contentView.bounds.origin.y
        scroller.scrollWheel(with: try wheelEvent(dx: -5, dy: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5)) // Wheel scrolling is animated.
        XCTAssertGreaterThan(scroller.offset, 0, "the table scrolls")
        XCTAssertEqual(page.contentView.bounds.origin.y, pageAfter, "the page doesn't")
    }

    func testUpdatingWhenNothingChangedSchedulesNoFurtherUpdates() {
        textView.updateTableScrollers()
        XCTAssertFalse(textView.tableScrollersNeedUpdate, "updating doesn't lay out again and ask for another update")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(textView.tableScrollersNeedUpdate)
    }

    private func clickEvent(modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
}
