import AppKit
import XCTest
@testable import Cera

/// Incremental and region-by-region styling must give exactly the same result as
/// styling the whole document in one pass.
final class LiveStylerTests: XCTestCase {

    private static let document = """
    Title
    =====

    Intro with **bold**, *italic*, `code`, a [link][ref], and <https://a.b>.

    ## Lists

    - one
    - two
      - nested
    1. first
    2. second

    - [ ] task
    - [x] done

    > quote
    >
    > > nested quote

    | A | B |
    |:--|--:|
    | 1 | **2** |

    ```bash
    # comment
    echo "hi" 42
    ```

        indented code

    ---

    Last paragraph
    with a second line.

    [ref]: https://example.com
    """

    private let settings = LiveStyler.Settings(theme: .midnight, baseURL: nil, availableWidth: 700)

    private func fullyStyled(_ text: String, caret: Int) -> NSAttributedString {
        let storage = NSTextStorage(string: text)
        MarkdownStyler(theme: settings.theme).style(storage, caret: caret, availableWidth: settings.availableWidth,
                                                    regionLength: .max)
        return storage
    }

    private func assertSameStyling(_ actual: NSAttributedString, _ expected: NSAttributedString, _ message: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard !actual.isEqual(to: expected) else { return }
        // Report the first difference to make failures readable.
        var location = 0
        while location < actual.length {
            var actualRange = NSRange(), expectedRange = NSRange()
            let a = actual.attributes(at: location, effectiveRange: &actualRange)
            let e = expected.attributes(at: location, effectiveRange: &expectedRange)
            if !NSDictionary(dictionary: a).isEqual(to: e) {
                let snippet = (actual.string as NSString).substring(with: NSRange(location: location, length: min(20, actual.length - location)))
                XCTFail("\(message): styling differs at \(location) (\"\(snippet)\")\nactual: \(a)\nexpected: \(e)", file: file, line: line)
                return
            }
            location = min(NSMaxRange(actualRange), NSMaxRange(expectedRange))
        }
        XCTFail("\(message): text differs", file: file, line: line)
    }

    func testStylingInSmallRegionsMatchesOnePass() {
        let text = Self.document
        let caret = (text as NSString).range(of: "two").location
        let small = NSTextStorage(string: text)
        MarkdownStyler(theme: settings.theme).style(small, caret: caret, availableWidth: settings.availableWidth, regionLength: 40)
        assertSameStyling(small, fullyStyled(text, caret: caret), "regions of 40 characters")
    }

    func testBackgroundPassFinishesWithFullStyling() {
        let text = String(repeating: Self.document + "\n\n", count: 20)
        let storage = NSTextStorage(string: text)
        let styler = LiveStyler(storage: storage, settings: settings, regionLength: 500)
        styler.restyleAll(caret: 0, immediateLength: 1_000)
        XCTAssertTrue(styler.isStylingInBackground)
        styler.finishBackgroundStyling(caret: 0)
        assertSameStyling(storage, fullyStyled(text, caret: 0), "after background pass")
    }

    func testIncrementalEditsMatchFullRestyle() {
        for seed: UInt64 in [42, 7, 1234, 99, 2026] {
            runRandomEdits(seed: seed, document: Self.document)
            if testRun?.failureCount ?? 0 > 0 { return }
        }
    }

    /// Blocks with no blank line between them, including tables that interrupt a paragraph, which are
    /// styled apart from it.
    func testIncrementalEditsAroundAdjacentBlocksMatchFullRestyle() {
        let document = """
        ## Heading
        Some **bold** text:
        | A | B |
        |---|---|
        | 1 | 2 |
        - [x] task
        1. [ ] numbered
        > - [ ] quoted task
        Intro:
        ```swift
        let a = 1
        ```
        - Item:
          | A | B |
          |---|---|
          | 1 | 2 |

        last
        """
        for seed: UInt64 in [3, 17, 2026] {
            runRandomEdits(seed: seed, document: document)
            if testRun?.failureCount ?? 0 > 0 { return }
        }
    }

    /// A longer run for stress testing: CERA_STRESS_FILE=doc.md CERA_STRESS_SEEDS=30
    func testStressIncrementalEdits() throws {
        let env = ProcessInfo.processInfo.environment
        guard let seeds = env["CERA_STRESS_SEEDS"].flatMap(UInt64.init) else { throw XCTSkip("Set CERA_STRESS_SEEDS.") }
        let document = try env["CERA_STRESS_FILE"].map { try String(contentsOfFile: $0, encoding: .utf8) } ?? Self.document
        for seed in 1...seeds {
            // The app's run loop empties the autorelease pool after every event; without that, a long
            // run here keeps every styled copy alive and runs out of memory.
            autoreleasepool { runRandomEdits(seed: seed, document: document) }
            if testRun?.failureCount ?? 0 > 0 { return }
        }
    }

