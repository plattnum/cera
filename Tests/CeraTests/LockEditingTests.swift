import AppKit
import XCTest
@testable import Cera

/// Lock Editing: a locked window shows every line rendered and refuses edits, except ticking task boxes.
final class LockEditingStylingTests: XCTestCase {
    private static let document = "# Title\n\nSome **bold** and a [link](https://example.com).\n\n- [ ] task\n\nlast"

    private func settings(locked: Bool) -> LiveStyler.Settings {
        LiveStyler.Settings(theme: .midnight, baseURL: nil, availableWidth: 700, isLocked: locked)
    }

    /// The document styled with no line being edited, so no line shows its markers.
    private func styledWithNoActiveLine(_ text: String) -> NSAttributedString {
        let storage = NSTextStorage(string: text)
        MarkdownStyler(theme: .midnight).style(storage, caret: -1, availableWidth: 700, regionLength: .max)
        return storage
    }

    private func caret(at needle: String, in text: String) -> Int {
        (text as NSString).range(of: needle).location
    }

    func testLockedShowsNoMarkersOnTheCaretsLine() {
        let text = Self.document
        let storage = NSTextStorage(string: text)
        LiveStyler(storage: storage, settings: settings(locked: true)).restyleAll(caret: caret(at: "bold", in: text))
        XCTAssertTrue(storage.isEqual(to: styledWithNoActiveLine(text)))

        let unlocked = NSTextStorage(string: text)
        LiveStyler(storage: unlocked, settings: settings(locked: false)).restyleAll(caret: caret(at: "bold", in: text))
        XCTAssertFalse(unlocked.isEqual(to: storage), "unlocked, the caret's line shows its markers")
    }

    func testMovingTheCaretWhileLockedChangesNothing() {
        let text = Self.document
        let storage = NSTextStorage(string: text)
        let styler = LiveStyler(storage: storage, settings: settings(locked: true))
        styler.restyleAll(caret: 0)
        let before = NSAttributedString(attributedString: storage)
        let bold = caret(at: "bold", in: text)
        styler.caretMoved(fromLineAt: 0, toLineAt: (text as NSString).lineRange(for: NSRange(location: bold, length: 0)).location,
                          caret: bold)
        XCTAssertTrue(storage.isEqual(to: before))
    }

    func testTickingABoxWhileLockedKeepsItsLineRendered() {
        let text = Self.document
        let storage = NSTextStorage(string: text)
        let styler = LiveStyler(storage: storage, settings: settings(locked: true))
        let box = caret(at: "[ ]", in: text) + 1
        styler.restyleAll(caret: box)
        storage.replaceCharacters(in: NSRange(location: box, length: 1), with: "x")
        styler.textChanged(editedRange: NSRange(location: box, length: 1), delta: 0, caret: box, previousLine: nil)
        XCTAssertTrue(storage.isEqual(to: styledWithNoActiveLine(storage.string)))
    }
}

/// A locked editor in a window, as in the app.
@MainActor
final class LockEditingEditorTests: XCTestCase {
    private var window: NSWindow!
    private var textView: MarkdownTextView!
    private var coordinator: MarkdownEditor.Coordinator!
    private let undo = UndoManager()
    private var refused = 0

    override func tearDown() async throws {
        window?.close()
    }

    /// An editor showing `text`, styled by its coordinator, with the caret at the end.
    private func makeEditor(_ text: String, locked: Bool = true) {
        var editor = MarkdownEditor(text: .constant(text), theme: .midnight, isLocked: locked, undoManager: undo)
        editor.onRefusedEdit = { [weak self] in self?.refused += 1 }
        coordinator = editor.makeCoordinator()
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        textView.delegate = coordinator
        textView.textStorage?.delegate = coordinator
        coordinator.textView = textView
        self.textView = textView
        textView.string = text
        textView.isLocked = locked
        textView.onRefusedEdit = editor.onRefusedEdit
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        coordinator.restyle()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    }

    private func setLocked(_ locked: Bool) {
        coordinator.parent.isLocked = locked
        textView.isLocked = locked
        coordinator.restyle()
    }

