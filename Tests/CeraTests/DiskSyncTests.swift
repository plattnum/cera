import AppKit
import XCTest
@testable import Cera

final class DiskSyncTests: XCTestCase {

    // MARK: - Smallest change

    func testFindsTheChangedMiddle() {
        let change = TextChange(from: "one two three", to: "one 2 three")
        XCTAssertEqual(change.range, NSRange(location: 4, length: 3))
        XCTAssertEqual(change.replacement, "2")
    }

    func testRepeatedCharactersDoNotOverlap() {
        let change = TextChange(from: "aa", to: "aaa")
        XCTAssertEqual(change.range, NSRange(location: 2, length: 0))
        XCTAssertEqual(change.replacement, "a")
    }

    func testIdenticalTextIsNoChange() {
        let change = TextChange(from: "same", to: "same")
        XCTAssertEqual(change.range, NSRange(location: 4, length: 0))
        XCTAssertEqual(change.replacement, "")
    }

    func testDoesNotSplitAnEmoji() {
        // 😀 and 😃 share their first UTF-16 unit; the change must cover the whole character.
        let change = TextChange(from: "a😀b", to: "a😃b")
        XCTAssertEqual(change.range, NSRange(location: 1, length: 2))
        XCTAssertEqual(change.replacement, "😃")
    }

    // MARK: - Replacing the editor's text

    /// An editor in a window, so it has an undo manager like the real one.
    private func editor(_ text: String) -> MarkdownTextView {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        addTeardownBlock { window.close() }
        textView.string = text
        return textView
    }

    func testReplacingTextKeepsCaretBeforeTheChange() {
        let textView = editor("first line\nsecond line\nthird line")
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.replaceText(with: "first line\nSECOND\nthird line")
        XCTAssertEqual(textView.string, "first line\nSECOND\nthird line")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testReplacingTextShiftsCaretAfterTheChange() {
        let textView = editor("first line\nsecond line\nthird line")
        let caret = ("first line\nsecond line\nthird" as NSString).length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.replaceText(with: "first line\nSECOND\nthird line")
        XCTAssertEqual(textView.selectedRange().location, caret - 5) // "second line" became "SECOND"
    }

    func testReplacingTextIsNotUndoable() throws {
        let textView = editor("old")
        let undo = try XCTUnwrap(textView.undoManager)
        undo.removeAllActions()
        textView.replaceText(with: "new")
        XCTAssertEqual(textView.string, "new")
        XCTAssertFalse(undo.canUndo)
    }

    // MARK: - What to do about a change on disk

    func testOwnSaveIsIgnored() {
        XCTAssertEqual(DiskChange.action(disk: "same", editor: "same", hasUnsavedEdits: false), .ignore)
        XCTAssertEqual(DiskChange.action(disk: "same", editor: "same", hasUnsavedEdits: true), .ignore)
    }

    func testChangeWithoutUnsavedEditsReloads() {
        XCTAssertEqual(DiskChange.action(disk: "theirs", editor: "mine", hasUnsavedEdits: false), .reload)
    }

    func testChangeWithUnsavedEditsAsks() {
        XCTAssertEqual(DiskChange.action(disk: "theirs", editor: "mine", hasUnsavedEdits: true), .ask)
    }

    // MARK: - Watching the file

    private func temporaryFile(_ contents: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("note.md")
        try contents.write(to: file, atomically: false, encoding: .utf8)
        return file
    }

    func testWatcherSeesAnInPlaceWrite() throws {
        let file = try temporaryFile("one")
        let changed = expectation(description: "change reported")
        changed.assertForOverFulfill = false
        let watcher = FileWatcher(url: file) { changed.fulfill() }
        defer { watcher.stop() }

        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("two".utf8))
        try handle.close()
        wait(for: [changed], timeout: 5)
    }

    func testWatcherSeesAnAtomicReplace() throws {
        let file = try temporaryFile("one")
        let changed = expectation(description: "change reported")
        changed.assertForOverFulfill = false
        let watcher = FileWatcher(url: file) { changed.fulfill() }
        defer { watcher.stop() }

        try "two".write(to: file, atomically: true, encoding: .utf8)
        wait(for: [changed], timeout: 5)
    }

