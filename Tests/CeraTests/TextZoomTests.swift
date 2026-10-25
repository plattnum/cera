import AppKit
import XCTest
@testable import Cera

/// View ▸ Zoom In, Zoom Out, Actual Size: the editor's scroll view is magnified, as a browser zooms a page.
final class TextZoomTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() {
        window?.close()
    }

    // MARK: Levels

    func testZoomInAndOutStepThroughTheLevelsAndStopAtTheEnds() {
        XCTAssertEqual(TextZoom.zoomedIn(from: 1), 1.15)
        XCTAssertEqual(TextZoom.zoomedOut(from: 1), 0.85)
        XCTAssertEqual(TextZoom.zoomedIn(from: 2.5), 3)
        XCTAssertNil(TextZoom.zoomedIn(from: 3))
        XCTAssertNil(TextZoom.zoomedOut(from: 0.5))
        // A level between steps, from defaults edited by hand, goes to the next step.
        XCTAssertEqual(TextZoom.zoomedIn(from: 1.1), 1.15)
        XCTAssertEqual(TextZoom.zoomedOut(from: 1.1), 1)
    }

    func testStoredLevelIsKeptInRange() {
        XCTAssertEqual(TextZoom.clamped(10), 3)
        XCTAssertEqual(TextZoom.clamped(0.1), 0.5)
        XCTAssertEqual(TextZoom.clamped(.nan), 1)
        XCTAssertEqual(TextZoom.clamped(1.25), 1.25)
    }

    // MARK: A magnified editor

    /// An editor in a window, as in the app, magnified by `zoom`, with `text` styled and laid out.
    private func editor(_ text: String, zoom: Double) -> (NSScrollView, MarkdownTextView) {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        self.window = window
        scrollView.magnification = zoom
        scrollView.layoutSubtreeIfNeeded()
        textView.apply(.ivory)
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        MarkdownStyler(theme: .ivory).style(textView.textStorage!, caret: (text as NSString).length)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        return (scrollView, textView)
    }

    func testMagnifiedTextLaysOutInANarrowerWidth() {
        let (actual, actualText) = editor("Some text", zoom: 1)
        let actualWidth = actualText.frame.width
        actual.window?.close()
        let (_, zoomedText) = editor("Some text", zoom: 1.5)
        XCTAssertEqual(zoomedText.frame.width, actualWidth / 1.5, accuracy: 1, "like a browser, the page is narrower in text points")
    }

    func testClickingACheckboxWorksWhenZoomed() throws {
        // AppKit converts the click through the magnification, so hit testing needs nothing.
        let (_, textView) = editor("- [ ] open\n\nlast", zoom: 1.5)
        let manager = textView.layoutManager as! MarkdownLayoutManager
        let box = manager.checkboxRect(at: 0)
        let inView = NSPoint(x: box.midX + textView.textContainerOrigin.x, y: box.midY + textView.textContainerOrigin.y)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: textView.convert(inView, to: nil),
                                                     modifierFlags: [], timestamp: 0, windowNumber: window!.windowNumber,
                                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        textView.mouseDown(with: event)
        XCTAssertEqual(textView.string, "- [x] open\n\nlast")
    }
}
