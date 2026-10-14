import AppKit
import XCTest
@testable import Cera

final class FormatCommandsTests: XCTestCase {
    private var window: NSWindow!

    override func tearDown() {
        window?.close()
    }

    /// A text view in a window, as in the app, with `text` and the given selection.
    private func editor(_ text: String, select range: NSRange) -> MarkdownTextView {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(range)
        return textView
    }

    private func all(_ text: String) -> NSRange { NSRange(location: 0, length: (text as NSString).length) }

    // MARK: Headings

    func testHeadingLevelsAndToggle() {
        let view = editor("Title", select: NSRange(location: 2, length: 0))
        view.heading4(nil)
        XCTAssertEqual(view.string, "#### Title")
        view.heading4(nil)
        XCTAssertEqual(view.string, "Title")
    }

    func testMakeHeadingLargerAndSmaller() {
        let view = editor("Title", select: NSRange(location: 0, length: 0))
        view.makeHeadingLarger(nil)
        XCTAssertEqual(view.string, "###### Title")
        view.makeHeadingLarger(nil)
        XCTAssertEqual(view.string, "##### Title")
        view.makeHeadingSmaller(nil)
        view.makeHeadingSmaller(nil)
        XCTAssertEqual(view.string, "Title")
    }

    func testParagraphRemovesHeading() {
        let view = editor("## Title", select: NSRange(location: 4, length: 0))
        view.paragraph(nil)
        XCTAssertEqual(view.string, "Title")
    }

    // MARK: Lists and quotes

    func testBulletedListTogglesOnAndOff() {
        let text = "one\ntwo"
        let view = editor(text, select: all(text))
        view.toggleBulletedList(nil)
        XCTAssertEqual(view.string, "- one\n- two")
        view.toggleBulletedList(nil)
        XCTAssertEqual(view.string, "one\ntwo")
    }

    func testNumberedListNumbersLinesAndConvertsBullets() {
        let text = "- one\n- two\n\n- three"
        let view = editor(text, select: all(text))
        view.toggleNumberedList(nil)
        XCTAssertEqual(view.string, "1. one\n2. two\n\n3. three")
    }

    func testTaskList() {
        let view = editor("buy milk", select: NSRange(location: 0, length: 0))
        view.toggleTaskList(nil)
        XCTAssertEqual(view.string, "- [ ] buy milk")
    }

    func testQuoteTogglesOnAndOff() {
        let text = "one\n\ntwo"
        let view = editor(text, select: all(text))
        view.toggleQuote(nil)
        XCTAssertEqual(view.string, "> one\n>\n> two")
        view.toggleQuote(nil)
        XCTAssertEqual(view.string, "one\n\ntwo")
    }

    func testTabIndentsListItemsOnly() {
        let view = editor("- item", select: NSRange(location: 6, length: 0))
        view.insertTab(nil)
        XCTAssertEqual(view.string, "    - item")
        view.insertBacktab(nil)
        XCTAssertEqual(view.string, "- item")

        let plain = editor("text", select: NSRange(location: 4, length: 0))
        plain.insertTab(nil)
        XCTAssertEqual(plain.string, "text\t")
    }

    // MARK: Inserted blocks

    func testCodeBlockWrapsSelectedLines() {
        let text = "let a = 1\nlet b = 2"
        let view = editor(text, select: all(text))
        view.insertCodeBlock(nil)
        XCTAssertEqual(view.string, "```\nlet a = 1\nlet b = 2\n```")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testEmptyCodeBlockPutsCursorInside() {
        let view = editor("", select: NSRange(location: 0, length: 0))
        view.insertCodeBlock(nil)
        XCTAssertEqual(view.string, "```\n\n```")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testTableInsertedAsOwnParagraphWithFirstHeaderSelected() {
        let view = editor("intro", select: NSRange(location: 5, length: 0))
        view.insertTable(nil)
        XCTAssertTrue(view.string.hasPrefix("intro\n\n| Column 1 | Column 2 | Column 3 |\n| -------- |"))
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "Column 1")
    }

    func testHorizontalRuleSplitsAParagraph() {
        let view = editor("beforeafter", select: NSRange(location: 6, length: 0))
        view.insertHorizontalRule(nil)
        XCTAssertEqual(view.string, "before\n\n---\n\nafter")
    }

    func testClearFormattingKeepsText() {
        let text = "**bold** *it* `code` ~~old~~ [site](https://a.b)"
        let view = editor(text, select: all(text))
        view.clearFormatting(nil)
        XCTAssertEqual(view.string, "bold it code old site")
    }

    /// Selecting rendered text selects only the visible characters, not the hidden markers.
    private func clear(_ text: String, selecting word: String) -> MarkdownTextView {
        let view = editor(text, select: (text as NSString).range(of: word))
        view.topLevelBlocks = { MarkdownStyler.topLevelBlocks(in: view.string as NSString) }
        view.clearFormatting(nil)
        return view
    }

    func testClearFormattingRemovesMarkersAroundSelectedText() {
        let view = clear("Some **bold** text", selecting: "bold")
        XCTAssertEqual(view.string, "Some bold text")
        XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "bold")

        XCTAssertEqual(clear("an *it* word", selecting: "it").string, "an it word")
        XCTAssertEqual(clear("~~old~~ news", selecting: "old").string, "old news")
        XCTAssertEqual(clear("run `ls -la` now", selecting: "ls").string, "run ls -la now")
        XCTAssertEqual(clear("run `` `x` `` now", selecting: "x").string, "run `x` now")
        XCTAssertEqual(clear("see [the site](https://a.b) ok", selecting: "site").string, "see the site ok")
        XCTAssertEqual(clear("go <https://a.b> ok", selecting: "a.b").string, "go https://a.b ok")
    }

