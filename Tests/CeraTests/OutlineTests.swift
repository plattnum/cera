import AppKit
import XCTest
@testable import Cera

final class OutlineTests: XCTestCase {

    // MARK: - Finding headings

    private func titles(_ text: String) -> [String] {
        Outline.items(in: text).map(\.title)
    }

    func testFindsHashAndUnderlinedHeadingsWithLevels() {
        let text = "Title\n=====\n\nIntro.\n\n## Part one\n\nSub\n---\n\n#### Deep\n"
        let items = Outline.items(in: text)
        XCTAssertEqual(items.map(\.title), ["Title", "Part one", "Sub", "Deep"])
        XCTAssertEqual(items.map(\.level), [1, 2, 2, 4])
        XCTAssertEqual(items.map(\.id), [0, 1, 2, 3])
    }

    func testLocationsAreLineStartsInUTF16() {
        let text = "😀 emoji line\n\n# First\n\nText 💡\n\n  ## Indented\n"
        let items = Outline.items(in: text)
        let ns = text as NSString
        XCTAssertEqual(items.map(\.location), [ns.range(of: "# First").location, ns.range(of: "  ## Indented").location])
    }

    func testWindowsLineEndings() {
        let text = "# One\r\n\r\nText\r\n\r\n# Two\r\n"
        XCTAssertEqual(Outline.items(in: text).map(\.location), [0, (text as NSString).range(of: "# Two").location])
    }

    func testTitleIsPlainText() {
        XCTAssertEqual(titles("# Use **bold**, `code`, and [links](https://x.com)\n"), ["Use bold, code, and links"])
        XCTAssertEqual(titles("## Closing hashes ##\n"), ["Closing hashes"])
        XCTAssertEqual(titles("# ![logo](logo.png) Cera\n"), ["logo Cera"])
    }

    func testMultiLineUnderlinedHeadingIsOneLine() {
        XCTAssertEqual(titles("A heading\nover two lines\n===\n"), ["A heading over two lines"])
    }

    func testHashLinesInCodeAreNotHeadings() {
        let text = "# Real\n\n```bash\n# a comment\n```\n\n    # indented code\n\n# Also real\n"
        XCTAssertEqual(titles(text), ["Real", "Also real"])
    }

    func testHeadingsInsideListsAndQuotesAreLeftOut() {
        XCTAssertEqual(titles("# Top\n\n- # in a list\n\n> # in a quote\n"), ["Top"])
    }

    func testEmptyHeadingsAreLeftOut() {
        XCTAssertEqual(titles("#\n\n# \n\n# Named\n"), ["Named"])
    }

    func testNoHeadings() {
        XCTAssertEqual(Outline.items(in: "").count, 0)
        XCTAssertEqual(Outline.items(in: "Just a paragraph.\n").count, 0)
    }

    func testIndexBeforeLocation() {
        let items = Outline.items(in: "Intro\n\n# A\n\ntext\n\n# B\n\ntext\n")
        let a = items[0].location, b = items[1].location
        XCTAssertNil(Outline.index(in: items, before: 0))
        XCTAssertEqual(Outline.index(in: items, before: a), 0)
        XCTAssertEqual(Outline.index(in: items, before: b - 1), 0)
        XCTAssertEqual(Outline.index(in: items, before: b), 1)
        XCTAssertEqual(Outline.index(in: items, before: 10_000), 1)
        XCTAssertNil(Outline.index(in: [], before: 5))
    }
}

/// The outline driving a real editor in a window.
@MainActor
final class OutlineNavigationTests: XCTestCase {
    private var window: NSWindow!
    private var textView: MarkdownTextView!
    private var model: OutlineModel!

    /// 30 sections of 20 lines each.
    private static let document: String = (1...30).map { section in
        "## Section \(section)\n\n" + (1...20).map { "Line \($0) of section \(section)." }.joined(separator: "\n\n")
    }.joined(separator: "\n\n") + "\n"

