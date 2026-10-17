import AppKit
import MermaidRender

/// Draws Mermaid diagrams natively with MermaidKit, in a theme's colors.
///
/// MermaidKit keeps its own render cache but hands back a new copy of the image on every
/// call; this cache keeps one image per diagram and theme instead of rendering again on every
/// restyle. A diagram's `ImageBlock` carries its theme and source as its key, so even when this
/// cache lets an image go, drawing the diagram again isn't a change.
final class MermaidDiagrams {
    static let shared = MermaidDiagrams()

    /// Images by theme name and source. NSCache also empties itself under memory pressure.
    private let images = NSCache<NSString, NSImage>()
    /// Sources MermaidKit couldn't draw, so a broken diagram isn't parsed again on every restyle.
    private var failed: Set<String> = []

    init() {
        images.countLimit = 200
    }

    /// Whether a code block's info string names Mermaid: its first word is `mermaid`, in any case.
    static func isMermaid(info: String?) -> Bool {
        guard let first = info?.split(whereSeparator: \.isWhitespace).first else { return false }
        return first.lowercased() == "mermaid"
    }

    /// The diagram for `source` in `theme`'s colors, or nil when it isn't a diagram MermaidKit can draw.
    /// Call on the main thread.
    func image(for source: String, theme: Theme) -> NSImage? {
        let key = theme.name + "\u{0}" + source
        if let image = images.object(forKey: key as NSString) { return image }
        guard !failed.contains(key) else { return nil }
        guard let image = MermaidRenderer.image(source: source, theme: Self.diagramTheme(for: theme)),
              image.size.width > 0, image.size.height > 0
        else {
            if failed.count > 500 { failed.removeAll() }
            failed.insert(key)
            return nil
        }
        images.setObject(image, forKey: key as NSString)
        return image
    }

    /// Forgets every image, as the cache does under memory pressure.
    func removeAll() {
        images.removeAllObjects()
        failed.removeAll()
    }

    /// MermaidKit draws node labels at 12 points (`DiagramLayout.nodeFontSize`).
    private static let labelSize: CGFloat = 12

    /// How much larger than MermaidKit's natural size to draw a diagram, so its labels are
    /// the size of the theme's body text. The images are vector, so they stay sharp.
    static func scale(for theme: Theme) -> CGFloat {
        max(1, theme.bodyFont.pointSize / labelSize)
    }

    /// MermaidKit's colors from a Cera theme. The diagram's image is transparent; `canvas`
    /// fills only the cut-outs behind labels and arrowheads, so it must match the page.
    static func diagramTheme(for theme: Theme) -> DiagramTheme {
        DiagramTheme(ink: theme.text,
                     secondaryTextColor: theme.text.withAlphaComponent(0.75),
                     tertiaryTextColor: theme.marker,
                     canvas: theme.background,
                     accent: accent(for: theme),
                     hairline: theme.rule,
                     prefersDark: theme.isDark)
    }

    /// The diagram's highlight color: node fills, bars, a mindmap's center. The theme's link
    /// color when it is a real color; Midnight's links are gray, so its selection blue instead.
    static func accent(for theme: Theme) -> NSColor {
        let link = theme.link.usingColorSpace(.sRGB) ?? theme.link
        return link.saturationComponent >= 0.2 ? theme.link : theme.selection
    }
}
