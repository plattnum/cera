import AppKit
import XCTest
@testable import Cera

/// The Markdown source view: the same text, shown as source instead of rendered.
final class SourceViewTests: XCTestCase {
    private static let document = """
    # Title

    Intro with **bold**, *italic*, `code`, and a [link](https://example.com).

    - one
      - nested
    - [x] done

    > quote

    | A | B |
    |---|---|
    | 1 | 2 |

    ```swift
    let a = 1
    ```

    ![picture](missing.png)

    ---

    Last line.
    """

    private static let renderingKeys: [NSAttributedString.Key] = [
        .listBullet, .codeBlock, .codeLanguage, .quoteBar, .imageBlock, .tableRow, .tableBlock, .horizontalRule,
        .headingUnderline, .inlineCode, .softBreak, .uppercase, .linkTarget, .kern
    ]

    private let theme = Theme.midnight

    private func settings(source: Bool) -> LiveStyler.Settings {
        LiveStyler.Settings(theme: theme, baseURL: nil, availableWidth: 700, showsSource: source)
    }

    private func assertIsSource(_ storage: NSTextStorage, file: StaticString = #filePath, line: UInt = #line) {
        let all = NSRange(location: 0, length: storage.length)
        for key in Self.renderingKeys {
            storage.enumerateAttribute(key, in: all) { value, range, _ in
                if value != nil { XCTFail("\(key.rawValue) at \(range)", file: file, line: line) }
            }
        }
        storage.enumerateAttribute(.font, in: all) { value, range, _ in
            XCTAssertEqual(value as? NSFont, theme.codeFont, "font at \(range)", file: file, line: line)
        }
    }

    func testSourceShowsEveryCharacterWithNoRendering() {
        let storage = NSTextStorage(string: Self.document)
        LiveStyler(storage: storage, settings: settings(source: true)).restyleAll(caret: 0)
        XCTAssertEqual(storage.string, Self.document, "the text never changes")
        assertIsSource(storage)
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            XCTAssertNotEqual(value as? NSColor, .clear, "nothing is hidden, at \(range)")
        }
    }

    func testSourceColorsTheMarkdownSyntax() throws {
        let storage = NSTextStorage(string: Self.document)
        LiveStyler(storage: storage, settings: settings(source: true)).restyleAll(caret: 0)
        let keyword = try XCTUnwrap(theme.syntax.color(for: .keyword))
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor, keyword, "the heading")
        let intro = (Self.document as NSString).range(of: "Intro").location
        XCTAssertEqual(storage.attribute(.foregroundColor, at: intro, effectiveRange: nil) as? NSColor, theme.text, "plain text")
    }

    func testSwitchingBackRendersAsBefore() {
        let rendered = NSTextStorage(string: Self.document)
        MarkdownStyler(theme: theme).style(rendered, caret: 0, availableWidth: 700, regionLength: .max)

        let storage = NSTextStorage(string: Self.document)
        let styler = LiveStyler(storage: storage, settings: settings(source: false))
        styler.restyleAll(caret: 0)
        styler.restyleAll(caret: 0, settings: settings(source: true))
        styler.restyleAll(caret: 0, settings: settings(source: false))
        XCTAssertTrue(storage.isEqual(to: rendered))
    }

    func testTypingInSourceKeepsItSource() {
        let storage = NSTextStorage(string: Self.document)
        let styler = LiveStyler(storage: storage, settings: settings(source: true))
        styler.restyleAll(caret: 0)
        let at = (Self.document as NSString).range(of: "Last line.").location
        storage.replaceCharacters(in: NSRange(location: at, length: 0), with: "**new** ")
        styler.textChanged(editedRange: NSRange(location: at, length: 8), delta: 8, caret: at + 8, previousLine: at)
        assertIsSource(storage)

        let fresh = NSTextStorage(string: storage.string)
        LiveStyler(storage: fresh, settings: settings(source: true)).restyleAll(caret: 0)
        XCTAssertTrue(storage.isEqual(to: fresh), "the same as styling the edited text afresh")
    }

    func testMovingTheCaretChangesNothing() {
        let storage = NSTextStorage(string: Self.document)
        let styler = LiveStyler(storage: storage, settings: settings(source: true))
        styler.restyleAll(caret: 0)
        let before = NSAttributedString(attributedString: storage)
        let bold = (Self.document as NSString).range(of: "**bold**").location
        styler.caretMoved(fromLineAt: 0, toLineAt: bold, caret: bold)
        XCTAssertTrue(storage.isEqual(to: before))
    }

    func testLongDocumentStylesInTheBackground() {
        let text = Array(repeating: Self.document, count: 400).joined(separator: "\n\n")
        let storage = NSTextStorage(string: text)
        let styler = LiveStyler(storage: storage, settings: settings(source: true))
        styler.restyleAll(caret: 0)
        XCTAssertTrue(styler.isStylingInBackground)
        styler.finishBackgroundStyling(caret: 0)
        assertIsSource(storage)
    }
}

/// The source view in a real editor.
@MainActor
final class SourceViewEditorTests: XCTestCase {
    private var window: NSWindow!
    private var textView: MarkdownTextView!
    private var coordinator: MarkdownEditor.Coordinator!
    private let undo = UndoManager()

    private func makeEditor(showsSource: Bool, text: String) {
        let editor = MarkdownEditor(text: .constant(text), theme: .midnight, showsSource: showsSource, undoManager: undo)
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
        coordinator.restyle()
    }

    override func tearDown() async throws {
        window.close()
    }

    func testSwitchingViewsKeepsTextAndUndoAndTypesSource() throws {
        let text = "# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nSome **bold** text.\n"
        makeEditor(showsSource: false, text: text)
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        textView.insertText("x", replacementRange: textView.selectedRange())
        XCTAssertTrue(undo.canUndo)
        let edited = textView.string

        coordinator.parent.showsSource = true
        coordinator.restyle()
        XCTAssertEqual(textView.string, edited)
        XCTAssertEqual(textView.typingAttributes[.font] as? NSFont, Theme.midnight.codeFont, "typing is source too")
        XCTAssertNil(textView.textStorage?.attribute(.tableRow, at: 12, effectiveRange: nil))
        textView.updateTableScrollers()
        XCTAssertTrue(textView.tableScrollers.isEmpty)

        undo.undo()
        XCTAssertEqual(textView.string, text, "undo goes back to before the typing, not the view switch")
    }
}