    func testClearFormattingNestedAndPartialSpans() {
        XCTAssertEqual(clear("A ***both*** B", selecting: "both").string, "A both B")
        XCTAssertEqual(clear("**bold *and it* end**", selecting: "and").string, "bold and it end")
        XCTAssertEqual(clear("x **longer bold** y", selecting: "ger b").string, "x longer bold y")
        // Spans the selection doesn't touch keep their formatting.
        XCTAssertEqual(clear("**one** two **three**", selecting: "two").string, "**one** two **three**")
        XCTAssertEqual(clear("**one** two **three**", selecting: "one** two").string, "one two **three**")
    }

    func testFormatBarEraserClearsSelectedText() throws {
        let text = "Some **bold** text"
        let view = editor(text, select: NSRange(location: 0, length: 0))
        view.setSelectedRange((text as NSString).range(of: "bold"))
        let bar = try XCTUnwrap(view.formatBar)
        XCTAssertFalse(bar.isHidden)
        func buttons(in view: NSView) -> [NSButton] {
            view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons(in: $0) }
        }
        let eraser = try XCTUnwrap(buttons(in: bar).first { $0.toolTip?.hasPrefix("Clear Formatting") == true })
        // A click on the middle of the eraser reaches the eraser, not the text underneath.
        bar.layoutSubtreeIfNeeded()
        let center = eraser.convert(NSPoint(x: eraser.bounds.midX, y: eraser.bounds.midY), to: view)
        XCTAssertTrue(view.hitTest(center) === eraser, "a click on the eraser reaches it")
        eraser.performClick(nil)
        XCTAssertEqual(view.string, "Some bold text")
    }

    func testClearFormattingAcrossLinesAndInContext() {
        let view = clear("- **first** item\n- *second* item", selecting: "first** item\n- *sec")
        XCTAssertEqual(view.string, "- first item\n- second item")
        // Asterisks inside a code block aren't formatting.
        XCTAssertEqual(clear("```\n**not bold**\n```", selecting: "not").string, "```\n**not bold**\n```")
    }

    func testCommandsAreUndoable() throws {
        let view = editor("one", select: NSRange(location: 0, length: 0))
        let undo = try XCTUnwrap(view.undoManager)
        undo.beginUndoGrouping()
        view.toggleBulletedList(nil)
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, "- one")
        undo.undo()
        XCTAssertEqual(view.string, "one")
    }

    // MARK: Format bar

    func testFormatBarAppearsAboveSelectionAndHidesWhenCleared() throws {
        let text = "\n\n\n\nSome text to format here."
        let view = editor(text, select: NSRange(location: 0, length: 0))
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        XCTAssertTrue(view.formatBar?.isHidden ?? true)

        view.setSelectedRange((text as NSString).range(of: "text"))
        let bar = try XCTUnwrap(view.formatBar)
        XCTAssertFalse(bar.isHidden)
        XCTAssertTrue(view.visibleRect.contains(bar.frame))

        view.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertTrue(bar.isHidden)
    }

    func testFormatBarGoesBelowWhenNoRoomAbove() throws {
        let text = "First line selected."
        let view = editor(text, select: NSRange(location: 0, length: 5))
        let bar = try XCTUnwrap(view.formatBar)
        let glyphs = view.layoutManager!.glyphRange(forCharacterRange: NSRange(location: 0, length: 5), actualCharacterRange: nil)
        let selected = view.layoutManager!.boundingRect(forGlyphRange: glyphs, in: view.textContainer!)
        XCTAssertGreaterThanOrEqual(bar.frame.minY, selected.maxY + view.textContainerOrigin.y)
    }
}
