import AppKit
import XCTest
@testable import Cera

/// The language list after ``` and the language label in a code panel's corner.
final class CodeLanguagePickerTests: XCTestCase {

    private func editor(_ text: String, caret: Int? = nil) -> MarkdownTextView {
        let textView = MarkdownTextView.makeEditor(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.string = text
        textView.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        return textView
    }

    // MARK: - Candidates

    func testEverythingIsOfferedBeforeALetterIsTyped() {
        XCTAssertEqual(CodeLanguagePicker.candidates(for: ""), CodeLanguagePicker.names)
        XCTAssertTrue(CodeLanguagePicker.names.contains("mermaid"))
        XCTAssertTrue(CodeLanguagePicker.names.contains("csharp"))
    }

    func testAliasesFindTheirLanguageFirst() {
        XCTAssertEqual(CodeLanguagePicker.candidates(for: "py").first, "python")
        XCTAssertEqual(CodeLanguagePicker.candidates(for: "js").first, "javascript")
        XCTAssertEqual(CodeLanguagePicker.candidates(for: "c#").first, "csharp")
        XCTAssertEqual(CodeLanguagePicker.candidates(for: "c").first, "c", "an exact name before longer ones")
        XCTAssertEqual(CodeLanguagePicker.candidates(for: "Sw"), ["swift"])
        XCTAssertEqual(CodeLanguagePicker.candidates(for: "zzz"), [])
    }

    // MARK: - Where it's offered

    func testOfferedAtTheEndOfAnOpeningFence() {
        let text = "Intro\n\n```py" as NSString
        XCTAssertEqual(editor(text as String).fenceLanguageRange(), NSRange(location: 10, length: 2))
        XCTAssertEqual(editor("```").fenceLanguageRange(), NSRange(location: 3, length: 0))
        XCTAssertEqual(editor("> ```").fenceLanguageRange(), NSRange(location: 5, length: 0))
        XCTAssertEqual(editor("- ~~~").fenceLanguageRange(), NSRange(location: 5, length: 0))
    }

    func testNotOfferedElsewhere() {
        XCTAssertNil(editor("```py", caret: 4).fenceLanguageRange(), "cursor inside the name")
        XCTAssertNil(editor("``").fenceLanguageRange(), "not a fence yet")
        XCTAssertNil(editor("```python title").fenceLanguageRange(), "past the name")
        XCTAssertNil(editor("```\ncode\n```").fenceLanguageRange(), "typing a closing fence")
        XCTAssertNil(editor("    ```").fenceLanguageRange(), "inside an indented code block")
        XCTAssertNil(editor("text ```").fenceLanguageRange(), "inline backticks")
    }

    // MARK: - Choosing

    func testArrowingThroughTheListLeavesTheTextAlone() {
        let textView = editor("```")
        let range = NSRange(location: 3, length: 0)
        textView.insertCompletion("bash", forPartialWordRange: range, movement: NSDownTextMovement, isFinal: false)
        XCTAssertEqual(textView.string, "```")
    }

    func testReturnInsertsTheNameAndOpensTheBlock() {
        let textView = editor("```py")
        textView.insertCompletion("python", forPartialWordRange: NSRange(location: 3, length: 2), movement: NSReturnTextMovement, isFinal: true)
        XCTAssertEqual(textView.string, "```python\n\n```")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 10, length: 0), "on the empty line between the fences")
    }

    func testTabInsertsTheNameOnly() {
        let textView = editor("```sw")
        textView.insertCompletion("swift", forPartialWordRange: NSRange(location: 3, length: 2), movement: NSTabTextMovement, isFinal: true)
        XCTAssertEqual(textView.string, "```swift")
    }

    func testEscapeKeepsWhatWasTyped() {
        let textView = editor("```py")
        textView.insertCompletion("python", forPartialWordRange: NSRange(location: 3, length: 2), movement: NSCancelTextMovement, isFinal: true)
        XCTAssertEqual(textView.string, "```py")
    }

    func testCompletionsElsewhereAreTheSystems() {
        let textView = editor("Some words")
        var index = 0
        // Not a fence: the text view's own word completion answers, whatever it offers.
        _ = textView.completions(forPartialWordRange: NSRange(location: 5, length: 5), indexOfSelectedItem: &index)
        XCTAssertNotEqual(textView.rangeForUserCompletion, NSRange(location: 10, length: 0))
    }

    func testNothingIsPreselectedUntilALetterIsTyped() {
        var index = 99
        XCTAssertEqual(editor("```").completions(forPartialWordRange: NSRange(location: 3, length: 0), indexOfSelectedItem: &index),
                       CodeLanguagePicker.names)
        XCTAssertEqual(index, -1)
        XCTAssertEqual(editor("```ru").completions(forPartialWordRange: NSRange(location: 3, length: 2), indexOfSelectedItem: &index),
                       ["ruby", "rust"])
        XCTAssertEqual(index, 0)
    }

    // MARK: - The label

    private func label(in text: String, caret: Int = 0) -> String? {
        let storage = NSTextStorage(string: text)
        MarkdownStyler(theme: .midnight).style(storage, caret: caret, availableWidth: 600)
        var found: String?
        storage.enumerateAttribute(.codeLanguage, in: NSRange(location: 0, length: storage.length)) { value, _, stop in
            if let value = value as? String { found = value; stop.pointee = true }
        }
        return found
    }

    func testLabelShowsTheLanguageAsWritten() {
        XCTAssertEqual(label(in: "Intro\n\n```py title\nx = 1\n```\n"), "py")
        XCTAssertEqual(label(in: "Intro\n\n> ```swift\n> let a = 1\n> ```\n"), "swift")
        XCTAssertEqual(label(in: "Intro\n\n```unknownlang\nx\n```\n"), "unknownlang")
    }

    func testNoLabelWithoutALanguageOrWhileItsFenceIsEdited() {
        XCTAssertNil(label(in: "Intro\n\n```\nx\n```\n"))
        XCTAssertNil(label(in: "Intro\n\n    indented code\n"))
        XCTAssertNil(label(in: "Intro\n\n```py\nx = 1\n```\n", caret: 8), "the fence line shows the language itself")
        XCTAssertEqual(label(in: "Intro\n\n```py\nx = 1\n```\n", caret: 13), "py", "editing the code keeps the label")
    }

    func testNoLabelOnADrawnDiagram() {
        XCTAssertNil(label(in: "Intro\n\n```mermaid\nflowchart LR\n  A --> B\n```\n"))
    }

    func testLabelSitsInTheCopyButtonsCorner() {
        let panel = NSRect(x: 0, y: 100, width: 500, height: 80)
        let rect = MarkdownLayoutManager.languageLabelRect(for: "swift", in: panel)
        XCTAssertEqual(rect.maxX, panel.maxX - 6, accuracy: 0.5, "right-aligned with the button")
        XCTAssertEqual(rect.midY, panel.minY + 6 + CodeCopyButton.size.height / 2, accuracy: 0.5, "centered on it")
    }
}
