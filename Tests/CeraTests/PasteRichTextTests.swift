import AppKit
import XCTest
@testable import Cera

/// Pasting HTML from the clipboard as Markdown.
final class PasteRichTextTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var window: NSWindow?

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("cera-tests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        window?.close()
    }

    /// A text view in a window (for undo), holding `text` with the insertion point at `caret` (the end by default).
    private func view(_ text: String, caret: Int? = nil) -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window?.isReleasedWhenClosed = false
        window?.contentView = view
        view.allowsUndo = true
        view.string = text
        view.topLevelBlocks = { MarkdownStyler.topLevelBlocks(in: view.string as NSString) }
        view.pastePasteboard = pasteboard
        view.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        return view
    }

    /// Puts HTML and its plain text on the test's pasteboard, as a browser does.
    private func copy(html: String, plain: String) {
        pasteboard.clearContents()
        pasteboard.declareTypes([.html, .string], owner: nil)
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(plain, forType: .string)
    }

    func testHTMLPastesAsMarkdown() {
        let view = view("Notes:\n\n")
        copy(html: "<h2>Plan</h2><ul><li><b>Ship</b> it</li><li>Tell <a href=\"https://a.b\">people</a></li></ul>",
             plain: "Plan\nShip it\nTell people")
        view.paste(nil)
        XCTAssertEqual(view.string, "Notes:\n\n## Plan\n\n- **Ship** it\n- Tell [people](https://a.b)")
        XCTAssertEqual(view.selectedRange().location, (view.string as NSString).length, "the insertion point is after it")
    }

    func testOneUndoTakesItBack() throws {
        let view = view("a ")
        copy(html: "<b>bold</b>", plain: "bold")
        let undo = try XCTUnwrap(view.undoManager)
        undo.beginUndoGrouping()
        view.paste(nil)
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, "a **bold**")
        XCTAssertEqual(undo.undoActionName, "Paste")
        undo.undo()
        XCTAssertEqual(view.string, "a ")
    }

    func testPastedLinesStayInTheListItemOrQuote() {
        let item = view("- first\n- ")
        copy(html: "<p>one</p><p>two</p>", plain: "one\ntwo")
        item.paste(nil)
        XCTAssertEqual(item.string, "- first\n- one\n\n  two")

        let quote = view("> ")
        copy(html: "<p>one</p><p>two</p>", plain: "one\ntwo")
        quote.paste(nil)
        XCTAssertEqual(quote.string, "> one\n>\n> two")
    }

    func testSafariWebArchive() throws {
        let view = view("")
        let archive: [String: Any] = ["WebMainResource": [
            "WebResourceData": Data("<p><i>from Safari</i></p>".utf8), "WebResourceTextEncodingName": "UTF-8",
            "WebResourceMIMEType": "text/html", "WebResourceURL": "about:blank"
        ]]
        pasteboard.clearContents()
        pasteboard.declareTypes([MarkdownTextView.webArchiveType, .string], owner: nil)
        pasteboard.setData(try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0),
                           forType: MarkdownTextView.webArchiveType)
        pasteboard.setString("from Safari", forType: .string)
        view.paste(nil)
        XCTAssertEqual(view.string, "*from Safari*")
    }

    // MARK: Left to the plain paste

    func testNotInCode() {
        copy(html: "<b>bold</b>", plain: "bold")
        let block = view("```\nlet a = 1\n\n```", caret: 14)
        XCTAssertFalse(block.pasteRichText(from: pasteboard), "in a code block")
        let span = view("Call `name` here.", caret: 7)
        XCTAssertFalse(span.pasteRichText(from: pasteboard), "in a code span")
        let after = view("Call `name` here.", caret: 11)
        XCTAssertTrue(after.pasteRichText(from: pasteboard), "just after a code span is ordinary text")
    }

    func testNotInFrontMatter() {
        copy(html: "<b>bold</b>", plain: "bold")
        let view = view("---\ntitle: x\n---\n# Heading\n", caret: 11)
        XCTAssertFalse(view.pasteRichText(from: pasteboard))
    }

    func testNotForASingleURL() {
        // A browser's address bar can put the URL on the clipboard as HTML too.
        copy(html: "<a href=\"https://a.b/c\">https://a.b/c</a>", plain: "https://a.b/c")
        XCTAssertFalse(view("").pasteRichText(from: pasteboard))
    }

    func testNotForACodeEditorsCopy() {
        copy(html: "<div style=\"font-family: Menlo, monospace;\"><div><span style=\"color: #569cd6;\">let</span> a = 1</div></div>",
             plain: "let a = 1")
        XCTAssertFalse(view("").pasteRichText(from: pasteboard))
    }

    func testNotWithoutHTML() {
        pasteboard.clearContents()
        pasteboard.setString("plain", forType: .string)
        XCTAssertFalse(view("").pasteRichText(from: pasteboard))
    }
}
