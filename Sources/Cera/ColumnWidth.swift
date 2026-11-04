import AppKit

/// The column width slider at the right end of the status bar: 0% is the theme's column, 100% is the full window
/// less the page margin on each side, and anywhere between widens the column into the margin. One width for
/// every window, remembered. The Settings window holds the slider's length and the percentage it goes back to.
enum ColumnWidth {
    /// The user defaults key holding the live percentage.
    static let key = "columnWidth"
    /// The key holding the percentage a double-click on the slider's number goes back to.
    static let defaultKey = "columnWidthDefault"
    /// The key holding the slider's length in the status bar, in points.
    static let sliderLengthKey = "columnSliderLength"

    /// The values before the user changes anything, registered at launch.
    static let defaults: [String: Any] = [key: 20.0, defaultKey: 20.0, sliderLengthKey: 150.0]

    /// A stored percentage kept within 0...100, in case the defaults were edited by hand.
    static func clamped(_ percent: Double) -> Double {
        percent.isFinite ? min(max(percent, 0), 100) : 0
    }

    /// A stored slider length kept within 80...400 points.
    static func clampedSliderLength(_ length: Double) -> Double {
        length.isFinite ? min(max(length, 80), 400) : 150
    }

    /// The column's width in a window `windowWidth` wide at `percent`: from the theme's column (its wide one from
    /// 1400pt) to the window less the page margins. A window too narrow for the theme's column keeps it, which
    /// the text view then fits between the margins as before.
    static func width(for theme: Theme, windowWidth: CGFloat, percent: Double) -> CGFloat {
        let base = windowWidth >= 1400 ? theme.wideColumnWidth : theme.columnWidth
        let full = windowWidth - 2 * theme.pageMargin
        guard full > base else { return base }
        return base + (full - base) * clamped(percent) / 100
    }
}
