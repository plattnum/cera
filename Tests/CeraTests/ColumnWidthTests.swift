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
