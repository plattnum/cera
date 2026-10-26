import AppKit

/// The kinds of callout: GitHub's five alert types, then the extra types other Markdown editors draw.
enum CalloutKind: String, CaseIterable {
    case note, tip, important, warning, caution
    case info, todo, abstract, success, question, failure, danger, bug, example, quote

    /// The kind a type name stands for, in any case. Unknown names are notes.
    /// `important` and `caution` keep GitHub's meaning, not other names for tip and warning.
    init(typeName: String) {
        let name = typeName.lowercased()
        if let kind = CalloutKind(rawValue: name) {
            self = kind
            return
        }
        switch name {
        case "hint": self = .tip
        case "attention": self = .warning
        case "summary", "tldr": self = .abstract
        case "check", "done": self = .success
        case "help", "faq": self = .question
        case "fail", "missing": self = .failure
        case "error": self = .danger
        case "cite": self = .quote
        default: self = .note
        }
    }

    var family: CalloutColorFamily {
        switch self {
        case .note, .info, .todo: return .blue
        case .abstract: return .teal
        case .tip, .success: return .green
        case .important, .example: return .purple
        case .warning: return .amber
        case .question: return .orange
        case .caution, .failure, .danger, .bug: return .red
        case .quote: return .gray
        }
    }

    /// The SF Symbol drawn in the header.
    var symbolName: String {
        switch self {
        case .note: return "info.circle"
        case .tip: return "lightbulb"
        case .important: return "exclamationmark.bubble"
        case .warning: return "exclamationmark.triangle"
        case .caution: return "exclamationmark.octagon"
        case .info: return "pencil"
        case .todo: return "checkmark.circle"
        case .abstract: return "list.clipboard"
        case .success: return "checkmark"
        case .question: return "questionmark.circle"
        case .failure: return "xmark"
        case .danger: return "bolt"
        case .bug: return "ladybug"
        case .example: return "list.bullet"
        case .quote: return "quote.opening"
        }
    }

    /// The header icon, tinted.
    func icon(color: NSColor, pointSize: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: rawValue)?
            .withSymbolConfiguration(configuration)
    }
}

/// Callout colors: one palette for every theme, in a dark and a light version.
enum CalloutColorFamily {
    case blue, teal, green, purple, amber, orange, red, gray

    func color(dark: Bool) -> NSColor {
        switch self {
        case .blue: return NSColor(hex: dark ? 0x4C8DF6 : 0x1F6FE0)
        case .teal: return NSColor(hex: dark ? 0x2DB7C4 : 0x0B7F8C)
        case .green: return NSColor(hex: dark ? 0x3FB66B : 0x1E8A45)
        case .purple: return NSColor(hex: dark ? 0xA97BF5 : 0x7C4FD6)
        case .amber: return NSColor(hex: dark ? 0xD9A23A : 0xA86C00)
        case .orange: return NSColor(hex: dark ? 0xE8833A : 0xC2570C)
        case .red: return NSColor(hex: dark ? 0xEE5A55 : 0xCC2F35)
        case .gray: return NSColor(hex: dark ? 0x9AA1A8 : 0x6A737D)
        }
    }
}

/// The `[!TYPE]` marker on a callout's first line.
struct CalloutMarker: Equatable {
    let kind: CalloutKind
    /// The type as typed, capitalized: shown when there is no title.
    let label: String
    /// Length (UTF-16) of the marker to hide: `[!type]`, a fold sign, and the space before a title.
    let markerLength: Int
    let hasTitle: Bool

    /// `[!type]`, a fold sign (accepted, not acted on), then an optional title after a space.
    private static let regex = try! NSRegularExpression(pattern: "^\\[!([A-Za-z0-9_-]+)\\]([+-])?(?:([ \\t]+)(\\S.*?))?[ \\t]*$")

    /// The marker at the start of `line`, the text from a quote's first paragraph to the end of its first line.
    static func parse(_ line: String) -> CalloutMarker? {
        let text = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else { return nil }
        let type = text.substring(with: match.range(at: 1))
        let title = match.range(at: 4)
        let hasTitle = title.location != NSNotFound
        return CalloutMarker(kind: CalloutKind(typeName: type),
                             label: type.prefix(1).uppercased() + type.dropFirst().lowercased(),
                             markerLength: hasTitle ? title.location : text.length,
                             hasTitle: hasTitle)
    }
}

/// One callout box, on each of its lines: lines inside a nested callout carry both, outer first.
/// Equal when they are the same callout drawn the same way, so lines of one callout run together, two callouts
/// next to each other stay apart, and restyling is a no-op.
final class CalloutBlock: NSObject {
    let kind: CalloutKind
    /// The box's left edge, measured from the column's left edge.
    let x: CGFloat
    /// How many callouts enclose this one.
    let depth: Int
    /// Where its first line starts, in the text it was styled in: tells apart callouts that touch.
    let header: Int

    init(kind: CalloutKind, x: CGFloat, depth: Int, header: Int) {
        self.kind = kind
        self.x = x
        self.depth = depth
        self.header = header
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CalloutBlock else { return false }
        return other.kind == kind && other.x == x && other.depth == depth && other.header == header
    }

    override var hash: Int { header ^ depth }
}

/// On a callout's first line, when it isn't being edited: the icon to draw, and the label when the line has no title.
final class CalloutHeader: NSObject {
    let kind: CalloutKind
    let label: String?

    init(kind: CalloutKind, label: String?) {
        self.kind = kind
        self.label = label
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? CalloutHeader else { return false }
        return other.kind == kind && other.label == label
    }

    override var hash: Int { kind.hashValue }
}

/// How a callout box is drawn and spaced.
enum CalloutStyle {
    /// Space inside the box above the first line and below the last, added to the block's height.
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 10
    /// Space between the text and the box's right edge, per level of callout.
    static let rightPadding: CGFloat = 12
    /// Space between two callouts with no blank line between them, as in consecutive list items.
    static let adjacentGap: CGFloat = 8
    static let iconSize: CGFloat = 16
    static let iconGap: CGFloat = 8
    static let radius: CGFloat = 6
    static let edgeWidth: CGFloat = 4
    static let borderAlpha: CGFloat = 0.55

    static func fillAlpha(dark: Bool) -> CGFloat { dark ? 0.10 : 0.07 }
}
