import AppKit
import XCTest
@testable import Cera

/// Task checkboxes: drawn in the right place, toggled by a click or by Toggle Checked (⌘L).
final class CheckboxTests: XCTestCase {
    private var window: NSWindow!

    override func tearDown() {
        window?.close()
    }

    /// A styled, laid-out editor in a window, as in the app. The caret is at the end unless `caret` says otherwise.
    private func editor(_ text: String, theme: Theme = .ivory, caret: Int? = nil) -> MarkdownTextView {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        textView.allowsUndo = true
        textView.apply(theme)
        textView.string = text
        let caret = caret ?? (text as NSString).length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        restyle(textView)
        return textView
    }

    private func restyle(_ textView: MarkdownTextView) {
        MarkdownStyler(theme: textView.theme).style(textView.textStorage!, caret: textView.selectedRange().location)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
    }

    private func layoutManager(_ textView: MarkdownTextView) -> MarkdownLayoutManager {
        textView.layoutManager as! MarkdownLayoutManager
    }

    private func location(of needle: String, in textView: MarkdownTextView) -> Int {
        (textView.string as NSString).range(of: needle).location
    }

    /// The center of the checkbox drawn for the line holding `needle`, in view coordinates. Lays the text out
    /// first, as drawing does before the user can click: right after an edit, positions are out of date.
    private func checkboxCenter(on needle: String, in textView: MarkdownTextView) -> NSPoint {
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        let line = (textView.string as NSString).lineRange(for: NSRange(location: location(of: needle, in: textView), length: 0))
        let box = layoutManager(textView).checkboxRect(at: line.location)
        return NSPoint(x: box.midX + textView.textContainerOrigin.x, y: box.midY + textView.textContainerOrigin.y)
    }

    private func bullet(at index: Int, in storage: NSTextStorage) -> String? {
        storage.attribute(.listBullet, at: index, effectiveRange: nil) as? String
    }

    // MARK: Drawing

