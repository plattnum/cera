import AppKit
import XCTest
@testable import Cera

final class CodeBlockTextTests: XCTestCase {
    /// The code of the block on the line holding `marker`, parsing the whole text.
    private func code(_ text: String, at marker: String) -> String? {
        let ns = text as NSString
        return CodeBlockText.code(in: ns, at: ns.range(of: marker).location, region: NSRange(location: 0, length: ns.length))
    }

    func testFencedBlockWithoutFences() {
        let text = "Intro\n\n```swift\nlet a = 1\nprint(a)\n```\n\nAfter\n"
        XCTAssertEqual(code(text, at: "let a"), "let a = 1\nprint(a)")
        XCTAssertEqual(code(text, at: "```swift"), "let a = 1\nprint(a)", "from the opening fence")
        XCTAssertEqual(code(text, at: "```\n\nAfter"), "let a = 1\nprint(a)", "from the closing fence")
        XCTAssertNil(code(text, at: "Intro"))
        XCTAssertNil(code(text, at: "After"))
    }

    func testTildesAndIndentationInsideTheCode() {
        XCTAssertEqual(code("~~~\ndef f():\n    return 1\n~~~\n", at: "def"), "def f():\n    return 1")
    }

    func testIndentedCodeBlockLosesItsFourSpaces() {
        XCTAssertEqual(code("Text\n\n    line one\n      line two\n", at: "line one"), "line one\n  line two")
    }

    func testBlockInAQuoteLosesTheQuoteMarkers() {
        XCTAssertEqual(code("> ```\n> echo hi\n> ls\n> ```\n", at: "echo"), "echo hi\nls")
    }

    func testBlockInAListLosesTheListIndentation() {
        let text = "- Step one:\n\n  ```sh\n  make\n  make install\n  ```\n- Step two\n"
        XCTAssertEqual(code(text, at: "make install"), "make\nmake install")
    }

    func testPicksTheRightBlockOfSeveral() {
        let text = "```\nfirst\n```\n```\nsecond\n```\n"
        XCTAssertEqual(code(text, at: "first"), "first")
        XCTAssertEqual(code(text, at: "second"), "second")
    }

    func testUnclosedFenceRunsToTheEnd() {
        XCTAssertEqual(code("```\nstill typing\nmore\n", at: "more"), "still typing\nmore")
    }

    func testEmptyBlockAndWindowsLineEndings() {
        XCTAssertEqual(code("```\n```\n", at: "```"), "")
        XCTAssertEqual(code("```\r\nA\r\nB\r\n```\r\n", at: "B"), "A\nB")
    }

    func testOutsideTheRegion() {
        let ns = "```\ncode\n```\n" as NSString
        XCTAssertNil(CodeBlockText.code(in: ns, at: 5, region: NSRange(location: 0, length: 3)))
    }
}

/// The copy button and Copy Code in a real editor.
@MainActor
final class CodeCopyButtonTests: XCTestCase {
    private var window: NSWindow!
    private var textView: MarkdownTextView!
    private var pasteboard: NSPasteboard!

    private static let document = "# Notes\n\nSome text.\n\n- Install:\n\n  ```sh\n  brew install cera\n  cera notes.md\n  ```\n\nMore text.\n"

