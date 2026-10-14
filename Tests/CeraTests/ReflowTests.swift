import AppKit
import XCTest
@testable import Cera

/// Hard-wrapped paragraphs flow as one paragraph, as Markdown reads them.
final class ReflowTests: XCTestCase {

    private func styled(_ text: String, caret: Int) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler(theme: .midnight, joinsHardWrappedLines: true).style(storage, caret: caret)
        return storage
    }

    func testOffByDefaultLikeTypora() {
        let text = "one two\nthree four\n\nlast"
        let storage = NSTextStorage(string: text)
        MarkdownStyler(theme: .midnight).style(storage, caret: (text as NSString).length)
        XCTAssertNil(storage.attribute(.softBreak, at: 7, effectiveRange: nil))
    }

    private func isSoftBreak(_ storage: NSTextStorage, at index: Int) -> Bool {
        storage.attribute(.softBreak, at: index, effectiveRange: nil) != nil
    }

    func testLineBreaksInsideAParagraphAreSoft() {
        let text = "one two\nthree four\nfive\n\nlast"
        let storage = styled(text, caret: (text as NSString).length)
        XCTAssertTrue(isSoftBreak(storage, at: 7))   // after "one two"
        XCTAssertTrue(isSoftBreak(storage, at: 18))  // after "three four"
        XCTAssertFalse(isSoftBreak(storage, at: 23)) // the paragraph's end
    }

    func testParagraphBeingEditedKeepsItsLineBreaks() {
        let text = "one two\nthree four\n\nlast"
        let storage = styled(text, caret: 9)
        XCTAssertFalse(isSoftBreak(storage, at: 7))
    }

    func testHardBreaksStayLineBreaks() {
        let text = "two spaces  \nbackslash\\\nend\n\nlast"
        let storage = styled(text, caret: (text as NSString).length)
        XCTAssertFalse(isSoftBreak(storage, at: 12))
        XCTAssertFalse(isSoftBreak(storage, at: 23))
    }

    func testCodeAndListLinesAreNotJoinedAcrossBlocks() {
        let text = "```\na\nb\n```\n\n- one\n- two\n\nlast"
        let storage = styled(text, caret: (text as NSString).length)
        XCTAssertFalse(isSoftBreak(storage, at: 5))  // inside code
        XCTAssertFalse(isSoftBreak(storage, at: 18)) // between list items
    }

    func testWrappedListItemFlows() {
        let text = "- one two\n  three four\n- next\n\nlast"
        let storage = styled(text, caret: (text as NSString).length)
        XCTAssertTrue(isSoftBreak(storage, at: 9))
    }

    func testHardWrappedParagraphLaysOutAsOneLine() throws {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        defer { window.close() }
        let text = "short one\nshort two\nshort three\n\nlast"
        textView.string = text
        MarkdownStyler(theme: .midnight, joinsHardWrappedLines: true).style(try XCTUnwrap(textView.textStorage), caret: (text as NSString).length)

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        layoutManager.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        let paragraph = layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: 31), actualCharacterRange: nil)
        var fragments = 0
        layoutManager.enumerateLineFragments(forGlyphRange: paragraph) { _, _, _, _, _ in fragments += 1 }
        XCTAssertEqual(fragments, 1, "three short source lines flow onto one line")

        // The breaks take a space's width, so the words stay apart.
        let used = layoutManager.boundingRect(forGlyphRange: paragraph, in: try XCTUnwrap(textView.textContainer)).width
        let joined = NSAttributedString(string: "short one short two short three",
                                        attributes: [.font: Theme.midnight.bodyFont]).size().width
        XCTAssertEqual(used, joined, accuracy: 3)
    }
}
