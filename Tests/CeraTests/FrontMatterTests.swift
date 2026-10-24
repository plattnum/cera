import AppKit
import XCTest
@testable import Cera

/// Front matter at the start of a file: found, kept out of the Markdown parse, and shown as muted source.
final class FrontMatterTests: XCTestCase {
    private static let yaml = "---\ntitle: Getting Started\ntags: [docs, setup]\n---\n"

    private func range(_ text: String) -> NSRange? {
        FrontMatter.range(in: text as NSString)
    }

    // MARK: Finding it

    func testYAMLFrontMatter() {
        let text = Self.yaml + "# Heading\n"
        XCTAssertEqual(range(text), NSRange(location: 0, length: (Self.yaml as NSString).length))
    }

    func testOtherOpeningsAndClosings() {
        XCTAssertEqual(range("---\na: 1\n...\nText"), NSRange(location: 0, length: 13), "YAML can close with ...")
        XCTAssertEqual(range("+++\na = 1\n+++\nText"), NSRange(location: 0, length: 14), "TOML, as in Hugo")
        XCTAssertEqual(range("---\n---\nText"), NSRange(location: 0, length: 8), "empty")
        XCTAssertEqual(range("---  \na: 1\n--- \t\nText"), NSRange(location: 0, length: 17), "trailing spaces")
        XCTAssertEqual(range("---\r\na: 1\r\n---\r\nText"), NSRange(location: 0, length: 16), "CRLF line breaks")
        XCTAssertEqual(range("\u{FEFF}---\na: 1\n---\nText"), NSRange(location: 0, length: 14), "after a byte order mark")
        XCTAssertEqual(range("---\na: 1\n---"), NSRange(location: 0, length: 12), "closing line at the end of the file")
    }

    func testNotFrontMatter() {
        XCTAssertNil(range("---\na: 1\n"), "unclosed")
        XCTAssertNil(range("----\na: 1\n----\n"), "four dashes")
        XCTAssertNil(range(" ---\na: 1\n---\n"), "indented")
        XCTAssertNil(range("Text\n---\na: 1\n---\n"), "not at the start")
        XCTAssertNil(range("+++\na = 1\n---\n"), "TOML closes with +++ only")
        XCTAssertNil(range("---\na: 1\n+++\n"), "YAML doesn't close with +++")
        XCTAssertNil(range(""))
    }

    func testParsableTextKeepsEveryOffset() {
        let text = (Self.yaml + "# Heading\n") as NSString
        let whole = NSRange(location: 0, length: text.length)
        let (parsable, frontMatter) = FrontMatter.parsable(text, region: whole)
        XCTAssertEqual(frontMatter, NSRange(location: 0, length: (Self.yaml as NSString).length))
        XCTAssertEqual((parsable as NSString).length, text.length)
        let blank = Self.yaml.split(separator: "\n").map { String(repeating: " ", count: $0.count) + "\n" }.joined()
        XCTAssertEqual(parsable, blank + "# Heading\n")
        // A region that doesn't start the document has no front matter.
        let later = NSRange(location: 4, length: text.length - 4)
        XCTAssertNil(FrontMatter.parsable(text, region: later).frontMatter)
    }

    // MARK: Styling

    private func styled(_ text: String, caret: Int? = nil) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler(theme: .ivory).style(storage, caret: caret ?? (text as NSString).length)
        return storage
    }

    func testFrontMatterIsMutedSourceNotARuleOrHeading() throws {
        let text = Self.yaml + "# Heading\n\nBody text.\n"
        let storage = styled(text)
        let frontMatter = NSRange(location: 0, length: (Self.yaml as NSString).length)
        storage.enumerateAttributes(in: frontMatter) { attributes, range, _ in
            XCTAssertEqual(attributes[.font] as? NSFont, Theme.ivory.codeFont, "\(range)")
            XCTAssertEqual(attributes[.foregroundColor] as? NSColor, Theme.ivory.marker, "\(range)")
            XCTAssertNil(attributes[.horizontalRule], "\(range)")
            XCTAssertNil(attributes[.headingUnderline], "\(range)")
        }
        // The heading after it is a heading, with its marker hidden.
        let heading = (text as NSString).range(of: "Heading").location
        let font = try XCTUnwrap(storage.attribute(.font, at: heading, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(font.pointSize, Theme.ivory.bodyFont.pointSize)
        XCTAssertEqual(storage.attribute(.font, at: heading - 2, effectiveRange: nil) as? NSFont, MarkdownStyler.hiddenFont)
    }

    func testUnclosedDashesStayMarkdown() {
        // With no closing line it isn't front matter: the dashes are a rule, as on GitHub.
        let storage = styled("---\nText after a rule.\n")
        XCTAssertNotNil(storage.attribute(.horizontalRule, at: 0, effectiveRange: nil))
    }

    func testBlockRightAfterFrontMatterGetsTheGap() throws {
        let storage = styled(Self.yaml + "Body text.\n\nlast")
        let body = (storage.string as NSString).range(of: "Body").location
        let style = try XCTUnwrap(storage.attribute(.paragraphStyle, at: body, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.paragraphSpacingBefore, Theme.ivory.blockSpacing)
    }

    func testFrontMatterIsATopLevelBlock() {
        let text = (Self.yaml + "# Heading\n\nBody.\n") as NSString
        let blocks = MarkdownStyler.topLevelBlocks(in: text)
        XCTAssertEqual(blocks.first, NSRange(location: 0, length: (Self.yaml as NSString).length))
        XCTAssertEqual(blocks.count, 3)
    }

    func testDefinitionLikeLinesInFrontMatterAreNotDefinitions() {
        let text = "---\n[ref]: https://example.com\n---\n\nA [link][ref].\n" as NSString
        XCTAssertTrue(MarkdownStyler.structure(in: text).definitions.isEmpty)
    }

    // MARK: Outline, anchors, code

    func testOutlineLeavesItOut() {
        let items = Outline.items(in: Self.yaml + "# Heading\n")
        XCTAssertEqual(items.map(\.title), ["Heading"])
        XCTAssertEqual(HeadingAnchors.anchors(in: Self.yaml + "# Heading\n").map(\.anchor), ["heading"])
    }

    func testFenceInsideFrontMatterIsNotCode() {
        let text = "---\nnote: |\n  ```\n---\n\n```\nlet a = 1\n```\n" as NSString
        let region = NSRange(location: 0, length: text.length)
        XCTAssertNil(CodeBlockText.code(in: text, at: text.range(of: "  ```").location, region: region))
        XCTAssertEqual(CodeBlockText.code(in: text, at: text.range(of: "let a").location, region: region), "let a = 1")
    }
}
