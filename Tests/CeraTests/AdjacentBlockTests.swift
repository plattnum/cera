import AppKit
import XCTest
@testable import Cera

/// Blocks that directly follow another block, with no blank line between them: the block gap goes above
/// them as spacing before, and what is drawn for them (table grid, code panel, quote bar) starts below it.
final class AdjacentBlockTests: XCTestCase {
    private var window: NSWindow!

    override func tearDown() {
        window?.close()
    }

    /// A styled, laid-out editor in a window, as in the app, with the caret on the last line.
    private func editor(_ text: String) -> MarkdownTextView {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        textView.apply(.ivory)
        textView.string = text
        let caret = (text as NSString).length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        let width = textView.textContainer!.size.width - 2 * textView.textContainer!.lineFragmentPadding
        MarkdownStyler(theme: .ivory).style(textView.textStorage!, caret: caret, availableWidth: width)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        return textView
    }

    private func layoutManager(_ view: MarkdownTextView) -> MarkdownLayoutManager {
        view.layoutManager as! MarkdownLayoutManager
    }

    private func location(of needle: String, in view: MarkdownTextView) -> Int {
        (view.string as NSString).range(of: needle).location
    }

    /// The bottom of the line holding `needle`, in container coordinates.
    private func bottom(of needle: String, in view: MarkdownTextView) -> CGFloat {
        let manager = layoutManager(view)
        return manager.lineFragmentRect(forGlyphAt: manager.glyphIndexForCharacter(at: location(of: needle, in: view)),
                                        effectiveRange: nil).maxY
    }

    // MARK: Drawing below the gap

    func testTableGridStartsBelowTheGap() {
        let view = editor("Intro\n| A | B |\n|---|---|\n| 1 | 2 |\n\nlast")
        let manager = layoutManager(view)
        let row = manager.lineRect(forGlyphAt: manager.glyphIndexForCharacter(at: location(of: "| A", in: view)))
        XCTAssertEqual(row.minY, bottom(of: "Intro", in: view) + view.theme.blockSpacing, accuracy: 0.5)
        XCTAssertEqual(row.height, view.theme.lineHeight + 10, accuracy: 0.5, "the header row is its own height, gap left out")
    }

    func testCodePanelStartsBelowTheGap() throws {
        let view = editor("Intro\n```swift\nlet a = 1\n```\n\nlast")
        let panel = try XCTUnwrap(layoutManager(view).codePanel(at: location(of: "let a", in: view))).rect
        XCTAssertEqual(panel.minY, bottom(of: "Intro", in: view) + view.theme.blockSpacing, accuracy: 0.5)
    }

    func testQuoteBarStartsBelowTheGap() {
        let view = editor("Intro\n> A quote\n\nlast")
        let quote = NSRange(location: location(of: "> A quote", in: view), length: 9)
        let bar = layoutManager(view).unionOfLines(for: quote)
        XCTAssertEqual(bar.minY, bottom(of: "Intro", in: view) + view.theme.blockSpacing, accuracy: 0.5)
    }

    func testFirstBlockOfTheDocumentIsUnchanged() {
        let view = editor("| A | B |\n|---|---|\n| 1 | 2 |\n\nlast")
        let manager = layoutManager(view)
        XCTAssertEqual(manager.lineRect(forGlyphAt: 0), manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil))
    }

    // MARK: A table that interrupts a paragraph

    private func row(at needle: String, in storage: NSTextStorage) -> TableRowInfo? {
        storage.attribute(.tableRow, at: (storage.string as NSString).range(of: needle).location, effectiveRange: nil) as? TableRowInfo
    }

    func testTableRightAfterAParagraphKeepsTheParagraph() throws {
        // The parser reports the table from the paragraph's first line.
        let source = "One\ntwo:\n| A | B |\n|---|---|\n| 1 | 2 |\n\nlast"
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: .ivory).style(storage, caret: (source as NSString).length)
        XCTAssertNil(row(at: "One", in: storage))
        XCTAssertNil(row(at: "two:", in: storage))
        XCTAssertEqual(try XCTUnwrap(row(at: "| A", in: storage)).isHeader, true)
        XCTAssertEqual(try XCTUnwrap(row(at: "| 1", in: storage)).isHeader, false)
        XCTAssertNil(row(at: "|---", in: storage), "the delimiter is not a row")
    }

    func testParagraphATableInterruptsIsStillAParagraph() throws {
        // It gets the gap under the heading, and its own formatting.
        let source = "## Heading\nSome **bold** text:\n| A | B |\n|---|---|\n| 1 | 2 |\n\nlast"
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: .ivory).style(storage, caret: (source as NSString).length)
        let paragraph = (source as NSString).range(of: "Some").location
        let style = try XCTUnwrap(storage.attribute(.paragraphStyle, at: paragraph, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.paragraphSpacingBefore, Theme.ivory.blockSpacing)
        let bold = try XCTUnwrap(storage.attribute(.font, at: (source as NSString).range(of: "bold").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertNil(row(at: "Some", in: storage))
    }

    func testTableRightAfterAListItemsText() throws {
        let source = "- Item:\n  | A | B |\n  |---|---|\n  | 1 | 2 |\n\nlast"
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: .ivory).style(storage, caret: (source as NSString).length)
        XCTAssertNil(row(at: "Item:", in: storage))
        XCTAssertEqual(try XCTUnwrap(row(at: "| A", in: storage)).isHeader, true)
        XCTAssertEqual(try XCTUnwrap(row(at: "| 1", in: storage)).isHeader, false)
    }

    func testTableRightAfterAParagraphGetsTheGap() {
        let view = editor("Intro:\n| A | B |\n|---|---|\n| 1 | 2 |\n\nlast")
        let manager = layoutManager(view)
        let row = manager.lineRect(forGlyphAt: manager.glyphIndexForCharacter(at: location(of: "| A", in: view)))
        XCTAssertEqual(row.minY, bottom(of: "Intro", in: view) + view.theme.blockSpacing, accuracy: 0.5)
    }
}
