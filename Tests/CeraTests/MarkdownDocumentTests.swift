import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Cera

final class MarkdownDocumentTests: XCTestCase {
    func testSnapshotWritesUTF8() throws {
        let document = MarkdownDocument(text: "# Café ☕️\n")
        let snapshot = try document.snapshot(contentType: .markdown)
        XCTAssertEqual(snapshot, "# Café ☕️\n")
        XCTAssertEqual(Data(snapshot.utf8), "# Café ☕️\n".data(using: .utf8))
    }

    func testMarkdownTypeMatchesFileExtensions() {
        XCTAssertEqual(UTType.markdown.identifier, "net.daringfireball.markdown")
        XCTAssertTrue(UTType.markdown.conforms(to: .plainText))
        XCTAssertEqual(MarkdownDocument.writableContentTypes.first, .markdown, "new documents save as Markdown")
    }

    /// Typing must register undo on the document's undo manager: that is what marks the
    /// document as edited, so the title bar shows "Edited" and autosave runs.
    func testEditsRegisterUndoOnTheDocument() throws {
        let documentUndo = UndoManager()
        let editor = MarkdownEditor(text: .constant(""), theme: .midnight, undoManager: documentUndo)
        let coordinator = editor.makeCoordinator()
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = scrollView
        textView.delegate = coordinator
        coordinator.textView = textView

        XCTAssertTrue(textView.undoManager === documentUndo)
        textView.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertTrue(documentUndo.canUndo)
    }
}
