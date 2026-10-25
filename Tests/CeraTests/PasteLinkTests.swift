import AppKit
import XCTest
@testable import Cera

/// Pasting a URL over selected text makes a link, `[text](url)`.
final class PasteLinkTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var window: NSWindow?

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("cera-tests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        window?.close()
    }

    /// A text view holding `text` with `selected` selected, pasting from the test's own pasteboard.
    private func view(_ text: String, selecting selected: String) -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.allowsUndo = true
        view.string = text
        view.topLevelBlocks = { MarkdownStyler.topLevelBlocks(in: view.string as NSString) }
        view.pastePasteboard = pasteboard
        view.setSelectedRange((text as NSString).range(of: selected))
        return view
    }

    /// Pastes `clipboard` over `selected` in `text` and returns the result.
    private func paste(_ clipboard: String, over selected: String, in text: String) -> MarkdownTextView {
        let view = view(text, selecting: selected)
        pasteboard.clearContents()
        pasteboard.setString(clipboard, forType: .string)
        view.paste(nil)
        return view
    }

    // MARK: Making a link

    func testURLOverSelectedTextMakesALink() {
        let view = paste("https://example.com/docs", over: "the docs", in: "Read the docs first.")
        XCTAssertEqual(view.string, "Read [the docs](https://example.com/docs) first.")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 41, length: 0), "the insertion point is after the link")
    }

    func testSpaceAndLineBreakAroundTheURLAreIgnored() {
        XCTAssertEqual(paste("  https://a.b/c\n", over: "word", in: "a word").string, "a [word](https://a.b/c)")
    }

    func testMailtoMakesALink() {
        XCTAssertEqual(paste("mailto:me@example.com", over: "write", in: "write me").string, "[write](mailto:me@example.com) me")
    }

    func testUnbalancedParenthesesGoInAngleBrackets() {
        XCTAssertEqual(paste("https://a.b/x)", over: "x", in: "x").string, "[x](<https://a.b/x)>)")
        XCTAssertEqual(paste("https://en.wikipedia.org/wiki/Swift_(language)", over: "Swift", in: "Swift").string,
                       "[Swift](https://en.wikipedia.org/wiki/Swift_(language))", "balanced ones are fine as they are")
    }

    func testUnbalancedBracketsInTheTextAreEscaped() {
        XCTAssertEqual(paste("https://a.b", over: "a ] b", in: "a ] b").string, "[a \\] b](https://a.b)")
        XCTAssertEqual(paste("https://a.b", over: "a [1] b", in: "a [1] b").string, "[a [1] b](https://a.b)")
    }

    func testWorksInAListItemAndAHeading() {
        XCTAssertEqual(paste("https://a.b", over: "item", in: "- an item").string, "- an [item](https://a.b)")
        XCTAssertEqual(paste("https://a.b", over: "Title", in: "## Title").string, "## [Title](https://a.b)")
    }

    func testOneUndoBringsTheTextBack() throws {
        let view = view("Read the docs.", selecting: "the docs")
        // The undo manager comes from the window, as in the app.
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window?.isReleasedWhenClosed = false
        window?.contentView = view
        pasteboard.clearContents()
        pasteboard.setString("https://example.com", forType: .string)
        let undo = try XCTUnwrap(view.undoManager)
        undo.beginUndoGrouping()
        view.paste(nil)
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, "Read [the docs](https://example.com).")
        XCTAssertEqual(undo.undoActionName, "Paste")
        undo.undo()
        XCTAssertEqual(view.string, "Read the docs.")
    }

    // MARK: Pasting as usual

    /// Asserts that pasting `clipboard` over `selected` just replaces it.
    private func assertPlainPaste(_ clipboard: String, over selected: String, in text: String, _ message: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let view = view(text, selecting: selected)
        XCTAssertFalse(view.pasteLink(clipboard), message, file: file, line: line)
        XCTAssertEqual(view.string, text, message, file: file, line: line)
    }

    func testOnlyOneURLMakesALink() {
        assertPlainPaste("just words", over: "word", in: "a word", "text")
        assertPlainPaste("https://a.b https://c.d", over: "word", in: "a word", "two URLs")
        assertPlainPaste("see https://a.b", over: "word", in: "a word", "a URL with words")
        assertPlainPaste("example.com", over: "word", in: "a word", "no scheme")
        assertPlainPaste("https://", over: "word", in: "a word", "a scheme alone")
        assertPlainPaste("note: this", over: "word", in: "a word", "a colon isn't a URL")
    }

    func testNoSelectionPastesTheURL() {
        let view = view("a word", selecting: "")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertFalse(view.pasteLink("https://a.b"))
    }

    func testURLOverAURLReplacesIt() {
        assertPlainPaste("https://new.example", over: "https://old.example", in: "see https://old.example", "a URL selected")
    }

    func testSelectionAcrossLinesIsReplaced() {
        assertPlainPaste("https://a.b", over: "one\ntwo", in: "one\ntwo", "two lines")
    }

    func testNotInCodeLinksHTMLOrFrontMatter() {
        assertPlainPaste("https://a.b", over: "name", in: "Call `name` here.", "a code span")
        assertPlainPaste("https://a.b", over: "name", in: "```\nlet name = 1\n```\n", "a code block")
        assertPlainPaste("https://a.b", over: "docs", in: "Read [the docs](https://x.y).", "a link's text")
        assertPlainPaste("https://a.b", over: "alt", in: "![alt text](p.png)", "an image's text")
        assertPlainPaste("https://a.b", over: "some", in: "<div>\nsome text\n</div>\n", "a raw HTML block")
        assertPlainPaste("https://a.b", over: "Notes", in: "---\ntitle: Notes\n---\n# Heading\n", "front matter")
    }
}