    func testTaskInsideAQuoteIsACheckbox() {
        // The parser misses task items inside quotes; the source still says they are tasks.
        let source = "> - [ ] open\n> - [x] done\n\nlast"
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: .ivory).style(storage, caret: (source as NSString).length)
        XCTAssertEqual(bullet(at: 0, in: storage), "☐")
        XCTAssertEqual(bullet(at: (source as NSString).range(of: "> - [x]").location, in: storage), "☑")
    }

    func testCheckboxIsCenteredOnItsTextWhenTheListFollowsAnotherBlock() {
        // No blank line between the lists, so the numbered list gets the block gap as space before it.
        let view = editor("- [x] a\n1. [ ] A numbered task\n2. [x] B\n\nlast")
        let manager = layoutManager(view)
        for needle in ["a\n", "A numbered task", "B"] {
            let index = location(of: needle, in: view)
            let line = (view.string as NSString).lineRange(for: NSRange(location: index, length: 0))
            let box = manager.checkboxRect(at: line.location)
            let text = manager.lineFragmentUsedRect(forGlyphAt: manager.glyphIndexForCharacter(at: index), effectiveRange: nil)
            XCTAssertEqual(box.midY, text.minY + view.theme.lineHeight / 2, accuracy: 0.5, needle)
        }
    }

    // MARK: Clicking

    func testClickingABoxTogglesIt() {
        let view = editor("- [ ] open\n- [x] done\n- [X] shouting\n\nlast")
        XCTAssertTrue(view.toggleCheckbox(at: checkboxCenter(on: "open", in: view)))
        XCTAssertTrue(view.toggleCheckbox(at: checkboxCenter(on: "done", in: view)))
        XCTAssertTrue(view.toggleCheckbox(at: checkboxCenter(on: "shouting", in: view)))
        XCTAssertEqual(view.string, "- [x] open\n- [ ] done\n- [ ] shouting\n\nlast")
    }

    func testMouseDownOnABoxTogglesIt() throws {
        // The whole path a click takes: the event, then the hit test, then the edit.
        let view = editor("- [ ] open\n\nlast")
        let point = view.convert(checkboxCenter(on: "open", in: view), to: nil)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                                                     timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                     eventNumber: 0, clickCount: 1, pressure: 1))
        view.mouseDown(with: event)
        XCTAssertEqual(view.string, "- [x] open\n\nlast")
    }

    func testClickingKeepsTheCaretAndSelection() {
        let view = editor("- [ ] open\n\nsome text here", caret: 15)
        view.setSelectedRange(NSRange(location: 14, length: 4))
        XCTAssertTrue(view.toggleCheckbox(at: checkboxCenter(on: "open", in: view)))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 14, length: 4))
    }

    func testClickingNestedNumberedAndQuotedBoxes() {
        let view = editor("- [ ] top\n  - [ ] nested\n\n1. [x] numbered\n\n> - [ ] quoted\n\nlast")
        for needle in ["nested", "numbered", "quoted"] {
            XCTAssertTrue(view.toggleCheckbox(at: checkboxCenter(on: needle, in: view)), needle)
            restyle(view)
        }
        XCTAssertEqual(view.string, "- [ ] top\n  - [x] nested\n\n1. [ ] numbered\n\n> - [x] quoted\n\nlast")
    }

    func testClickingTheTextOrABulletDoesNothing() {
        let view = editor("- [ ] open\n- plain\n\nlast")
        let textPoint = checkboxCenter(on: "open", in: view).applying(.init(translationX: 60, y: 0))
        XCTAssertFalse(view.toggleCheckbox(at: textPoint))
        let line = (view.string as NSString).lineRange(for: NSRange(location: location(of: "plain", in: view), length: 0))
        let bulletBox = layoutManager(view).checkboxRect(at: line.location)
        XCTAssertFalse(view.toggleCheckbox(at: NSPoint(x: bulletBox.midX + view.textContainerOrigin.x,
                                                        y: bulletBox.midY + view.textContainerOrigin.y)))
        XCTAssertEqual(view.string, "- [ ] open\n- plain\n\nlast")
    }

    func testNoBoxOnTheLineBeingEdited() {
        // The caret's line shows its Markdown, so there is no box to click.
        let view = editor("- [ ] open\n\nlast", caret: 8)
        let line = layoutManager(view).checkboxRect(at: 0)
        XCTAssertFalse(view.toggleCheckbox(at: NSPoint(x: line.midX + view.textContainerOrigin.x,
                                                        y: line.midY + view.textContainerOrigin.y)))
        XCTAssertEqual(view.string, "- [ ] open\n\nlast")
    }

    func testClickIsUndoable() throws {
        let view = editor("- [ ] open\n\nlast")
        let undo = try XCTUnwrap(view.undoManager)
        undo.beginUndoGrouping()
        XCTAssertTrue(view.toggleCheckbox(at: checkboxCenter(on: "open", in: view)))
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, "- [x] open\n\nlast")
        undo.undo()
        XCTAssertEqual(view.string, "- [ ] open\n\nlast")
    }

    // MARK: Toggle Checked (⌘L)

    private func toggleChecked(_ text: String, select range: NSRange) -> MarkdownTextView {
        let view = editor(text)
        view.setSelectedRange(range)
        view.toggleChecked(nil)
        return view
    }

    func testToggleCheckedFlipsTheCurrentLine() {
        XCTAssertEqual(toggleChecked("- [ ] a", select: NSRange(location: 7, length: 0)).string, "- [x] a")
        XCTAssertEqual(toggleChecked("- [x] a", select: NSRange(location: 7, length: 0)).string, "- [ ] a")
        XCTAssertEqual(toggleChecked("- [X] a", select: NSRange(location: 7, length: 0)).string, "- [ ] a")
        XCTAssertEqual(toggleChecked("  1. [ ] a", select: NSRange(location: 3, length: 0)).string, "  1. [x] a")
        XCTAssertEqual(toggleChecked("> - [ ] a", select: NSRange(location: 9, length: 0)).string, "> - [x] a")
    }

    func testToggleCheckedKeepsTheCaret() {
        let view = toggleChecked("- [ ] abc", select: NSRange(location: 8, length: 0))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 8, length: 0))
    }

    func testToggleCheckedMakesOtherLinesTasks() {
        // Like Obsidian: a line that isn't a task becomes one, keeping its list marker.
        let text = "plain\n- bullet\n3. number\n> quoted\n\n  indented"
        let view = toggleChecked(text, select: NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(view.string, "- [ ] plain\n- [ ] bullet\n3. [ ] number\n> - [ ] quoted\n\n  - [ ] indented")
    }

    func testToggleCheckedOnAMixedSelectionChecksAll() {
        let text = "- [x] a\n- [ ] b\n- [x] c"
        let view = toggleChecked(text, select: NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(view.string, "- [x] a\n- [x] b\n- [x] c")
        view.toggleChecked(nil)
        XCTAssertEqual(view.string, "- [ ] a\n- [ ] b\n- [ ] c")
    }

    func testToggleCheckedIsUndoable() throws {
        let view = editor("- [ ] a")
        let undo = try XCTUnwrap(view.undoManager)
        undo.beginUndoGrouping()
        view.toggleChecked(nil)
        undo.endUndoGrouping()
        XCTAssertEqual(view.string, "- [x] a")
        undo.undo()
        XCTAssertEqual(view.string, "- [ ] a")
    }
}