    func testWatcherKeepsWatchingAfterAnAtomicReplace() throws {
        let file = try temporaryFile("one")
        var count = 0
        let second = expectation(description: "second change reported")
        let watcher = FileWatcher(url: file) {
            count += 1
            if count == 2 { second.fulfill() }
        }
        defer { watcher.stop() }

        try "two".write(to: file, atomically: true, encoding: .utf8)
        let deadline = Date().addingTimeInterval(5)
        while count < 1, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        try "three".write(to: file, atomically: true, encoding: .utf8)
        wait(for: [second], timeout: 5)
    }

    func testWatcherIsQuietAfterStop() throws {
        let file = try temporaryFile("one")
        let changed = expectation(description: "no change reported")
        changed.isInverted = true
        let watcher = FileWatcher(url: file) { changed.fulfill() }
        watcher.stop()

        try "two".write(to: file, atomically: true, encoding: .utf8)
        wait(for: [changed], timeout: 1.5)
    }

    func testReadsTextAndModificationDate() throws {
        let file = try temporaryFile("hello")
        let contents = try XCTUnwrap(FileWatcher.read(file))
        XCTAssertEqual(contents.text, "hello")
        let date = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        XCTAssertEqual(contents.modified, date)
    }
}

final class KeepScrollPositionTests: XCTestCase {
    private var window: NSWindow!
    private var textView: MarkdownTextView!
    private let theme = Theme.midnight

    override func setUp() {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        self.textView = textView
        textView.string = Self.document(firstLine: "Line 4 of the document.")
        restyle()
    }

    override func tearDown() {
        window.close()
    }

    private static func document(firstLine line4: String, extraTop: String = "") -> String {
        var lines = ["# Live doc", "", "## Section", ""]
        for i in 1...200 { lines.append(i == 4 ? line4 : "Line \(i) of the document.") }
        return extraTop + lines.joined(separator: "\n") + "\n"
    }

    private func restyle() {
        MarkdownStyler(theme: theme).style(textView.textStorage!, caret: 0, availableWidth: 600)
    }

    /// The first character in view, measured on a complete layout.
    private var firstVisibleCharacter: Int {
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        let y = textView.visibleRect.minY - textView.textContainerOrigin.y
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: max(0, y) + 1), in: textView.textContainer!)
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    private func scroll(toLine line: Int) {
        let index = (textView.string as NSString).range(of: "Line \(line) of").location
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        let rect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index), effectiveRange: nil)
        textView.scroll(NSPoint(x: 0, y: rect.minY + textView.textContainerOrigin.y))
    }

    func testChangeAboveTheViewKeepsTheSameTextInView() {
        scroll(toLine: 120)
        let before = firstVisibleCharacter
        textView.replaceTextKeepingPosition(with: Self.document(firstLine: "Line four, reloaded, of the document.")) { restyle() }
        XCTAssertEqual(firstVisibleCharacter, before + 14)
    }

    func testLinesAddedAboveTheViewKeepTheSameTextInView() {
        scroll(toLine: 120)
        let before = firstVisibleCharacter
        let added = "New paragraph one.\n\nNew paragraph two.\n\n"
        textView.replaceTextKeepingPosition(with: Self.document(firstLine: "Line 4 of the document.", extraTop: added)) { restyle() }
        XCTAssertEqual(firstVisibleCharacter, before + (added as NSString).length)
    }

    func testChangeBelowTheViewLeavesTheViewAlone() {
        scroll(toLine: 120)
        let before = firstVisibleCharacter
        let text = Self.document(firstLine: "Line 4 of the document.").replacingOccurrences(of: "Line 190 of", with: "Line 190, longer now, of")
        textView.replaceTextKeepingPosition(with: text) { restyle() }
        XCTAssertEqual(firstVisibleCharacter, before)
    }

    func testAtTheTopNewTextAtTheTopIsShown() {
        textView.scroll(.zero)
        textView.replaceTextKeepingPosition(with: Self.document(firstLine: "Line 4 of the document.", extraTop: "Intro.\n\n")) { restyle() }
        XCTAssertEqual(firstVisibleCharacter, 0)
    }
}
