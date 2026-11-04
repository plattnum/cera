import AppKit
import XCTest
@testable import Cera

/// The column width slider: 0% is the theme's column, 100% is the full window less the page margin.
final class ColumnWidthTests: XCTestCase {
    // MARK: Arithmetic

    func testZeroPercentIsTodaysColumn() {
        XCTAssertEqual(ColumnWidth.width(for: .midnight, windowWidth: 1200, percent: 0), 914)
        XCTAssertEqual(ColumnWidth.width(for: .midnight, windowWidth: 1600, percent: 0), 1024, "the wide column from 1400pt")
    }

    func testHundredPercentIsTheWindowLessTheMargins() {
        XCTAssertEqual(ColumnWidth.width(for: .midnight, windowWidth: 1600, percent: 100), 1600 - 2 * 68)
    }

    func testHalfwayIsHalfway() {
        XCTAssertEqual(ColumnWidth.width(for: .midnight, windowWidth: 1600, percent: 50), 1024 + (1464 - 1024) / 2)
    }

    func testNarrowWindowStaysAtTheColumn() {
        XCTAssertEqual(ColumnWidth.width(for: .midnight, windowWidth: 600, percent: 100), 914)
    }

    func testStoredValuesAreKeptInRange() {
        XCTAssertEqual(ColumnWidth.clamped(150), 100)
        XCTAssertEqual(ColumnWidth.clamped(-1), 0)
        XCTAssertEqual(ColumnWidth.clamped(.nan), 0)
        XCTAssertEqual(ColumnWidth.clamped(45), 45)
        XCTAssertEqual(ColumnWidth.clampedSliderLength(10), 80)
        XCTAssertEqual(ColumnWidth.clampedSliderLength(1000), 400)
        XCTAssertEqual(ColumnWidth.clampedSliderLength(.nan), 150)
    }

    func testDefaultsStartAtTwentyPercentAndAHundredAndFiftyPoints() {
        XCTAssertEqual(ColumnWidth.defaults[ColumnWidth.key] as? Double, 20)
        XCTAssertEqual(ColumnWidth.defaults[ColumnWidth.defaultKey] as? Double, 20)
        XCTAssertEqual(ColumnWidth.defaults[ColumnWidth.sliderLengthKey] as? Double, 150)
    }
}

/// The text view's column at a percentage.
@MainActor
final class ColumnPercentTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() {
        window?.close()
    }

    /// A styled, laid-out editor in a window `width` wide, in the Ivory theme (960pt column, 68pt margins). The
    /// text view is narrower than the window by the scroller.
    private func editor(width: CGFloat) -> MarkdownTextView {
        let (scrollView, textView) = MarkdownEditor.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        self.window = window
        scrollView.layoutSubtreeIfNeeded()
        textView.apply(.ivory)
        textView.string = "Some text"
        MarkdownStyler(theme: .ivory).style(textView.textStorage!, caret: 0)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        return textView
    }

    func testPercentWidensTheColumn() {
        let view = editor(width: 1300)
        let width = view.frame.width
        XCTAssertGreaterThan(width, 1200)
        XCTAssertEqual(view.textContainerInset.width, (width - 960) / 2, accuracy: 0.5, "0%: today's centered column")
        view.columnPercent = 100
        XCTAssertEqual(view.textContainerInset.width, 68, accuracy: 0.5, "100%: the page margin only")
        view.columnPercent = 50
        XCTAssertEqual(view.textContainerInset.width, (width - (960 + (width - 136 - 960) / 2)) / 2, accuracy: 0.5)
    }

    func testNarrowWindowKeepsThePageMargin() {
        let view = editor(width: 600)
        view.columnPercent = 100
        XCTAssertEqual(view.textContainerInset.width, 68, accuracy: 0.5)
    }

    func testChangingThePercentRewrapsAndTellsTheEditor() {
        let view = editor(width: 1300)
        var changes = 0
        view.onWidthChange = { changes += 1 }
        view.columnPercent = 100
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(view.textContainer!.size.width, view.frame.width - 136, accuracy: 1, "the text wraps in the wider column")
        view.columnPercent = 100
        XCTAssertEqual(changes, 1, "the same value again changes nothing")
    }
}
