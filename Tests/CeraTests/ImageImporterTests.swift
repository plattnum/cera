import AppKit
import XCTest
@testable import Cera

final class ImageImporterTests: XCTestCase {
    private var root: URL!
    private var documentFolder: URL!
    private var elsewhere: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cera-\(UUID().uuidString)")
        documentFolder = root.appendingPathComponent("docs")
        elsewhere = root.appendingPathComponent("Downloads")
        for folder in [documentFolder!, elsewhere!, documentFolder.appendingPathComponent("pics")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeImage(at url: URL) throws {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.blue.setFill(); rect.fill(); return true
        }
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
            .representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    func testImageInsideDocumentFolderIsLinkedRelatively() throws {
        let file = documentFolder.appendingPathComponent("pics/chart.png")
        try makeImage(at: file)
        let path = try ImageImporter(documentFolder: documentFolder).reference(for: file)
        XCTAssertEqual(path, "pics/chart.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: documentFolder.appendingPathComponent("assets").path))
    }

    func testImageElsewhereIsCopiedIntoAssets() throws {
        let file = elsewhere.appendingPathComponent("photo.png")
        try makeImage(at: file)
        let path = try ImageImporter(documentFolder: documentFolder).reference(for: file)
        XCTAssertEqual(path, "assets/photo.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: documentFolder.appendingPathComponent("assets/photo.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the original stays where it was")
    }

    func testNameClashGetsANumber() throws {
        let file = elsewhere.appendingPathComponent("photo.png")
        try makeImage(at: file)
        let importer = ImageImporter(documentFolder: documentFolder)
        XCTAssertEqual(try importer.reference(for: file), "assets/photo.png")
        XCTAssertEqual(try importer.reference(for: file), "assets/photo-1.png")
    }

    func testSpacesAreEncoded() throws {
        let file = elsewhere.appendingPathComponent("Screen Shot 1.png")
        try makeImage(at: file)
        let path = try ImageImporter(documentFolder: documentFolder).reference(for: file)
        XCTAssertEqual(path, "assets/Screen%20Shot%201.png")
        XCTAssertEqual(ImageImporter.markdown(for: path), "![Screen Shot 1](assets/Screen%20Shot%201.png)")
    }

    func testUntitledDocumentLinksAbsolutePath() throws {
        let file = elsewhere.appendingPathComponent("photo.png")
        try makeImage(at: file)
        let path = try ImageImporter(documentFolder: nil).reference(for: file)
        XCTAssertTrue(path.hasPrefix("/"))
        XCTAssertTrue(path.hasSuffix("/Downloads/photo.png"))
    }

    func testPastedImageIsSavedAsPNG() throws {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let date = Date(timeIntervalSince1970: 0)
        let path = try ImageImporter(documentFolder: documentFolder).reference(forPasted: image, date: date)
        XCTAssertTrue(path.hasPrefix("assets/pasted-image-"))
        XCTAssertTrue(path.hasSuffix(".png"))
        XCTAssertNotNil(NSImage(contentsOf: documentFolder.appendingPathComponent(path)))
    }

    func testPastedImageNeedsASavedDocument() {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        XCTAssertThrowsError(try ImageImporter(documentFolder: nil).reference(forPasted: image))
    }

    func testInsertedReferenceRendersAsImage() throws {
        let file = elsewhere.appendingPathComponent("render me.png")
        try makeImage(at: file)
        let path = try ImageImporter(documentFolder: documentFolder).reference(for: file)
        let source = ImageImporter.markdown(for: path) + "\n\nlast"
        let storage = NSTextStorage(string: source)
        MarkdownStyler(theme: .midnight).style(storage, caret: (source as NSString).length, baseURL: documentFolder)
        XCTAssertNotNil(storage.attribute(.imageBlock, at: 0, effectiveRange: nil) as? ImageBlock)
    }
}
