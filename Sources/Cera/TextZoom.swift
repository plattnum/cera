import Foundation

/// View ▸ Zoom In, Zoom Out, and Actual Size: the document is magnified as a whole, as in a browser, so text,
/// spacing, checkboxes, tables, and images all scale together. One level for every window, remembered.
enum TextZoom {
    /// The user defaults key holding the level, where 1 is actual size.
    static let key = "textZoom"

    /// The levels Zoom In and Zoom Out step through, as in Safari.
    static let levels: [Double] = [0.5, 0.67, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]

    /// The next level up from `zoom`, or nil at the largest.
    static func zoomedIn(from zoom: Double) -> Double? {
        levels.first { $0 > zoom + 0.001 }
    }

    /// The next level down from `zoom`, or nil at the smallest.
    static func zoomedOut(from zoom: Double) -> Double? {
        levels.last { $0 < zoom - 0.001 }
    }

    /// A stored level kept within the range, in case the defaults were edited by hand.
    static func clamped(_ zoom: Double) -> Double {
        zoom.isFinite ? min(max(zoom, levels.first!), levels.last!) : 1
    }
}
