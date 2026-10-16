import AppKit
import XCTest
@testable import Cera

final class ContextMenuTests: XCTestCase {
    private var window: NSWindow!
    private var textView: MarkdownTextView!

    override func setUp() {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        self.textView = textView
    }

    override func tearDown() {
        window.close()
    }

    /// The editor's right-click menu for a click on the character at `index`.
    private func menu(atCharacter index: Int) throws -> NSMenu {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: container)
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        let point = NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: textView.convert(point, to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        return try XCTUnwrap(textView.menu(for: event))
    }

    private func titles(in menu: NSMenu) -> [String] {
        menu.items.flatMap { [$0.title] + ($0.submenu.map(titles) ?? []) }
    }

    private func sizeItem(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        let submenu = try XCTUnwrap(menu.items.first { $0.title == "Image Size" }?.submenu)
        return try XCTUnwrap(submenu.items.first { $0.title.hasPrefix(title) })
    }

    // MARK: - Removed items

    func testMenuHasNoFontPanelsOrLayoutOrientation() throws {
        textView.string = "hello"
        let titles = titles(in: try menu(atCharacter: 1))
        XCTAssertTrue(titles.contains("Copy"), "the standard items stay")
        for removed in ["Font", "Show Fonts", "Show Colours", "Show Colors", "Layout Orientation", "Vertical"] {
            XCTAssertFalse(titles.contains(removed), "\(removed) should be gone")
        }
    }

    func testMenuHasNoDoubledOrDanglingSeparators() throws {
        textView.string = "hello"
        let items = try menu(atCharacter: 1).items
        XCTAssertFalse(items.first?.isSeparatorItem ?? true)
        XCTAssertFalse(items.last?.isSeparatorItem ?? true)
        for (above, below) in zip(items, items.dropFirst()) {
            XCTAssertFalse(above.isSeparatorItem && below.isSeparatorItem)
        }
    }

    func testVerticalLayoutIsRefused() {
        textView.setLayoutOrientation(.vertical)
        XCTAssertEqual(textView.layoutOrientation, .horizontal)
    }

    // MARK: - Image Size

    func testImageLineOffersSizes() throws {
        textView.string = "![pic](pic.png)\n\nlast"
        let menu = try menu(atCharacter: 3)
        XCTAssertEqual(menu.items.first?.title, "Image Size")
        let submenu = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertEqual(submenu.items.map(\.title), ["Small", "Medium", "Large", "Original Size"])
    }

    func testTextLineOffersNoSizes() throws {
        textView.string = "just words\n\n![pic](pic.png)"
        XCTAssertFalse(titles(in: try menu(atCharacter: 3)).contains("Image Size"))
    }

    func testChoosingASizeWritesItIntoTheMarkdown() throws {
        textView.string = "![pic](pic.png)\n\nlast"
        let item = try sizeItem("Medium", in: try menu(atCharacter: 3))
        _ = item.target?.perform(item.action, with: item)
        XCTAssertEqual(textView.string, "![pic|\(ImageSize.medium.width!)](pic.png)\n\nlast")
    }

    func testOriginalSizeRemovesTheSize() throws {
        textView.string = "![pic|300](pic.png)\n\nlast"
        let item = try sizeItem("Original Size", in: try menu(atCharacter: 3))
        _ = item.target?.perform(item.action, with: item)
        XCTAssertEqual(textView.string, "![pic](pic.png)\n\nlast")
    }

    func testCurrentSizeIsChecked() throws {
        textView.string = "![pic|\(ImageSize.large.width!)](pic.png)"
        let menu = try menu(atCharacter: 3)
        XCTAssertEqual(try sizeItem("Large", in: menu).state, .on)
        XCTAssertEqual(try sizeItem("Small", in: menu).state, .off)
        XCTAssertEqual(try sizeItem("Original Size", in: menu).state, .off)
    }

    func testChoosingASizeCanBeUndone() throws {
        textView.string = "![pic](pic.png)"
        let undo = try XCTUnwrap(textView.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        let item = try sizeItem("Small", in: try menu(atCharacter: 3))
        _ = item.target?.perform(item.action, with: item)
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(textView.string, "![pic](pic.png)")
    }
}
