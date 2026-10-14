import AppKit
import XCTest
@testable import Cera

final class LinkTests: XCTestCase {

    func testResolvesWebMailAndRelativeLinks() {
        let base = URL(fileURLWithPath: "/Users/me/docs")
        XCTAssertEqual(LinkResolver.resolve("https://example.com/a", relativeTo: base)?.absoluteString, "https://example.com/a")
        XCTAssertEqual(LinkResolver.resolve("mailto:me@example.com", relativeTo: base)?.scheme, "mailto")
        XCTAssertEqual(LinkResolver.resolve("www.example.com", relativeTo: base)?.absoluteString, "https://www.example.com")
        XCTAssertEqual(LinkResolver.resolve("guide/setup.md#install", relativeTo: base)?.path, "/Users/me/docs/guide/setup.md")
        XCTAssertNil(LinkResolver.resolve("#section", relativeTo: base))
    }

    func testStylerAttachesTargetsToEveryLinkForm() {
        let source = "[site](https://example.com) and <https://a.b> and https://c.d\n\nlast"
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: .midnight).style(storage, caret: (source as NSString).length)
        let text = source as NSString

        func target(at word: String) -> String? {
            (storage.attribute(.linkTarget, at: text.range(of: word).location, effectiveRange: nil) as? URL)?.absoluteString
        }
        XCTAssertEqual(target(at: "site"), "https://example.com")
        XCTAssertEqual(target(at: "a.b"), "https://a.b")
        XCTAssertEqual(target(at: "c.d"), "https://c.d")
        XCTAssertNil(storage.attribute(.linkTarget, at: text.range(of: "and").location, effectiveRange: nil))
    }

    func testClickPointFindsLinkUnderIt() throws {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        textView.string = "Go to [the site](https://example.com) now.\n\nlast"
        MarkdownStyler(theme: .midnight).style(try XCTUnwrap(textView.textStorage), caret: (textView.string as NSString).length)

        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let container = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: container)

        func point(atCharacter index: Int) -> NSPoint {
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            return NSPoint(x: rect.midX + textView.textContainerOrigin.x, y: rect.midY + textView.textContainerOrigin.y)
        }
        let text = textView.string as NSString
        XCTAssertEqual(textView.linkURL(at: point(atCharacter: text.range(of: "site").location))?.absoluteString,
                       "https://example.com")
        XCTAssertNil(textView.linkURL(at: point(atCharacter: text.range(of: "Go").location)))
        window.close()
    }
}