    private func runRandomEdits(seed: UInt64, document: String) {
        let storage = NSTextStorage(string: document)
        let styler = LiveStyler(storage: storage, settings: settings)
        styler.restyleAll(caret: 0)
        styler.finishBackgroundStyling(caret: 0)

        // Insertions chosen to change structure: new blocks, markers, merges, splits.
        let insertions = ["x", "\n", "\n\n", "**", "*", "`", "# ", "- ", "1. ", "> ", "| c |", "---", "[", "](u)", "~~", "    ", "```"]
        var generator = SeededGenerator(seed: seed)
        var previousCaret = 0
        for step in 0..<300 { let stop: Bool = autoreleasepool {
            let length = storage.length
            let location = length == 0 ? 0 : Int.random(in: 0...length, using: &generator)
            let edit: (range: NSRange, replacement: String)
            if Bool.random(using: &generator), location < length {
                let deleteLength = min(Int.random(in: 1...6, using: &generator), length - location)
                edit = (NSRange(location: location, length: deleteLength), "")
            } else {
                edit = (NSRange(location: location, length: 0), insertions.randomElement(using: &generator)!)
            }
            // A copy: `storage.string` is the storage's live text, so bridged back to NSString after
            // the edit it would already hold the edit.
            let oldText = NSString(string: storage.string) as String
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
            let newLength = (edit.replacement as NSString).length
            let caret = edit.range.location + newLength
            let previousLine = (oldText as NSString).lineRange(for: NSRange(location: min(previousCaret, (oldText as NSString).length), length: 0)).location
            styler.textChanged(editedRange: NSRange(location: edit.range.location, length: newLength),
                               delta: newLength - edit.range.length, caret: caret, previousLine: previousLine)
            previousCaret = caret
            styler.finishBackgroundStyling(caret: caret)

            let expected = fullyStyled(storage.string, caret: caret)
            if !storage.isEqual(to: expected), let dump = ProcessInfo.processInfo.environment["CERA_STRESS_DUMP"] {
                try? oldText.write(toFile: dump + "/before.md", atomically: true, encoding: .utf8)
                try? storage.string.write(toFile: dump + "/after.md", atomically: true, encoding: .utf8)
                try? "\(edit.range.location) \(edit.range.length) \(edit.replacement.debugDescription) caret \(caret) previousCaret \(previousCaret)"
                    .write(toFile: dump + "/edit.txt", atomically: true, encoding: .utf8)
            }
            assertSameStyling(storage, expected, "seed \(seed) step \(step)")
            return testRun?.failureCount ?? 0 > 0
        }; if stop { return } }
    }

    func testEditsDuringBackgroundStylingEndInFullStyling() {
        let text = String(repeating: Self.document + "\n\n", count: 8)
        let storage = NSTextStorage(string: text)
        let styler = LiveStyler(storage: storage, settings: settings, regionLength: 200)
        styler.restyleAll(caret: 0, immediateLength: 200)
        XCTAssertTrue(styler.isStylingInBackground)

        var generator = SeededGenerator(seed: 5)
        let insertions = ["x", "\n", "\n\n", "**", "# ", "- ", "> ", "| c |", "---", "```"]
        var caret = 0
        var previousLine = 0
        for _ in 0..<60 {
            let location = Int.random(in: 0...storage.length, using: &generator)
            let insertion = insertions.randomElement(using: &generator)!
            storage.replaceCharacters(in: NSRange(location: location, length: 0), with: insertion)
            let length = (insertion as NSString).length
            caret = location + length
            styler.textChanged(editedRange: NSRange(location: location, length: length), delta: length, caret: caret,
                               previousLine: previousLine)
            previousLine = (storage.string as NSString).lineRange(for: NSRange(location: caret, length: 0)).location
        }
        styler.finishBackgroundStyling(caret: caret)
        assertSameStyling(storage, fullyStyled(storage.string, caret: caret), "after edits during background styling")
    }

    func testCaretMovesOnlyChangeMarkerVisibility() {
        let text = Self.document
        let storage = NSTextStorage(string: text)
        let styler = LiveStyler(storage: storage, settings: settings)
        styler.restyleAll(caret: 0)
        styler.finishBackgroundStyling(caret: 0)

        let ns = text as NSString
        var previous = 0
        for word in ["two", "quote", "comment", "**2**", "Last", "Intro"] {
            let caret = ns.range(of: word).location
            styler.caretMoved(fromLineAt: ns.lineRange(for: NSRange(location: previous, length: 0)).location,
                              toLineAt: ns.lineRange(for: NSRange(location: caret, length: 0)).location, caret: caret)
            assertSameStyling(storage, fullyStyled(text, caret: caret), "caret on \(word)")
            previous = caret
        }
    }
}

/// A small deterministic random number generator, so failures can be reproduced.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
