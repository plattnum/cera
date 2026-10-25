import AppKit
import XCTest
@testable import Cera

/// The status bar: line, column, and words.
@MainActor
final class StatusBarTests: XCTestCase {
    // MARK: Words

    func testWordsAreRunsOfLettersAndDigits() {
        XCTAssertEqual(StatusCounts.words(in: "One two  three\nfour 5 6th"), 6)
        XCTAssertEqual(StatusCounts.words(in: ""), 0)
        XCTAssertEqual(StatusCounts.words(in: "   \n\n"), 0)
    }

    func testApostrophesHyphensAndUnderscoresInsideAWordKeepItWhole() {
        XCTAssertEqual(StatusCounts.words(in: "don't stop, it’s a well-known snake_case name"), 7)
        XCTAssertEqual(StatusCounts.words(in: "a - b -- c 'quoted'"), 4, "on their own they aren't words")
    }

    func testMarkdownSymbolsDontCount() {
        XCTAssertEqual(StatusCounts.words(in: "# Title\n\n- **bold** and *it*\n> quote\n\n---\n| a | b |"), 7)
    }

    func testLinkDestinationsDefinitionsAndTagsDontCount() {
        XCTAssertEqual(StatusCounts.words(in: "See [the docs](https://example.com/a/b) now."), 4)
        XCTAssertEqual(StatusCounts.words(in: "![a picture](images/p.png)"), 2)
        XCTAssertEqual(StatusCounts.words(in: "[Swift](https://en.wikipedia.org/wiki/Swift_(language)) rocks"), 2)
        XCTAssertEqual(StatusCounts.words(in: "Use [this][ref].\n\n[ref]: https://example.com/long/path \"Title\""), 2)
        XCTAssertEqual(StatusCounts.words(in: "<div align=\"center\">Centered text</div>"), 2)
    }

    func testFrontMatterDoesntCount() {
        XCTAssertEqual(StatusCounts.words(in: "---\ntitle: Many words in here\n---\nTwo words"), 2)
        XCTAssertEqual(StatusCounts.words(in: "---\ntitle: x\n---\nTwo words", skippingFrontMatter: false), 4)
    }

    func testCodeCounts() {
        XCTAssertEqual(StatusCounts.words(in: "Run `make all`:\n\n```\nlet a = 1\n```"), 6)
    }

    // MARK: Line and column

    private func position(_ text: String, at location: Int) -> (Int, Int) {
        let position = StatusCounts.position(in: text as NSString, at: location)
        return (position.line, position.column)
    }

    func testLineAndColumn() {
        let text = "first\nsecond line\n\nfourth"
        XCTAssertTrue(position(text, at: 0) == (1, 1))
        XCTAssertTrue(position(text, at: 5) == (1, 6), "the end of the first line")
        XCTAssertTrue(position(text, at: 6) == (2, 1))
        XCTAssertTrue(position(text, at: 13) == (2, 8))
        XCTAssertTrue(position(text, at: 18) == (3, 1), "an empty line")
        XCTAssertTrue(position(text, at: (text as NSString).length) == (4, 7), "the end of the text")
    }

    func testOtherLineBreaks() {
        XCTAssertTrue(position("a\r\nb\r\nc", at: 6) == (3, 1), "CRLF counts once")
        XCTAssertTrue(position("a\rb\rc", at: 4) == (3, 1), "CR alone")
    }

    func testColumnCountsCharactersNotUnits() {
        // 👍🏽 is four UTF-16 units and one character.
        XCTAssertTrue(position("a👍🏽b", at: 5) == (1, 3))
    }

    // MARK: The bar

    /// Runs the main queue until `condition` holds, for the bar's deferred and background updates.
    private func waitUntil(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    func testBarText() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = "One two three.\nFour five."
        let model = StatusModel()
        model.textView = textView
        model.isShown = true
        textView.setSelectedRange(NSRange(location: 19, length: 0))
        model.selectionChanged()
        waitUntil(model.words == 5 && model.line == 2)
        XCTAssertEqual(model.positionText, "Ln 2, Col 5")
        XCTAssertEqual(model.wordsText, "5 words")

        textView.setSelectedRange(NSRange(location: 4, length: 9))   // "two three"
        model.selectionChanged()
        waitUntil(model.selectedWords == 2)
        XCTAssertEqual(model.positionText, "Ln 1, Col 5 (9 selected)")
        XCTAssertEqual(model.wordsText, "2 of 5 words")

        textView.string = "Alone"
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        model.textChanged(delay: 0)
        model.selectionChanged()
        waitUntil(model.words == 1 && model.selectedCharacters == 0)
        XCTAssertEqual(model.wordsText, "1 word")
    }

    func testSeveralSelectionsAddUp() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = "one two three four"
        let model = StatusModel()
        model.textView = textView
        model.isShown = true
        textView.selectedRanges = [NSValue(range: NSRange(location: 0, length: 3)), NSValue(range: NSRange(location: 8, length: 5))]
        model.selectionChanged()
        waitUntil(model.selectedWords == 2)
        XCTAssertEqual(model.selectedCharacters, 8)
        XCTAssertEqual(model.positionText, "Ln 1, Col 1 (8 selected)")
    }

    func testNothingIsCountedWhileHidden() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = "some words here"
        let model = StatusModel()
        model.textView = textView
        model.textChanged(delay: 0)
        model.selectionChanged()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(model.words, 0)
        model.isShown = true
        waitUntil(model.words == 3)
    }
}
