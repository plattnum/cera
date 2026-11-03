import AppKit
import XCTest
@testable import Cera

/// Selected text shows its highlight everywhere: over the panel of a code block and the box of
/// inline code as over a paragraph.
@MainActor
final class SelectionDrawingTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() {
        window?.close()
    }

    /// A styled, laid-out editor in a window, as in the app, with the caret at the end.
    private func editor(_ text: String, theme: Theme) -> MarkdownTextView {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        self.window = window
        textView.apply(theme)
        textView.string = text
        let caret = (text as NSString).length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        let width = textView.textContainer!.size.width - 2 * textView.textContainer!.lineFragmentPadding
        MarkdownStyler(theme: theme).style(textView.textStorage!, caret: caret, availableWidth: width)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        return textView
    }

    /// The color drawn in the middle of the character at `index`, with and without `needle` selected.
    /// The character is a space (`offset` into `needle`), so no glyph's ink gets in the way.
    private func colors(of needle: String, offset: Int, in view: MarkdownTextView) throws -> (selected: NSColor, unselected: NSColor) {
        let text = view.string as NSString
        let selection = text.range(of: needle)
        XCTAssertNotEqual(selection.location, NSNotFound, needle)
        XCTAssertEqual(text.character(at: selection.location + offset), 0x20, "\(needle): sample a space")
        let index = selection.location + offset

        let layoutManager = view.layoutManager!
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer!)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)

        func color() throws -> NSColor {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            let pixel = try XCTUnwrap(bitmap.colorAt(x: Int(rect.midX * scale), y: Int(rect.midY * scale)))
            return try XCTUnwrap(pixel.usingColorSpace(.sRGB))
        }
        view.setSelectedRange(NSRange(location: NSMaxRange(selection), length: 0))
        let unselected = try color()
        view.setSelectedRange(selection)
        XCTAssertEqual(view.selectedRange(), selection, "\(needle) can be selected")
        return (try color(), unselected)
    }

    private func components(_ color: NSColor) -> [CGFloat] {
        [color.redComponent, color.greenComponent, color.blueComponent]
    }

    private func assertSameColor(_ a: NSColor, _ b: NSColor, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in zip(components(a), components(b)) {
            XCTAssertEqual(x, y, accuracy: 0.01, message, file: file, line: line)
        }
    }

    private func assertDifferentColors(_ a: NSColor, _ b: NSColor, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let apart = zip(components(a), components(b)).contains { abs($0 - $1) > 0.03 }
        XCTAssertTrue(apart, "\(message): \(a) and \(b)", file: file, line: line)
    }

    private static let document = """
    # Notes

    Some plain text here.

    Call `the function` now.

    ```sh
    brew install cera
    cera notes.md
    ```

    > [!TIP]
    > A callout.

    More text.

    """

    func testSelectionShowsOverCodeAsOverAParagraph() throws {
        for theme in [Theme.midnight, .plain] {
            let view = editor(Self.document, theme: theme)
            let paragraph = try colors(of: "plain text", offset: 5, in: view)
            assertDifferentColors(paragraph.selected, paragraph.unselected, "\(theme.name): the paragraph's highlight shows")

            let code = try colors(of: "brew install", offset: 4, in: view)
            assertSameColor(code.selected, paragraph.selected, "\(theme.name): a selected line of code shows the highlight")
            assertDifferentColors(code.selected, code.unselected, "\(theme.name): a selected line of code looks selected")

            let inline = try colors(of: "the function", offset: 3, in: view)
            assertSameColor(inline.selected, paragraph.selected, "\(theme.name): selected inline code shows the highlight")
            assertDifferentColors(inline.selected, inline.unselected, "\(theme.name): selected inline code looks selected")
        }
    }

    func testCalloutHeaderStaysVisibleWhenSelected() throws {
        for theme in [Theme.midnight, .plain] {
            let view = editor(Self.document, theme: theme)
            let text = view.string as NSString
            let paragraph = try colors(of: "plain text", offset: 5, in: view)
            let callout = text.range(of: "> [!TIP]\n> A callout.")
            view.setSelectedRange(callout)

            // The header's icon and label are drawn where the hidden `[!TIP]` marker is.
            let layoutManager = view.layoutManager as! MarkdownLayoutManager
            let slot = layoutManager.calloutIconRect(atHeader: text.range(of: "[!TIP]").location)
            let header = NSRect(x: slot.minX, y: slot.minY, width: slot.width + CalloutStyle.iconGap + 40, height: slot.height)
                .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            var highlighted = 0, drawnOver = 0
            for x in Int(header.minX * scale)..<Int(header.maxX * scale) {
                for y in Int(header.minY * scale)..<Int(header.maxY * scale) {
                    guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    let apart = zip(components(pixel), components(paragraph.selected)).contains { abs($0 - $1) > 0.03 }
                    if apart { drawnOver += 1 } else { highlighted += 1 }
                }
            }
            XCTAssertGreaterThan(highlighted, 0, "\(theme.name): the header line is selected")
            XCTAssertGreaterThan(drawnOver, 50, "\(theme.name): the icon and label show over the highlight")
        }
    }
}
