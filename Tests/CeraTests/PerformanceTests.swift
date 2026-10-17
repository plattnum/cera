import AppKit
import Markdown
import XCTest
@testable import Cera

/// Measures styling speed on large documents built by repeating a file.
/// Run in release mode: CERA_PERF_FILE=doc.md swift test -c release --filter PerformanceTests
final class PerformanceTests: XCTestCase {
    func testMeasure() throws {
        guard let path = ProcessInfo.processInfo.environment["CERA_PERF_FILE"] else { throw XCTSkip("Set CERA_PERF_FILE.") }
        let unit = try String(contentsOfFile: path, encoding: .utf8)
        for copies in [100, 1000] {
            let source = Array(repeating: unit, count: copies).joined(separator: "\n\n")
            let mb = Double(source.utf8.count) / 1_048_576
            let storage = NSTextStorage(string: source)
            let styler = LiveStyler(storage: storage, settings: .init(theme: .midnight, baseURL: nil, availableWidth: 760))

            var start = Date()
            styler.restyleAll(caret: 0)
            let open = Date().timeIntervalSince(start)
            start = Date()
            styler.finishBackgroundStyling(caret: 0)
            let background = Date().timeIntervalSince(start)

            // Type a character in a paragraph in the middle of the document.
            let middle = (source as NSString).range(of: "Readability, however", options: [], range: NSRange(location: storage.length / 2, length: storage.length / 2)).location
            start = Date()
            storage.replaceCharacters(in: NSRange(location: middle, length: 0), with: "x")
            styler.textChanged(editedRange: NSRange(location: middle, length: 1), delta: 1, caret: middle + 1, previousLine: middle)
            let keystroke = Date().timeIntervalSince(start)

            start = Date()
            storage.replaceCharacters(in: NSRange(location: middle + 1, length: 0), with: "\n")
            styler.textChanged(editedRange: NSRange(location: middle + 1, length: 1), delta: 1, caret: middle + 2, previousLine: middle)
            let newline = Date().timeIntervalSince(start)

            start = Date()
            styler.caretMoved(fromLineAt: middle + 2, toLineAt: middle - 200, caret: middle - 200)
            let caret = Date().timeIntervalSince(start)

            print(String(format: "PERF %5.1f MB  open (visible part) %.2fs  rest in background %.2fs  keystroke %.1fms  return %.1fms  caret move %.1fms",
                         mb, open, background, keystroke * 1000, newline * 1000, caret * 1000))
        }
    }

    /// Code highlighting on a code-heavy document (scripts/make-large-docs.sh writes
    /// TestDocuments/large-code.md). Run with CERA_PERF_CODE=<file> in release mode.
    func testMeasureCode() throws {
        guard let path = ProcessInfo.processInfo.environment["CERA_PERF_CODE"] else { throw XCTSkip("Set CERA_PERF_CODE.") }
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let storage = NSTextStorage(string: source)
        let styler = LiveStyler(storage: storage, settings: .init(theme: .midnight, baseURL: nil, availableWidth: 760))
        func time(_ work: () -> Void) -> Double { let start = Date(); work(); return Date().timeIntervalSince(start) * 1000 }
        func type(at location: Int) -> Double {
            time {
                storage.replaceCharacters(in: NSRange(location: location, length: 0), with: "x")
                styler.textChanged(editedRange: NSRange(location: location, length: 1), delta: 1, caret: location + 1, previousLine: location)
            }
        }
        func location(of marker: String, from: Int = 0) -> Int {
            (storage.string as NSString).range(of: marker, options: [], range: NSRange(location: from, length: storage.length - from)).location
        }

        let open = time { styler.restyleAll(caret: 0) }
        let background = time { styler.finishBackgroundStyling(caret: 0) }
        let middle = storage.length / 3
        let small = type(at: location(of: "        if let cached", from: middle) + 8)
        let bigBlock = location(of: "A paragraph before big block 3.")
        let inBig = type(at: location(of: "    return value * 120", from: bigBlock) + 4)
        let nextToBig = type(at: location(of: "A paragraph before big block 4.") + 2)
        let line = location(of: "def step_130", from: bigBlock)
        let caret = time { styler.caretMoved(fromLineAt: line, toLineAt: location(of: "def step_131", from: line), caret: line + 80) }
        let giant = type(at: location(of: "    return value * 2000", from: location(of: "the giant block")) + 4)

        print(String(format: "CODE %.1f MB: open %.0f ms, background %.0f ms, keystroke in a small block %.1f ms, "
                     + "in a 500-line block %.1f ms, next to a big block %.1f ms, caret move in a big block %.1f ms, "
                     + "in the 5,000-line block %.1f ms", Double(source.utf8.count) / 1_048_576,
                     open, background, small, inBig, nextToBig, caret, giant))
    }

    /// Finding the outline's headings, and jumping to one far down.
    @MainActor
    func testMeasureOutline() throws {
        guard let path = ProcessInfo.processInfo.environment["CERA_PERF_FILE"] else { throw XCTSkip("Set CERA_PERF_FILE.") }
        let unit = try String(contentsOfFile: path, encoding: .utf8)
        for copies in [100, 1000] {
            let source = Array(repeating: unit, count: copies).joined(separator: "\n\n")
            let mb = Double(source.utf8.count) / 1_048_576
            var start = Date()
            let items = Outline.items(in: source)
            let parse = Date().timeIntervalSince(start)

            let (scrollView, textView) = MarkdownEditor.makeScrollView()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = scrollView
            textView.string = source
            let styler = LiveStyler(storage: textView.textStorage!, settings: .init(theme: .midnight, baseURL: nil, availableWidth: 760))
            styler.restyleAll(caret: 0)
            styler.finishBackgroundStyling(caret: 0)
            let model = OutlineModel()
            model.textView = textView
            model.update(text: source, immediately: true)

            start = Date()
            model.jump(to: items.count / 2)
            let middle = Date().timeIntervalSince(start)
            start = Date()
            model.jump(to: items.count - 1)
            let last = Date().timeIntervalSince(start)
            start = Date()
            for _ in 0..<100 { model.visibleAreaChanged() }
            let current = Date().timeIntervalSince(start) / 100

            print(String(format: "PERF %5.1f MB  %d headings: find %.0fms  jump to middle %.0fms  then to last %.0fms  current section %.2fms",
                         mb, items.count, parse * 1000, middle * 1000, last * 1000, current * 1000))
        }
    }
}
