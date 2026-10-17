import AppKit
import XCTest
@testable import Cera

/// Typing in code blocks. In the texts, ‸ marks the cursor and «…» a selection.
final class CodeEditingTests: XCTestCase {

    /// A text view holding `marked`, with the cursor or selection it marks.
    private func editor(_ marked: String) -> MarkdownTextView {
        var text = marked
        var selection = NSRange(location: 0, length: 0)
        if let caret = text.range(of: "‸") {
            selection.location = (String(text[..<caret.lowerBound]) as NSString).length
            text.removeSubrange(caret)
        } else if let open = text.range(of: "«"), let close = text.range(of: "»") {
            let start = (String(text[..<open.lowerBound]) as NSString).length
            let end = (String(text[..<close.lowerBound]) as NSString).length - 1
            text.removeSubrange(close)
            text.removeSubrange(text.range(of: "«")!)
            selection = NSRange(location: start, length: end - start)
        }
        let textView = MarkdownTextView.makeEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.string = text
        textView.setSelectedRange(selection)
        return textView
    }

    /// The text with the cursor or selection marked again.
    private func marked(_ textView: MarkdownTextView) -> String {
        let text = textView.string as NSString
        let selection = textView.selectedRange()
        if selection.length == 0 {
            return text.replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "‸")
        }
        return text.substring(to: selection.location) + "«" + text.substring(with: selection) + "»"
            + text.substring(from: NSMaxRange(selection))
    }

    private func afterReturn(_ text: String) -> String {
        let textView = editor(text)
        textView.insertNewline(nil)
        return marked(textView)
    }

    private func afterTab(_ text: String) -> String {
        let textView = editor(text)
        textView.insertTab(nil)
        return marked(textView)
    }

    private func afterBacktab(_ text: String) -> String {
        let textView = editor(text)
        textView.insertBacktab(nil)
        return marked(textView)
    }

    // MARK: - Return

    func testReturnKeepsIndentation() {
        XCTAssertEqual(afterReturn("```py\ndef f():\n    return 1‸\n```\n"), "```py\ndef f():\n    return 1\n    ‸\n```\n")
        XCTAssertEqual(afterReturn("```go\nfunc f() {\n\tx := 1‸\n}\n```\n"), "```go\nfunc f() {\n\tx := 1\n\t‸\n}\n```\n")
    }

    func testReturnInsideTheIndentationSplitsIt() {
        XCTAssertEqual(afterReturn("```\n  ‸  code\n```\n"), "```\n  \n  ‸  code\n```\n")
    }

    func testReturnAtTheStartOfALineAddsNoIndentation() {
        XCTAssertEqual(afterReturn("```\n‸    code\n```\n"), "```\n\n‸    code\n```\n")
    }

    func testReturnReplacesTheSelection() {
        XCTAssertEqual(afterReturn("```\n    a «bc» d\n```\n"), "```\n    a \n    ‸ d\n```\n")
    }

    func testReturnDoesNotContinueListsOrQuotesInCode() {
        XCTAssertEqual(afterReturn("```yaml\nitems:\n  - one‸\n```\n"), "```yaml\nitems:\n  - one\n  ‸\n```\n")
        XCTAssertEqual(afterReturn("```\n1. step‸\n```\n"), "```\n1. step\n‸\n```\n")
        XCTAssertEqual(afterReturn("```\n> quoted in code‸\n```\n"), "```\n> quoted in code\n‸\n```\n")
        // An empty "- " line in code isn't an empty list item to end.
        XCTAssertEqual(afterReturn("```\n- ‸\n```\n"), "```\n- \n‸\n```\n")
    }

    func testReturnInAQuotedBlockKeepsOneQuoteMarker() {
        XCTAssertEqual(afterReturn("> ```\n>     code‸\n> ```\n"), "> ```\n>     code\n>     ‸\n> ```\n")
        // At the very start of a quoted line, both lines keep their marker.
        XCTAssertEqual(afterReturn("> ```\n‸> code\n> ```\n"), "> ```\n> \n‸> code\n> ```\n")
    }

    func testReturnInABlockOpenedOnAListLine() {
        XCTAssertEqual(afterReturn("- ```sh\n  make‸\n  ```\n"), "- ```sh\n  make\n  ‸\n  ```\n")
    }

    func testReturnOnTheClosingFenceLeavesTheBlock() {
        XCTAssertEqual(afterReturn("```\ncode\n```‸\n"), "```\ncode\n```\n‸\n")
        // In a quote, the quote continues as usual.
        XCTAssertEqual(afterReturn("> ```\n> code\n> ```‸\n"), "> ```\n> code\n> ```\n> ‸\n")
    }

    func testReturnOutsideCodeStillContinuesLists() {
        XCTAssertEqual(afterReturn("- one‸"), "- one\n- ‸")
        XCTAssertEqual(afterReturn("> quote‸"), "> quote\n> ‸")
        XCTAssertEqual(afterReturn("    indented code‸"), "    indented code\n‸", "indented code blocks are left as before")
    }

    // MARK: - Closing the fence

    func testReturnAfterAnOpeningFenceClosesIt() {
        XCTAssertEqual(afterReturn("```‸"), "```\n‸\n```")
        XCTAssertEqual(afterReturn("Text\n\n```swift‸\n\nMore text\n"), "Text\n\n```swift\n‸\n```\n\nMore text\n")
        XCTAssertEqual(afterReturn("~~~~‸"), "~~~~\n‸\n~~~~")
        XCTAssertEqual(afterReturn("````md‸"), "````md\n‸\n````")
    }

    func testClosingInAQuoteAndAList() {
        XCTAssertEqual(afterReturn("> ```‸"), "> ```\n> ‸\n> ```")
        XCTAssertEqual(afterReturn("- ```js‸"), "- ```js\n  ‸\n  ```")
    }

    func testNoClosingFenceWhenTheBlockIsAlreadyClosed() {
        XCTAssertEqual(afterReturn("```swift‸\nlet a = 1\n```\n"), "```swift\n‸\nlet a = 1\n```\n")
        XCTAssertEqual(afterReturn("> ```‸\n> code\n> ```\n"), "> ```\n> ‸\n> code\n> ```\n")
    }

    func testAFenceIndentedTooFarDoesNotClose() {
        // Four spaces in, ``` is code, so the block is still open and Return closes it.
        XCTAssertEqual(afterReturn("```‸\n    ```\n"), "```\n‸\n```\n    ```\n")
        XCTAssertEqual(afterReturn("```‸\n   ```\n"), "```\n‸\n   ```\n", "three spaces in, it closes the block")
    }

    func testNewFenceAboveABlockPairsWithItsClosingFence() {
        // Known limit, kept deliberate: the new fence closes at the old block's opening fence,
        // so the parse sees it as closed and nothing is added.
        XCTAssertEqual(afterReturn("```‸\n\n```\nold\n```\n"), "```\n‸\n\n```\nold\n```\n")
    }

    // MARK: - Tab and Shift-Tab

    func testTabInsertsAnIndentAtTheCursor() {
        XCTAssertEqual(afterTab("```\nfoo‸bar\n```\n"), "```\nfoo    ‸bar\n```\n")
    }

    func testTabIndentsSelectedLinesAndKeepsThemSelected() {
        XCTAssertEqual(afterTab("```\n«a\nb»\n```\n"), "```\n«    a\n    b»\n```\n")
    }

    func testTabLeavesFencesAlone() {
        XCTAssertEqual(afterTab("«```\na\n```»\n"), "```\n«    a»\n```\n")
    }

    func testIndentFollowsTheBlock() {
        XCTAssertEqual(afterTab("```\n\tx\n«y»\n```\n"), "```\n\tx\n«\ty»\n```\n", "a block indented with tabs")
        XCTAssertEqual(afterTab("```\n  x\n«y»\n```\n"), "```\n  x\n«  y»\n```\n", "a block indented by 2")
    }

    func testOneSpaceIsAlignmentNotIndentation() {
        XCTAssertEqual(afterTab("```\nlist = [1,\n «2]»\n```\n"), "```\nlist = [1,\n«     2]»\n```\n")
    }

    func testIndentUsesTheLanguageDefaultInAnUnindentedBlock() {
        XCTAssertEqual(afterTab("```go\n«x»\n```\n"), "```go\n«\tx»\n```\n")
        XCTAssertEqual(afterTab("```yaml\n«x»\n```\n"), "```yaml\n«  x»\n```\n")
        XCTAssertEqual(afterTab("```rust\n«x»\n```\n"), "```rust\n«    x»\n```\n")
    }

    func testTabInAQuotedBlockGoesAfterTheMarker() {
        XCTAssertEqual(afterTab("> ```\n> «foo»\n> ```\n"), "> ```\n«>     foo»\n> ```\n")
        XCTAssertEqual(afterTab("> ```\n> ‸foo\n> ```\n"), "> ```\n>     ‸foo\n> ```\n")
    }

    func testShiftTabOutdents() {
        XCTAssertEqual(afterBacktab("```\n«        a\n    b»\n```\n"), "```\n«    a\nb»\n```\n")
        XCTAssertEqual(afterBacktab("```\n  a‸\n```\n"), "```\na‸\n```\n", "fewer spaces than a unit")
        XCTAssertEqual(afterBacktab("```go\n\t\tx‸\n```\n"), "```go\n\tx‸\n```\n")
        XCTAssertEqual(afterBacktab("> ```\n>     a‸\n> ```\n"), "> ```\n> a‸\n> ```\n")
    }

    func testShiftTabOnAnUnindentedLineChangesNothing() {
        XCTAssertEqual(afterBacktab("```\na‸\n```\n"), "```\na‸\n```\n")
    }

    func testListLooksInsideCodeAreCode() {
        // Today's list indentation used to kick in for these.
        XCTAssertEqual(afterTab("```yaml\n«- item»\n```\n"), "```yaml\n«  - item»\n```\n")
        XCTAssertEqual(afterTab("```c\n/**\n« * doc»\n */\n```\n"), "```c\n/**\n«     * doc»\n */\n```\n")
    }

    func testSelectionReachingOutsideTheBlockFallsBack() {
        // A list item and a code line together: the list behavior applies, code lines are left alone.
        let textView = editor("- «item\n\n```\ncode»\n```\n")
        textView.insertTab(nil)
        XCTAssertEqual(textView.string, "    - item\n\n```\ncode\n```\n")
    }

    func testFormatMenuIndentWorksInCode() {
        let textView = editor("```\nfoo‸\n```\n")
        textView.indentList(nil)
        XCTAssertEqual(marked(textView), "```\n    foo‸\n```\n")
        textView.outdentList(nil)
        XCTAssertEqual(marked(textView), "```\nfoo‸\n```\n")
    }

    // MARK: - Undo

    private func inWindow(_ textView: MarkdownTextView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = textView
        textView.allowsUndo = true
        return window
    }

    func testEachActionIsOneUndoStep() throws {
        for (text, action) in [("```\n«a\nb»\n```\n", { (view: MarkdownTextView) in view.insertTab(nil) }),
                               ("```\n    a‸\n```\n", { (view: MarkdownTextView) in view.insertBacktab(nil) }),
                               ("```swift‸", { (view: MarkdownTextView) in view.insertNewline(nil) }),
                               ("```\n    a‸\n```\n", { (view: MarkdownTextView) in view.insertNewline(nil) })] {
            let textView = editor(text)
            let window = inWindow(textView)
            defer { window.close() }
            let before = textView.string
            let undoManager = try XCTUnwrap(textView.undoManager)
            undoManager.beginUndoGrouping()
            action(textView)
            undoManager.endUndoGrouping()
            XCTAssertNotEqual(textView.string, before, text)
            undoManager.undo()
            XCTAssertEqual(textView.string, before, "one Undo puts back \(text)")
        }
    }

    // MARK: - In the app's editor

    func testUsesTheEditorsBlockListWhenThereIsOne() {
        let textView = editor("Intro\n\n```py\nif x:\n    y = 1‸\n```\n\n- list\n")
        let styler = LiveStyler(storage: textView.textStorage!, settings: .init(theme: .midnight, baseURL: nil, availableWidth: 600))
        styler.restyleAll(caret: 0)
        textView.topLevelBlocks = { styler.blocks }
        textView.insertNewline(nil)
        XCTAssertEqual(marked(textView), "Intro\n\n```py\nif x:\n    y = 1\n    ‸\n```\n\n- list\n")
    }

    func testFindsTheBlockAndItsPrefix() throws {
        let text = "> - ```swift title\n>   let a = 1\n>   ```\n" as NSString
        let block = try XCTUnwrap(FencedCodeBlock.find(in: text, at: 20, region: NSRange(location: 0, length: text.length)))
        XCTAssertEqual(block.prefix, ">   ")
        XCTAssertEqual(block.fence, "```")
        XCTAssertEqual(block.language, "swift")
        XCTAssertEqual(block.body.map { text.substring(with: $0) }, [">   let a = 1"])
        XCTAssertEqual(block.closing.map { text.substring(with: $0) }, ">   ```")
        XCTAssertNil(FencedCodeBlock.find(in: "    indented\n" as NSString, at: 4, region: NSRange(location: 0, length: 13)))
    }
}
