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
}
