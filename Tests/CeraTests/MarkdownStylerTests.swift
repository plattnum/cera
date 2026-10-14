import AppKit
import XCTest
@testable import Cera

final class MarkdownStylerTests: XCTestCase {
    private let theme = Theme.midnight

    /// Styles `source` with the insertion point at `caret` and returns the storage for inspection.
    private func style(_ source: String, caret: Int) -> NSTextStorage {
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: theme).style(storage, caret: caret)
        return storage
    }

    private func font(in storage: NSTextStorage, at index: Int) -> NSFont? {
        storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func color(in storage: NSTextStorage, at index: Int) -> NSColor? {
        storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    func testHeadingUsesThemeHeadingFont() {
        let storage = style("# Title\n\nbody", caret: 12)
        XCTAssertEqual(font(in: storage, at: 3), theme.headings[0].font)
        XCTAssertEqual(color(in: storage, at: 3), theme.headings[0].color)
    }

    func testMarkersHiddenOnInactiveLine() {
        // The caret is on the last line, so the bold markers on line one must be hidden.
        let storage = style("a **b** c\n\nlast", caret: 15)
        XCTAssertEqual(color(in: storage, at: 2), .clear)
        XCTAssertLessThan(font(in: storage, at: 2)?.pointSize ?? 99, 1)
    }

    func testMarkersVisibleOnActiveLine() {
        let storage = style("a **b** c", caret: 4)
        XCTAssertEqual(color(in: storage, at: 2), theme.marker)
        XCTAssertEqual(font(in: storage, at: 2)?.pointSize, theme.bodyFont.pointSize)
    }

    func testBoldContentIsBold() {
        let storage = style("a **b** c", caret: 0)
        let bold = font(in: storage, at: 4)
        XCTAssertTrue(bold?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    func testMarkersInsideCodeBlockAreNotStyled() {
        // The `**` in the fence is code, not emphasis, so it stays in the code font.
        let source = "```\n**not bold**\n```"
        let storage = style(source, caret: 0)
        let inside = (source as NSString).range(of: "**not").location
        XCTAssertEqual(font(in: storage, at: inside), theme.codeFont)
        XCTAssertEqual(color(in: storage, at: inside), theme.codeText)
    }

    func testInactiveBulletIsDrawnByLayoutManager() {
        let storage = style("- item\n\nlast", caret: 10)
        XCTAssertEqual(storage.attribute(.listBullet, at: 0, effectiveRange: nil) as? String, "•")
    }

    func testActiveBulletShowsSourceMarker() {
        let storage = style("- item", caret: 3)
        XCTAssertNil(storage.attribute(.listBullet, at: 0, effectiveRange: nil))
        XCTAssertEqual(color(in: storage, at: 0), theme.marker)
    }

    func testStorageTextIsNeverChanged() {
        let source = "# Hi **there** `code` [link](https://a.b)\n- item\n1. one\n> quote\n---\n<https://x.y>"
        let storage = style(source, caret: 3)
        XCTAssertEqual(storage.string, source)
    }

    // MARK: - Parser-based features

    func testSetextHeadingHidesUnderline() {
        let source = "Title\n=====\n\nbody"
        let storage = style(source, caret: (source as NSString).length)
        XCTAssertEqual(font(in: storage, at: 0), theme.headings[0].font)
        XCTAssertEqual(color(in: storage, at: 6), .clear) // the "=" underline
    }

    func testTableRowsAreLaidOutAsGrid() {
        let source = "| a | b |\n|---|---|\n| 1 | 2 |\n\nlast"
        let storage = style(source, caret: (source as NSString).length)
        XCTAssertNotNil(storage.attribute(.tableRow, at: 2, effectiveRange: nil) as? TableRowInfo)
        XCTAssertNotNil(storage.attribute(.tableRow, at: 22, effectiveRange: nil) as? TableRowInfo)
        // The pipes are hidden, and the space before the second cell carries the column offset.
        XCTAssertEqual(color(in: storage, at: 0), .clear)
        let kern = storage.attribute(.kern, at: 25, effectiveRange: nil) as? CGFloat ?? 0
        XCTAssertGreaterThan(kern, 0)
    }

    func testTableRowBeingEditedShowsSource() {
        let source = "| a | b |\n|---|---|\n| 1 | 2 |"
        let storage = style(source, caret: 22)
        XCTAssertNil(storage.attribute(.tableRow, at: 22, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.tableRow, at: 2, effectiveRange: nil))
    }

    func testNestedListBulletsChangeShape() {
        let source = "- one\n  - two\n\nlast"
        let storage = style(source, caret: (source as NSString).length)
        XCTAssertEqual(storage.attribute(.listBullet, at: 0, effectiveRange: nil) as? String, "•")
        XCTAssertEqual(storage.attribute(.listBullet, at: 6, effectiveRange: nil) as? String, "◦")
    }

    func testOrderedListUsesStartNumber() {
        let source = "3. three\n4. four\n\nlast"
        let storage = style(source, caret: (source as NSString).length)
        XCTAssertEqual(storage.attribute(.listBullet, at: 0, effectiveRange: nil) as? String, "3.")
        XCTAssertEqual(storage.attribute(.listBullet, at: 9, effectiveRange: nil) as? String, "4.")
    }

    func testLocalImageParagraphIsDrawnAsImage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = NSImage(size: NSSize(width: 100, height: 50), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
            .representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("pic.png"))

        let source = "![pic](pic.png)\n\nlast"
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: theme).style(storage, caret: (source as NSString).length, baseURL: folder)
        let block = try XCTUnwrap(storage.attribute(.imageBlock, at: 0, effectiveRange: nil) as? ImageBlock)
        XCTAssertEqual(block.size.width, 100, accuracy: 1)
    }

    func testMissingImageFallsBackToAltText() {
        let source = "![alt text](does-not-exist.png)\n\nlast"
        let storage = style(source, caret: (source as NSString).length)
        XCTAssertNil(storage.attribute(.imageBlock, at: 0, effectiveRange: nil))
        XCTAssertEqual(color(in: storage, at: 2), theme.link) // "alt text"
        XCTAssertEqual(color(in: storage, at: 0), .clear)     // "!["
    }

    func testEmphasisInsideCodeSpanIsNotStyled() {
        let source = "`**not bold**` x"
        let storage = style(source, caret: (source as NSString).length + 10)
        XCTAssertEqual(font(in: storage, at: 3), theme.codeFont)
    }
}
