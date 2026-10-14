import AppKit
import XCTest
@testable import Cera

/// Tests run against a real NSTextView, so they exercise the same code path as the app.
final class MarkdownEditingTests: XCTestCase {

    /// Builds the text system explicitly, as NSTextView does when created from a storage.
    private func makeTextView(_ text: String, selection: NSRange) -> MarkdownTextView {
        let storage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)
        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        textView.setSelectedRange(selection)
        return textView
    }

    /// Regression test: the app's editor must accept text set after creation.
    /// This was broken once (blank editor) and the tests above used a different setup.
    func testEditorFactoryAcceptsStringAfterCreation() {
        let textView = MarkdownTextView.makeEditor(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNotNil(textView.textStorage)
        textView.string = "hello"
        XCTAssertEqual(textView.string, "hello")
    }

    // MARK: - List and quote continuation on Return

    func testReturnContinuesBulletList() {
        let textView = makeTextView("- apple", selection: NSRange(location: 7, length: 0))
        textView.insertNewline(nil)
        XCTAssertEqual(textView.string, "- apple\n- ")
    }

    func testReturnIncrementsNumberedList() {
        let textView = makeTextView("1. one\n2. two", selection: NSRange(location: 13, length: 0))
        textView.insertNewline(nil)
        XCTAssertEqual(textView.string, "1. one\n2. two\n3. ")
    }

    func testReturnKeepsTaskItemUnchecked() {
        let textView = makeTextView("- [x] done", selection: NSRange(location: 10, length: 0))
        textView.insertNewline(nil)
        XCTAssertEqual(textView.string, "- [x] done\n- [ ] ")
    }

    func testReturnContinuesQuoteAndKeepsIndent() {
        let textView = makeTextView("  > note", selection: NSRange(location: 8, length: 0))
        textView.insertNewline(nil)
        XCTAssertEqual(textView.string, "  > note\n  > ")
    }

    func testReturnOnEmptyItemEndsTheList() {
        let textView = makeTextView("- apple\n- ", selection: NSRange(location: 10, length: 0))
        textView.insertNewline(nil)
        XCTAssertEqual(textView.string, "- apple\n")
    }

    func testReturnOnPlainLineInsertsOnlyNewline() {
        let textView = makeTextView("plain", selection: NSRange(location: 5, length: 0))
        textView.insertNewline(nil)
        XCTAssertEqual(textView.string, "plain\n")
    }

    // MARK: - Format menu

    func testBoldWrapsSelection() {
        let textView = makeTextView("hello world", selection: NSRange(location: 6, length: 5))
        textView.toggleBold(nil)
        XCTAssertEqual(textView.string, "hello **world**")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 5))
    }

    func testBoldTogglesOff() {
        let textView = makeTextView("hello **world**", selection: NSRange(location: 8, length: 5))
        textView.toggleBold(nil)
        XCTAssertEqual(textView.string, "hello world")
    }

    func testInlineCodeWrapsEmptySelectionWithCaretInside() {
        let textView = makeTextView("x", selection: NSRange(location: 1, length: 0))
        textView.toggleInlineCode(nil)
        XCTAssertEqual(textView.string, "x``")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testLinkInsertsTemplateAndSelectsURL() {
        let textView = makeTextView("see docs", selection: NSRange(location: 4, length: 4))
        textView.insertLink(nil)
        XCTAssertEqual(textView.string, "see [docs](https://)")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 11, length: 8))
    }

    func testHeadingSetsLevelAndSecondPressRemovesIt() {
        let textView = makeTextView("Title", selection: NSRange(location: 2, length: 0))
        textView.heading2(nil)
        XCTAssertEqual(textView.string, "## Title")
        textView.heading2(nil)
        XCTAssertEqual(textView.string, "Title")
    }

    func testHeadingChangesExistingLevel() {
        let textView = makeTextView("# Title", selection: NSRange(location: 3, length: 0))
        textView.heading3(nil)
        XCTAssertEqual(textView.string, "### Title")
    }

    // MARK: - Undo

    func testFormattingIsUndoable() throws {
        let textView = makeTextView("hello", selection: NSRange(location: 0, length: 5))
        // Undo lives on the window's undo manager, so the view must be in a window.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = textView
        textView.allowsUndo = true
        let undoManager = try XCTUnwrap(textView.undoManager)

        // AppKit opens an undo group per user action; outside the event loop the test opens one itself.
        undoManager.beginUndoGrouping()
        textView.toggleBold(nil)
        undoManager.endUndoGrouping()
        XCTAssertEqual(textView.string, "**hello**")
        undoManager.undo()
        XCTAssertEqual(textView.string, "hello")
    }
}