    override func setUp() async throws {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        self.textView = textView
        textView.string = Self.document
        MarkdownStyler(theme: .midnight).style(textView.textStorage!, caret: 0, availableWidth: 600)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("cera-tests-\(UUID().uuidString)"))
        textView.codeCopyPasteboard = pasteboard
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        window.close()
    }

    private func location(of marker: String) -> Int {
        (textView.string as NSString).range(of: marker).location
    }

    /// The middle of the character at `index`, in view coordinates.
    private func point(at index: Int) -> NSPoint {
        let layoutManager = textView.layoutManager!
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textView.textContainer!)
        return NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y)
    }

    private func panelRect() throws -> NSRect {
        let panel = try XCTUnwrap((textView.layoutManager as? MarkdownLayoutManager)?.codePanel(at: location(of: "brew")))
        return panel.rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
    }

    func testButtonAppearsInTheTopRightCornerOfTheBlockUnderThePointer() throws {
        textView.updateCodeCopyButton(at: point(at: location(of: "cera notes")))
        let button = try XCTUnwrap(textView.codeCopyButton)
        XCTAssertFalse(button.isHidden)
        let panel = try panelRect()
        XCTAssertTrue(panel.contains(button.frame), "inside the panel")
        XCTAssertEqual(button.frame.maxX, panel.maxX - 6, accuracy: 0.5)
        XCTAssertEqual(button.frame.minY, panel.minY + 6, accuracy: 0.5)
    }

    func testButtonHidesAwayFromCode() throws {
        textView.updateCodeCopyButton(at: point(at: location(of: "brew")))
        XCTAssertFalse(try XCTUnwrap(textView.codeCopyButton).isHidden)
        textView.updateCodeCopyButton(at: point(at: location(of: "Some text")))
        XCTAssertTrue(try XCTUnwrap(textView.codeCopyButton).isHidden)
        textView.updateCodeCopyButton(at: point(at: location(of: "brew")))
        textView.insertText("x", replacementRange: NSRange(location: location(of: "More"), length: 0))
        XCTAssertTrue(try XCTUnwrap(textView.codeCopyButton).isHidden, "typing hides it")
    }

    func testMovingTheMouseShowsAndHidesTheButton() throws {
        func move(to index: Int) throws {
            textView.mouseMoved(with: try XCTUnwrap(NSEvent.mouseEvent(
                with: .mouseMoved, location: textView.convert(point(at: index), to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)))
        }
        try move(to: location(of: "brew"))
        XCTAssertFalse(try XCTUnwrap(textView.codeCopyButton).isHidden)
        try move(to: location(of: "More text"))
        XCTAssertTrue(try XCTUnwrap(textView.codeCopyButton).isHidden)
    }

    func testButtonStaysWhileThePointerIsOnIt() throws {
        textView.updateCodeCopyButton(at: point(at: location(of: "brew")))
        let button = try XCTUnwrap(textView.codeCopyButton)
        textView.updateCodeCopyButton(at: NSPoint(x: button.frame.midX, y: button.frame.midY))
        XCTAssertFalse(button.isHidden)
    }

    func testPanelEdgesCountButTheMarginDoesNot() throws {
        let panel = try panelRect()
        XCTAssertNotNil(textView.codeBlockLocation(at: NSPoint(x: panel.maxX - 2, y: panel.minY + 2)), "panel's corner")
        XCTAssertNil(textView.codeBlockLocation(at: NSPoint(x: panel.minX - 4, y: panel.midY)), "left of the panel")
    }

    func testClickingTheButtonCopiesJustTheCode() throws {
        textView.updateCodeCopyButton(at: point(at: location(of: "brew")))
        let button = try XCTUnwrap(textView.codeCopyButton)
        button.performClick(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "brew install cera\ncera notes.md")
    }

    func testCopyUsesTheTextAsItIsWhenClicked() throws {
        textView.updateCodeCopyButton(at: point(at: location(of: "brew")))
        let button = try XCTUnwrap(textView.codeCopyButton)
        // An edit inside the block after the button appeared.
        textView.textStorage!.replaceCharacters(in: NSRange(location: location(of: "cera notes"), length: 4), with: "open")
        textView.copyCodeBlock(button)
        XCTAssertEqual(pasteboard.string(forType: .string), "brew install cera\nopen notes.md")
    }

    func testRightClickOffersCopyCodeOnlyInCode() throws {
        func menu(at index: Int) throws -> NSMenu {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: .rightMouseDown, location: textView.convert(point(at: index), to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            return try XCTUnwrap(textView.menu(for: event))
        }
        let codeMenu = try menu(at: location(of: "brew"))
        let item = try XCTUnwrap(codeMenu.items.first)
        XCTAssertEqual(item.title, "Copy Code")
        textView.copyCodeBlock(item)
        XCTAssertEqual(pasteboard.string(forType: .string), "brew install cera\ncera notes.md")
        XCTAssertFalse(try menu(at: location(of: "Some text")).items.contains { $0.title == "Copy Code" })
    }
}
