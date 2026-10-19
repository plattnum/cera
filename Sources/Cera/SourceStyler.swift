import AppKit

/// Styles text as Markdown source: every character shown, in the theme's code font, with
/// the Markdown syntax colored by tree-sitter. None of `MarkdownStyler`'s rendering: no
/// hidden markers, and no attributes for the layout manager to draw from, so bullets,
/// panels, tables and images all show as the text they are.
enum SourceStyler {
    /// The attributes of source text, also used for typing.
    static func attributes(_ theme: Theme) -> [NSAttributedString.Key: Any] {
        [
            .font: theme.codeFont,
            .foregroundColor: theme.text,
            .paragraphStyle: MarkdownStyler.paragraph(lineHeight: theme.codeLineHeight),
            .baselineOffset: MarkdownStyler.baselineOffset(for: theme.codeFont, lineHeight: theme.codeLineHeight)
        ]
    }

    /// Styles one region of the document. `region` must start and end on boundaries between
    /// top-level blocks, so it parses as Markdown the way it does in the whole document.
    static func styleRegion(_ storage: NSTextStorage, text: NSString, region: NSRange, theme: Theme) {
        guard region.length > 0, NSMaxRange(region) <= text.length else { return }
        storage.beginEditing()
        storage.setAttributes(attributes(theme), range: region)
        // A region too long to highlight stays uncolored, so a huge block can't slow typing.
        if let markdown = CodeLanguages.language(info: "markdown"),
           let runs = SyntaxHighlighter.shared.runs(for: text.substring(with: region), language: markdown) {
            for run in runs {
                guard let color = theme.syntax.color(for: run.role) else { continue }
                storage.addAttribute(.foregroundColor, value: color,
                                     range: NSRange(location: region.location + run.location, length: run.length))
            }
        }
        storage.endEditing()
    }
}