    private func point(atCharacter index: Int) -> NSPoint {
        let layoutManager = textView.layoutManager!
        let container = textView.textContainer!
        layoutManager.ensureLayout(for: container)
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        return NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y)
    }

    func testTypingDeletingAndReturnAreRefused() {
        let text = "Some text\n\nlast"
        makeEditor(text)
        XCTAssertFalse(textView.isEditable)
        textView.insertText("a", replacementRange: textView.selectedRange())
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        textView.doCommand(by: #selector(NSResponder.insertTab(_:)))
        textView.doCommand(by: #selector(NSResponder.yank(_:)))
        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(refused, 5)
        XCTAssertFalse(undo.canUndo)
    }

    func testMovingAndSelectingStillWork() {
        makeEditor("Some text\n\nlast")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))
        textView.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:)))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 2))
        XCTAssertEqual(refused, 0)
    }

    func testKeyCommandsThatEditAreTold() {
        for command in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.deleteWordBackward(_:)),
                        #selector(NSResponder.transpose(_:)), #selector(NSResponder.yank(_:)),
                        #selector(NSResponder.uppercaseWord(_:)), #selector(NSResponder.insertBacktab(_:))] {
            XCTAssertTrue(MarkdownTextView.editsText(command), NSStringFromSelector(command))
        }
        for command in [#selector(NSResponder.moveDown(_:)), #selector(NSResponder.scrollPageDown(_:)),
                        #selector(NSResponder.selectAll(_:)), #selector(NSResponder.cancelOperation(_:))] {
            XCTAssertFalse(MarkdownTextView.editsText(command), NSStringFromSelector(command))
        }
    }

    func testFormatCommandsChangeNothing() {
        let text = "Some text\n\n- item\n\nlast"
        makeEditor(text)
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        textView.toggleBold(nil)
        textView.heading1(nil)
        textView.toggleBulletedList(nil)
        textView.toggleChecked(nil)
        textView.insertTable(nil)
        textView.insertLink(nil)
        XCTAssertEqual(textView.string, text)
    }

    func testPasteIsRefused() {
        let text = "Some text"
        makeEditor(text)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cera.tests.lock"))
        pasteboard.clearContents()
        pasteboard.setString("pasted", forType: .string)
        textView.pastePasteboard = pasteboard
        textView.paste(nil)
        XCTAssertEqual(textView.string, text)
        XCTAssertEqual(refused, 1)
    }

    func testTaskBoxesStillTick() {
        makeEditor("- [ ] open\n\nlast")
        let layoutManager = textView.layoutManager as! MarkdownLayoutManager
        let box = layoutManager.checkboxRect(at: 0)
        let center = NSPoint(x: box.midX + textView.textContainerOrigin.x, y: box.midY + textView.textContainerOrigin.y)
        XCTAssertTrue(textView.toggleCheckbox(at: center))
        XCTAssertEqual(textView.string, "- [x] open\n\nlast")
        XCTAssertFalse(textView.isEditable, "still locked afterwards")
    }

    func testABoxOnTheCaretsLineIsDrawn() {
        // Unlocked, the caret's line shows its Markdown and has no box; locked, every line is rendered.
        makeEditor("- [ ] open\n\nlast")
        textView.setSelectedRange(NSRange(location: 8, length: 0))
        coordinator.restyle()
        XCTAssertEqual(textView.textStorage?.attribute(.listBullet, at: 0, effectiveRange: nil) as? String, "☐")
    }

    func testLockingHidesTheFormatBarAndUnlockingEditsAgain() throws {
        makeEditor("Some text\n\nlast", locked: false)
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        XCTAssertEqual(textView.formatBar?.isHidden, false)
        setLocked(true)
        XCTAssertEqual(textView.formatBar?.isHidden, true)
        textView.setSelectedRange(NSRange(location: 0, length: 9))
        XCTAssertEqual(textView.formatBar?.isHidden, true, "selecting while locked doesn't bring it back")

        setLocked(false)
        XCTAssertTrue(textView.isEditable)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("New ", replacementRange: textView.selectedRange())
        XCTAssertEqual(textView.string, "New Some text\n\nlast")
        XCTAssertEqual(refused, 0)
    }

    func testUndoAndRedoStopAtALockedEditorAndKeepTheirSteps() {
        let undoCommand = #selector(MarkdownTextView.undo(_:)), redoCommand = #selector(MarkdownTextView.redo(_:))
        makeEditor("Some text", locked: false)
        XCTAssertFalse(textView.responds(to: undoCommand), "unlocked, Undo goes on to the window")
        textView.insertText("!", replacementRange: textView.selectedRange())
        setLocked(true)

        for command in [undoCommand, redoCommand] {
            let item = NSMenuItem(title: "", action: command, keyEquivalent: "")
            XCTAssertFalse(textView.validateUserInterfaceItem(item), "disabled while locked")
            XCTAssertTrue(textView.tryToPerform(command, with: nil), "handled by the editor, not the window")
        }
        XCTAssertEqual(textView.string, "Some text!")
        XCTAssertEqual(refused, 2)

        setLocked(false)
        XCTAssertTrue(undo.canUndo, "the step is still there")
        undo.undo()
        XCTAssertEqual(textView.string, "Some text")
    }

    func testAPlainClickOnALinkFollowsIt() throws {
        // An in-page link, so following it scrolls rather than opening another app.
        let filler = Array(repeating: "Filler paragraph.", count: 80).joined(separator: "\n\n")
        let text = "Go to [the end](#the-end) now.\n\n\(filler)\n\n## The End\n\nlast"
        makeEditor(text)
        textView.scroll(.zero)
        let target = point(atCharacter: (text as NSString).range(of: "the end").location)
        let location = textView.convert(target, to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                                    windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                    clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 0,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                  clickCount: 1, pressure: 0))
        // The text view follows the mouse until it is released.
        NSApp.postEvent(up, atStart: true)
        textView.mouseDown(with: down)
        XCTAssertGreaterThan(textView.visibleRect.minY, 100, "scrolled to the heading")
    }
}

@MainActor
final class LockRequestTests: XCTestCase {
    func testReadsTheFileFromAnOpenLockedURL() throws {
        let url = try XCTUnwrap(URL(string: "cera://open-locked?path=%2FUsers%2Fme%2Fmy%20notes%20%26%20%C3%A9t%C3%A9%2B.md"))
        XCTAssertEqual(LockRequests.file(in: url)?.path, "/Users/me/my notes & été+.md")
    }

    func testIgnoresOtherURLs() throws {
        for string in ["cera://open?path=%2Fa.md", "https://open-locked?path=%2Fa.md", "cera://open-locked?file=%2Fa.md",
                       "cera://open-locked?path=a.md", "cera://open-locked"] {
            XCTAssertNil(LockRequests.file(in: try XCTUnwrap(URL(string: string))), string)
        }
    }

    func testARequestIsTakenOnceHoweverThePathIsWritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("notes.md")
        try Data("# Notes\n".utf8).write(to: file)
        let link = folder.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertFalse(LockRequests.take(file))
        LockRequests.request(link)
        XCTAssertFalse(LockRequests.take(folder.appendingPathComponent("other.md")))
        XCTAssertTrue(LockRequests.take(URL(fileURLWithPath: folder.path + "/sub/../notes.md")))
        XCTAssertFalse(LockRequests.take(file), "used up")
        XCTAssertFalse(LockRequests.take(nil))
    }
}
