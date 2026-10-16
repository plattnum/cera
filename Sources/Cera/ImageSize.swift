import Foundation

/// An image's size, written into its alt text after a `|`, as Obsidian does: `![photo|500](photo.png)`.
enum ImageSize {
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
