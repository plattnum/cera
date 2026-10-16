import Foundation
import Markdown

/// The preset sizes offered on an image's right-click menu. A size is written into the
/// image's alt text after a `|`, as Obsidian does: `![photo|500](photo.png)`.
enum ImageSize: CaseIterable {
    case small, medium, large, original

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .original: "Original Size"
        }
    }

    /// The width written into the Markdown, or nil to show the image at its own size.
    var width: Int? {
        switch self {
        case .small: 300
        case .medium: 500
        case .large: 700
        case .original: nil
        }
    }

    /// The size asked for after the last `|` in an image's alt text: `photo|300` for a
    /// width, `photo|300x200` for a box the image fits inside. Nil when there's no such size.
    static func requested(alt: String) -> (width: CGFloat, height: CGFloat?)? {
        guard let pipe = alt.lastIndex(of: "|") else { return nil }
        let parts = alt[alt.index(after: pipe)...].trimmingCharacters(in: .whitespaces)
            .split(separator: "x", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let width = Int(parts[0]), width > 0
        else { return nil }
        guard parts.count == 2 else { return (CGFloat(width), nil) }
        guard let height = Int(parts[1]), height > 0 else { return nil }
        return (CGFloat(width), CGFloat(height))
    }
}

/// A line holding nothing but a Markdown image, whose size can be read and changed.
struct ImageLine {
    private let line: String
    /// Where the alt text sits in `line`, between `![` and `]`.
    private let alt: Range<String.Index>

    /// Nil unless `line` is a paragraph holding a single image and nothing else.
    init?(_ line: String) {
        let document = Document(parsing: line)
        guard document.childCount == 1,
              let paragraph = document.child(at: 0) as? Paragraph,
              paragraph.childCount == 1,
              let image = paragraph.child(at: 0) as? Image,
              let opening = image.range?.lowerBound,
              let start = Self.index(atColumn: opening.column + 2, in: line)
        else { return nil }
        let end = image.children.compactMap { $0.range?.upperBound.column }.max()
            .flatMap { Self.index(atColumn: $0, in: line) } ?? start
        self.line = line
        self.alt = start..<max(start, end)
    }

    /// The plain width after the `|`, or nil when there's none or it's a width-and-height box.
    var width: Int? {
        guard let size = ImageSize.requested(alt: String(line[alt])), size.height == nil else { return nil }
        return Int(size.width)
    }

    /// The line with its size replaced by `width`, or removed when `width` is nil.
    func settingWidth(_ width: Int?) -> String {
        var text = String(line[alt])
        if ImageSize.requested(alt: text) != nil, let pipe = text.lastIndex(of: "|") {
            text = String(text[..<pipe])
        }
        if let width { text += "|\(width)" }
        return line.replacingCharacters(in: alt, with: text)
    }

    /// swift-markdown columns count UTF-8 bytes from 1.
    private static func index(atColumn column: Int, in line: String) -> String.Index? {
        line.utf8.index(line.utf8.startIndex, offsetBy: column - 1, limitedBy: line.utf8.endIndex)
    }
}
