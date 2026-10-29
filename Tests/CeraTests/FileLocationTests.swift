import AppKit
import XCTest
@testable import Cera

/// The open file's name and path: what the status bar shows, and what Copy Name and Copy Path put on the clipboard.
final class FileLocationTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/Users/me/Notes/My Notes/plan v2.md")
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("cera-tests-\(UUID().uuidString)"))
    }

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    func testNameIsTheFileNameWithItsExtension() {
        XCTAssertEqual(FileLocation.name(of: file), "plan v2.md")
    }

    func testAnUnsavedDocumentIsUntitled() {
        XCTAssertEqual(FileLocation.name(of: nil), "Untitled")
        XCTAssertNil(FileLocation.path(of: nil))
    }

    func testPathIsTheFullPathWithSpacesAsTheyAre() {
        XCTAssertEqual(FileLocation.path(of: file), "/Users/me/Notes/My Notes/plan v2.md")
    }

    func testPathIsntPercentEncoded() {
        let url = URL(fileURLWithPath: "/tmp/Übersicht & Pläne/réunion #3.md")
        XCTAssertEqual(FileLocation.path(of: url), "/tmp/Übersicht & Pläne/réunion #3.md")
    }

    func testCopyNamePutsTheNameOnTheClipboard() {
        FileLocation.copyName(of: file, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "plan v2.md")
    }

    func testCopyPathPutsTheFullPathOnTheClipboard() {
        FileLocation.copyPath(of: file, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "/Users/me/Notes/My Notes/plan v2.md")
    }

    func testCopyingReplacesWhatWasOnTheClipboard() {
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        pasteboard.setData(Data([1, 2, 3]), forType: .tiff)
        FileLocation.copyPath(of: file, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "/Users/me/Notes/My Notes/plan v2.md")
        XCTAssertNil(pasteboard.data(forType: .tiff), "only the path is on the clipboard")
    }
}
