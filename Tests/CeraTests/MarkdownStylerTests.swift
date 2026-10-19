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

    /// A table with `columns` columns of long cells, too wide for the default 760-point column from 4 up.
    private func wideTable(columns: Int) -> String {
        let cells = (0..<columns).map { "column number \($0) heading" }
        return "| " + cells.joined(separator: " | ") + " |\n|" + String(repeating: "---|", count: columns)
            + "\n| " + cells.joined(separator: " | ") + " |\n"
    }

    private func tableBlock(in storage: NSTextStorage, at index: Int) -> (block: TableBlock, range: NSRange)? {
        var range = NSRange()
        guard let block = storage.attribute(.tableBlock, at: index, longestEffectiveRange: &range,
                                            in: NSRange(location: 0, length: storage.length)) as? TableBlock
        else { return nil }
        return (block, range)
    }

    func testWideTableOverflowsAtItsNaturalWidth() throws {
        let source = wideTable(columns: 8) + "\nlast"
        let storage = style(source, caret: (source as NSString).length)
        let table = try XCTUnwrap(tableBlock(in: storage, at: 2))
        XCTAssertTrue(table.block.overflows)
        let row = try XCTUnwrap(storage.attribute(.tableRow, at: 2, effectiveRange: nil) as? TableRowInfo)
        XCTAssertGreaterThan(try XCTUnwrap(row.edges.last), 760, "the columns keep their natural width")
    }

    func testNarrowTableFillsTheColumnAndDoesNotOverflow() throws {
        let source = "| a | b |\n|---|---|\n| 1 | 2 |\n\nlast"
        let storage = style(source, caret: (source as NSString).length)
        XCTAssertFalse(try XCTUnwrap(tableBlock(in: storage, at: 2)).block.overflows)
        let row = try XCTUnwrap(storage.attribute(.tableRow, at: 2, effectiveRange: nil) as? TableRowInfo)
        XCTAssertEqual(try XCTUnwrap(row.edges.last), 760, accuracy: 0.5)
    }

    func testTableBlockCoversExactlyTheTablesLines() throws {
        let table = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let source = "intro\n\n" + table + "\nlast"
        let storage = style(source, caret: (source as NSString).length)
        let range = try XCTUnwrap(tableBlock(in: storage, at: 9)).range
        XCTAssertEqual(range, NSRange(location: 7, length: (table as NSString).length))
    }

    func testTwoTablesAreSeparateBlocks() throws {
        let first = "| a | b |\n|---|---|\n| 1 | 2 |\n"
        let source = first + "\n| c | d |\n|---|---|\n| 3 | 4 |\n\nlast"
        let storage = style(source, caret: (source as NSString).length)
        let one = try XCTUnwrap(tableBlock(in: storage, at: 2)).range
        let two = try XCTUnwrap(tableBlock(in: storage, at: (first as NSString).length + 3)).range
        XCTAssertEqual(NSMaxRange(one), (first as NSString).length)
        XCTAssertGreaterThan(two.location, NSMaxRange(one))
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

    /// Writes a 100×50 PNG to a fresh folder as `pic.png`, styles `source` against it,
    /// and returns the image block drawn for the first line.
    private func imageBlock(for source: String, availableWidth: CGFloat = 760) throws -> ImageBlock {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = NSImage(size: NSSize(width: 100, height: 50), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
            .representation(using: .png, properties: [:]))
        try png.write(to: folder.appendingPathComponent("pic.png"))

        let storage = NSTextStorage(string: source + "\n\nlast")
        MarkdownStyler(theme: theme).style(storage, caret: storage.length, baseURL: folder,
                                           availableWidth: availableWidth)
        return try XCTUnwrap(storage.attribute(.imageBlock, at: 0, effectiveRange: nil) as? ImageBlock)
    }

    func testImageWidthAfterPipeShrinksImage() throws {
        let block = try imageBlock(for: "![pic|50](pic.png)")
        XCTAssertEqual(block.size, NSSize(width: 50, height: 25))
    }

    func testImageWidthAfterPipeEnlargesImage() throws {
        let block = try imageBlock(for: "![pic|300](pic.png)")
        XCTAssertEqual(block.size, NSSize(width: 300, height: 150))
    }

    func testImageWidthAfterPipeStaysWithinColumn() throws {
        let block = try imageBlock(for: "![pic|2000](pic.png)", availableWidth: 400)
        XCTAssertEqual(block.size, NSSize(width: 400, height: 200))
    }

    func testImageWidthAndHeightAfterPipeFitImageInsideBoxKeepingShape() throws {
        let block = try imageBlock(for: "![pic|60x60](pic.png)")
        XCTAssertEqual(block.size, NSSize(width: 60, height: 30))
    }

    func testImagePipeWithoutNumberKeepsNaturalSize() throws {
        let block = try imageBlock(for: "![this|that](pic.png)")
        XCTAssertEqual(block.size, NSSize(width: 100, height: 50))
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

    // MARK: - Nested emphasis, escapes, definitions

    func testBoldItalicHidesAllSixAsterisks() {
        let source = "a ***both*** b\n\nlast"
        let storage = style(source, caret: (source as NSString).length)
        for index in [2, 3, 4, 9, 10, 11] {
            XCTAssertEqual(color(in: storage, at: index), .clear, "asterisk at \(index)")
        }
        let traits = font(in: storage, at: 5)?.fontDescriptor.symbolicTraits ?? []
        XCTAssertTrue(traits.contains(.bold) && traits.contains(.italic))
    }

    func testEscapeBackslashesHide() {
        let source = "a \\*not italic\\* b\n\nlast"
        let storage = style(source, caret: (source as NSString).length)
        XCTAssertEqual(color(in: storage, at: 2), .clear)   // the backslash
        XCTAssertNotEqual(color(in: storage, at: 3), .clear) // the asterisk stays
    }

    func testDefinitionLinesAreDimmed() {
        let source = "see [x][d]\n\n[d]: https://example.com\n\nlast"
        let storage = style(source, caret: (source as NSString).length)
        let definition = (source as NSString).range(of: "[d]:").location
        XCTAssertEqual(color(in: storage, at: definition), theme.marker)
    }
}