    override func setUp() async throws {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                          styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.contentView = scrollView
        self.textView = textView
        textView.string = Self.document
        MarkdownStyler(theme: .midnight).style(textView.textStorage!, caret: 0, availableWidth: 600)
        // Lay out the whole document, so positions are exact rather than estimated.
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        model = OutlineModel()
        model.textView = textView
        model.update(text: Self.document, immediately: true)
        NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView,
                                               queue: nil) { [weak model] _ in
            MainActor.assumeIsolated { model?.visibleAreaChanged() }
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    override func tearDown() async throws {
        window.close()
    }

    private func location(of title: String) -> Int {
        (textView.string as NSString).range(of: "## \(title)\n").location
    }

    func testFindsTheSections() {
        XCTAssertEqual(model.items.count, 30)
        XCTAssertEqual(model.current, 0, "the document opens on its first section")
    }

    func testTitleBarCoversTheTopOfTheText() {
        XCTAssertGreaterThan(textView.obscuredTop, 0, "the editor runs up under the transparent title bar")
    }

    func testJumpPutsTheHeadingAtTheTopBelowTheTitleBar() {
        model.jump(to: 14)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: location(of: "Section 15"), length: 0))
        XCTAssertEqual(textView.characterIndex(belowVisibleTop: 2), location(of: "Section 15"),
                       "the heading's line is the first one below the title bar")
        XCTAssertTrue(textView.isLineVisible(at: location(of: "Section 15")))
        XCTAssertEqual(model.current, 14)
    }

    func testCurrentFollowsScrolling() {
        model.jump(to: 4)
        XCTAssertEqual(model.current, 4)
        // Scroll down into the middle of section 5: still section 5.
        textView.scroll(NSPoint(x: 0, y: textView.visibleRect.minY + 200))
        XCTAssertEqual(model.current, 4)
        // Bring section 9's heading to the top: section 9.
        textView.scrollLineToTop(at: location(of: "Section 9"))
        XCTAssertEqual(model.current, 8)
        // Back to the very top: section 1.
        textView.scroll(.zero)
        XCTAssertEqual(model.current, 0)
    }

    func testJumpingNearTheEndKeepsTheChosenHeadingHighlighted() {
        // The last section is too short to scroll to the top of the window.
        model.jump(to: 29)
        XCTAssertEqual(model.current, 29)
        XCTAssertTrue(textView.isLineVisible(at: location(of: "Section 30")))
        // Scrolling it out of view hands back to the natural choice.
        textView.scrollLineToTop(at: location(of: "Section 3"))
        XCTAssertEqual(model.current, 2)
    }

    func testJumpAfterAnEditFindsTheHeadingsAgain() {
        // Insert a section at the top without telling the model; its headings are stale.
        textView.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 0), with: "## New first\n\nIntro.\n\n")
        model.jump(to: 1)
        XCTAssertEqual(model.items.count, 31)
        XCTAssertEqual(textView.selectedRange().location, location(of: "Section 1"))
    }

    func testJumpNoticesAnEditMadeAfterTheHeadingsWereFound() {
        // The editor hands the outline `textView.string`, which stays tied to the live text when read
        // back as an NSString. An edit after that must still count as a change.
        model.update(text: textView.string, immediately: true)
        textView.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 0), with: "## New first\n\nIntro.\n\n")
        model.jump(to: 1)
        XCTAssertEqual(model.items.count, 31)
        XCTAssertEqual(textView.selectedRange().location, location(of: "Section 1"))
    }

    func testOutOfRangeJumpDoesNothing() {
        let before = textView.selectedRange()
        model.jump(to: 99)
        XCTAssertEqual(textView.selectedRange(), before)
    }

    func testUpdateWhileTypingArrivesAfterAPause() async throws {
        let edited = Self.document + "\n## Appended\n"
        textView.string = edited
        model.update(text: edited)
        XCTAssertEqual(model.items.count, 30, "not right away")
        for _ in 0..<50 where model.items.count == 30 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(model.items.last?.title, "Appended")
    }

    func testLaterUpdateWinsOverAnEarlierOne() async throws {
        model.update(text: Self.document + "\n## First edit\n")
        model.update(text: Self.document + "\n## Second edit\n")
        for _ in 0..<50 where model.items.count == 30 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(model.items.last?.title, "Second edit")
    }

    func testJumpsLandOnTheHeadingInALargeDocumentLaidOutOnlyWhereSeen() {
        // Like the app: no full layout, so heights above the target are estimated.
        let (scrollView, bigView) = MarkdownEditor.makeScrollView()
        let bigWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                                 styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        bigWindow.isReleasedWhenClosed = false
        bigWindow.titlebarAppearsTransparent = true
        defer { bigWindow.close() }
        bigWindow.contentView = scrollView
        let text = String(repeating: Self.document, count: 20)
        bigView.string = text
        MarkdownStyler(theme: .midnight).style(bigView.textStorage!, caret: 0, availableWidth: 600)
        let bigModel = OutlineModel()
        bigModel.textView = bigView
        bigModel.update(text: text, immediately: true) // Large enough to be read in the background.

        for index in [300, 590, 150, 10, 451] {
            bigModel.jump(to: index) // The first jump reads the headings now.
            XCTAssertEqual(bigModel.items.count, 600)
            bigWindow.display()
            XCTAssertEqual(bigView.characterIndex(belowVisibleTop: 2), bigModel.items[index].location, "heading \(index)")
            XCTAssertEqual(bigModel.current, index)
        }
    }

    /// Opening the outline narrows the editor; the text in view must not creep.
    func testNarrowingAndWideningKeepsTheTextInView() async throws {
        // Long lines, so a new width really rewraps them.
        let long = (1...60).map { "## Part \($0)\n\n" + String(repeating: "A long line of words that wraps. ", count: 12) }
            .joined(separator: "\n\n")
        textView.string = long
        MarkdownStyler(theme: .midnight).style(textView.textStorage!, caret: 0, availableWidth: 600)
        textView.scrollLineToTop(at: (long as NSString).range(of: "## Part 30\n").location)
        let before = try XCTUnwrap(textView.readingPosition())
        for width in [560.0, 800, 560, 800] {
            window.setContentSize(NSSize(width: width, height: 500))
            try await Task.sleep(nanoseconds: 50_000_000) // The position is put back on the next turn.
            let now = try XCTUnwrap(textView.readingPosition())
            XCTAssertEqual(now.character, before.character, "width \(width)")
            XCTAssertEqual(now.offset, before.offset, accuracy: 1, "width \(width)")
        }
    }

    func testAtTheTopTheViewStaysAtTheTop() async throws {
        textView.scroll(NSPoint(x: 0, y: -1000)) // As far up as it goes.
        let top = textView.visibleRect.minY
        XCTAssertNil(textView.readingPosition())
        window.setContentSize(NSSize(width: 560, height: 500))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(textView.visibleRect.minY, top)
    }

    func testAddingAHeadingForgetsTheOneJumpedTo() {
        model.jump(to: 29) // Near the end: highlighted because it was chosen, not by position.
        XCTAssertEqual(model.current, 29)
        // A new heading at the top shifts every heading's number; number 29 is now Section 29.
        let edited = "## Added\n\n" + textView.string
        textView.string = edited
        model.update(text: edited, immediately: true)
        XCTAssertEqual(model.items[29].title, "Section 29")
        XCTAssertNotEqual(model.current, 29, "the old number isn't kept highlighted")
    }
}
