import AppKit
import SwiftUI
import XCTest
@testable import Cera

/// Renders the app window to PNGs so the styling can be checked by eye.
///
///     CERA_RENDER_DIR=/some/dir [CERA_RENDER_FILE=doc.md] [CERA_RENDER_HEIGHT=5000] [CERA_RENDER_THEMES=midnight,plain]
///         [CERA_RENDER_OUTLINE=1] swift test --filter RenderPreviewTests
///
/// Writes one `window-<theme>.png` per theme.
final class RenderPreviewTests: XCTestCase {

    private static let sample = """
    Sample Document
    ===============

    A paragraph with **bold**, *italic*, ~~struck~~, `inline code`, and a [link](https://example.com).

    | Feature | Status | Notes |
    |:--------|:------:|------:|
    | Tables | **done** | right-aligned |
    | Images | done | `local` files |
    | Lists | done | nested too |

    ![diagram](sample-image.png)

    - first item
    - second item
      - nested item
        - deeper item

    1. one
    2. two

    - [ ] a task
    - [x] a finished task

    > A quote.
    >
    > > A nested quote.

    ---

    ```bash
    # comment
    pnpm install "quoted" 42
    ```

    Last line.
    """

    func testWriteWindowImages() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["CERA_RENDER_DIR"] else {
            throw XCTSkip("Set CERA_RENDER_DIR to write preview PNGs.")
        }
        let file: URL
        if let path = env["CERA_RENDER_FILE"] {
            file = URL(fileURLWithPath: path)
        } else {
            file = URL(fileURLWithPath: directory).appendingPathComponent("sample.md")
            try Self.sample.write(to: file, atomically: true, encoding: .utf8)
            try Self.writeSampleImage(to: URL(fileURLWithPath: directory).appendingPathComponent("sample-image.png"))
        }

        let previous = UserDefaults.standard.string(forKey: "theme")
        let previousOutline = UserDefaults.standard.object(forKey: "showsOutline")
        defer {
            UserDefaults.standard.set(previous, forKey: "theme")
            UserDefaults.standard.set(previousOutline, forKey: "showsOutline")
        }
        UserDefaults.standard.set(env["CERA_RENDER_OUTLINE"] == "1", forKey: "showsOutline")

        let height = env["CERA_RENDER_HEIGHT"].flatMap(Double.init) ?? 1300
        let themes = env["CERA_RENDER_THEMES"].map { $0.split(separator: ",").compactMap { ThemeChoice(rawValue: String($0)) } }
            ?? ThemeChoice.allCases
        for choice in themes {
            UserDefaults.standard.set(choice.rawValue, forKey: "theme")
            let output = URL(fileURLWithPath: directory).appendingPathComponent("window-\(choice.rawValue).png")
            try renderWindow(file: file, height: height, to: output)
        }
    }

    /// A simple gradient picture for the sample's image.
    private static func writeSampleImage(to url: URL) throws {
        let image = NSImage(size: NSSize(width: 480, height: 160), flipped: false) { rect in
            NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: rect, angle: 0)
            NSAttributedString(string: "sample-image.png", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.white
            ]).draw(at: NSPoint(x: 24, y: 64))
            return true
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])).write(to: url)
    }

    private func renderWindow(file: URL, height: Double, to output: URL) throws {
        let document = MarkdownDocument(text: try String(contentsOf: file, encoding: .utf8))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 950, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = file.lastPathComponent
        window.representedURL = file
        window.contentViewController = NSHostingController(rootView: ContentView(document: document, fileURL: file))
        window.setContentSize(NSSize(width: 950, height: height))
        window.layoutIfNeeded()
        // Let SwiftUI and the text system finish their passes.
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        let frameView = try XCTUnwrap(window.contentView?.superview)
        let bitmap = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output)
        window.close()
    }
}
