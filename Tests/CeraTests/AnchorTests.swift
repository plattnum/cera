import AppKit
import XCTest
@testable import Cera

final class AnchorTests: XCTestCase {

    func testSlugFollowsGitHubRules() {
        XCTAssertEqual(HeadingAnchors.slug("Install"), "install")
        XCTAssertEqual(HeadingAnchors.slug("Getting Started!"), "getting-started")
        // Punctuation goes but its spaces stay, so each becomes a hyphen.
        XCTAssertEqual(HeadingAnchors.slug("API & SDK"), "api--sdk")
        XCTAssertEqual(HeadingAnchors.slug("C++ / C#"), "c--c")
        XCTAssertEqual(HeadingAnchors.slug("snake_case and kebab-case"), "snake_case-and-kebab-case")
        XCTAssertEqual(HeadingAnchors.slug("Version 1.2"), "version-12")
        XCTAssertEqual(HeadingAnchors.slug("Café Über"), "café-über")
        XCTAssertEqual(HeadingAnchors.slug("🚀 Launch"), "-launch")
    }

    func testAnchorsUseHeadingTextWithoutMarkup() {
        let text = "# The `cera` command\n\n## [Docs](https://x.y) and **more**\n"
        XCTAssertEqual(HeadingAnchors.anchors(in: text).map(\.anchor), ["the-cera-command", "docs-and-more"])
    }

    func testRepeatedAnchorsGetNumbered() {
        let text = "# Setup\n\n## Setup\n\n### Setup\n\n# Other\n"
        XCTAssertEqual(HeadingAnchors.anchors(in: text).map(\.anchor), ["setup", "setup-1", "setup-2", "other"])
    }

    func testLocationFindsTheHeadingLine() {
        let text = "Intro\n\n## Install\n\nSteps\n\n## Usage\n\nRun it\n"
        let source = text as NSString
        XCTAssertEqual(HeadingAnchors.location(of: "install", in: text), source.range(of: "## Install").location)
        XCTAssertEqual(HeadingAnchors.location(of: "usage", in: text), source.range(of: "## Usage").location)
    }

    func testLocationMatchesIgnoringCase() {
        let text = "# Read Me\n"
        XCTAssertEqual(HeadingAnchors.location(of: "Read-Me", in: text), 0)
    }

    func testTopMeansTheStartUnlessAHeadingIsNamedTop() {
        XCTAssertEqual(HeadingAnchors.location(of: "top", in: "Intro\n\n# End\n"), 0)
        let named = "Intro\n\n# Top\n"
        XCTAssertEqual(HeadingAnchors.location(of: "top", in: named), (named as NSString).range(of: "# Top").location)
    }

    func testUnknownAnchorHasNoLocation() {
        XCTAssertNil(HeadingAnchors.location(of: "missing", in: "# Here\n"))
        XCTAssertNil(HeadingAnchors.location(of: "", in: "# Here\n"))
    }

    // MARK: - Resolving and following

    func testInPageAnchorResolvesToItsFragment() throws {
        let url = try XCTUnwrap(LinkResolver.resolve("#install", relativeTo: nil))
        XCTAssertNil(url.scheme)
        XCTAssertEqual(LinkResolver.action(for: url), .heading("install"))
    }

    func testBareHashStaysUnresolved() {
        XCTAssertNil(LinkResolver.resolve("#", relativeTo: nil))
    }

    func testAnchorIsPercentDecoded() throws {
        let url = try XCTUnwrap(LinkResolver.resolve("#caf%C3%A9", relativeTo: nil))
        XCTAssertEqual(LinkResolver.action(for: url), .heading("café"))
    }

    func testMarkdownFileLinkKeepsItsAnchor() throws {
        let base = URL(fileURLWithPath: "/Users/me/docs")
        let url = try XCTUnwrap(LinkResolver.resolve("guide/setup.md#install", relativeTo: base))
        XCTAssertEqual(LinkResolver.action(for: url),
                       .markdownFile(URL(fileURLWithPath: "/Users/me/docs/guide/setup.md"), heading: "install"))
    }

    func testMarkdownFileLinkWithoutAnchorOpensInCera() throws {
        let base = URL(fileURLWithPath: "/Users/me/docs")
        let md = try XCTUnwrap(LinkResolver.resolve("guide/setup.md", relativeTo: base))
        XCTAssertEqual(LinkResolver.action(for: md),
                       .markdownFile(URL(fileURLWithPath: "/Users/me/docs/guide/setup.md"), heading: nil))
        let long = try XCTUnwrap(LinkResolver.resolve("Notes.Markdown", relativeTo: base))
        XCTAssertEqual(LinkResolver.action(for: long),
                       .markdownFile(URL(fileURLWithPath: "/Users/me/docs/Notes.Markdown"), heading: nil))
    }

    func testOtherLinksOpenAsBefore() throws {
        let base = URL(fileURLWithPath: "/Users/me/docs")
        let web = try XCTUnwrap(LinkResolver.resolve("https://example.com/a#b", relativeTo: base))
        XCTAssertEqual(LinkResolver.action(for: web), .open(web))
        // Any other file opens in its default app, its anchor dropped as it always was.
        let pdf = try XCTUnwrap(LinkResolver.resolve("paper.pdf#page=2", relativeTo: base))
        XCTAssertEqual(LinkResolver.action(for: pdf), .open(URL(fileURLWithPath: "/Users/me/docs/paper.pdf")))
    }

    func testStylerAttachesTargetToInPageLink() {
        let source = "See [Install](#install).\n\n## Install\n"
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: .midnight).style(storage, caret: (source as NSString).length)
        let index = (source as NSString).range(of: "Install").location
        let url = storage.attribute(.linkTarget, at: index, effectiveRange: nil) as? URL
        XCTAssertEqual(url.map(LinkResolver.action(for:)), .heading("install"))
    }

    @MainActor
    func testFollowingAnInPageLinkMovesToTheHeading() throws {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        let filler = (1...80).map { "Paragraph \($0)." }.joined(separator: "\n\n")
        textView.string = "[Usage](#usage)\n\n\(filler)\n\n## Usage\n\nRun it.\n"
        MarkdownStyler(theme: .midnight).style(try XCTUnwrap(textView.textStorage), caret: 0)

        textView.followLink(try XCTUnwrap(URL(string: "#usage")))

        let heading = (textView.string as NSString).range(of: "## Usage").location
        XCTAssertEqual(textView.selectedRange(), NSRange(location: heading, length: 0))
        XCTAssertTrue(textView.isLineVisible(at: heading))
        window.close()
    }

    @MainActor
    func testFollowingAnUnknownAnchorDoesNothing() throws {
        let (_, textView) = MarkdownEditor.makeScrollView()
        textView.string = "# Here\n\ntext\n"
        textView.setSelectedRange(NSRange(location: 9, length: 0))
        textView.followLink(try XCTUnwrap(URL(string: "#missing")))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))
    }
}
