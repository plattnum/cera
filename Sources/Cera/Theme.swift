import AppKit

/// Fonts, colors, and spacing for the editor. Sizes are in points and mirror the
/// CSS pixel values of the stylesheet each theme is modeled on.
struct Theme {
    enum Bullet { case disc, square }
    /// A line drawn under a heading: across the column, or a short centered stroke.
    enum HeadingRule { case none, full, short }

    struct Heading {
        let font: NSFont
        let lineHeight: CGFloat
        var kern: CGFloat = 0
        let color: NSColor
        var rule: HeadingRule = .none
        var alignment: NSTextAlignment = .natural
        var uppercase = false
        /// Extra space above the heading, beyond the blank line before it.
        var spaceBefore: CGFloat = 0
    }

    struct Syntax {
        let comment: NSColor
        let string: NSColor
        let keyword: NSColor
        let number: NSColor
        let atom: NSColor
        let builtin: NSColor
        let type: NSColor
        let function: NSColor
        /// HTML and JSX element names.
        let tag: NSColor
        /// Added and removed lines in a diff.
        let inserted: NSColor
        let deleted: NSColor

        /// The color for a syntax role, or nil for body text.
        func color(for role: SyntaxRole) -> NSColor? {
            switch role {
            case .comment: comment
            case .string: string
            case .keyword: keyword
            case .number: number
            case .atom: atom
            case .builtin: builtin
            case .type: type
            case .function: function
            case .tag: tag
            case .inserted: inserted
            case .deleted: deleted
            case .plain: nil
            }
        }
    }

    let name: String
    /// Dark themes get a dark window frame, scrollers, and menus.
    let isDark: Bool

    // Text
    let bodyFont: NSFont
    let codeFont: NSFont
    let headings: [Heading]
    let lineHeight: CGFloat
    let codeLineHeight: CGFloat
    /// Height of a blank source line, which is the gap between blocks.
    let blockSpacing: CGFloat
    var bodyAlignment: NSTextAlignment = .natural
    var listItemSpacing: CGFloat = 6

    // Layout
    let columnWidth: CGFloat
    /// Column width once the window is at least 1400pt wide.
    let wideColumnWidth: CGFloat
    var pageMargin: CGFloat = 68
    var topMargin: CGFloat = 36
    let listIndent: CGFloat
    var bullet: Bullet = .disc
    let quoteBarX: CGFloat
    let quoteBarWidth: CGFloat
    let quoteIndent: CGFloat
    var quoteItalic = false
    /// Left edge of the code panel, measured from the column's left edge.
    var codePanelX: CGFloat = 0
    /// Left edge of code text, measured from the column's left edge.
    let codeIndent: CGFloat
    let codePadding: CGFloat
    var codeRadius: CGFloat = 0
    var codeBorder: NSColor?

    // Colors
    let background: NSColor
    let text: NSColor
    let marker: NSColor
    let link: NSColor
    var linkUnderline = false
    let codeText: NSColor
    let codePanel: NSColor
    let inlineCode: NSColor
    /// Space between inline code text and the edge of its background box.
    var inlineCodePadding: CGFloat = 4
    let quoteText: NSColor
    let quoteBar: NSColor
    let rule: NSColor
    let selection: NSColor
    let syntax: Syntax
    /// Color for bold text and table headers, when the theme sets one.
    var strongColor: NSColor?

    // MARK: - Shared syntax palettes

    /// Colors of the dark code theme.
    static let darkSyntax = Syntax(
        comment: NSColor(hex: 0xDA924A), string: NSColor(hex: 0xD26B6B), keyword: NSColor(hex: 0xC88FD0),
        number: NSColor(hex: 0x64AB8F), atom: NSColor(hex: 0x84B6CB), builtin: NSColor(hex: 0xF3B3F8),
        type: NSColor(hex: 0xE5C07B), function: NSColor(hex: 0x7FB2F0), tag: NSColor(hex: 0xE0876A),
        inserted: NSColor(hex: 0x8CC98A), deleted: NSColor(hex: 0xE57C7C)
    )

    /// The default light code colors.
    static let lightSyntax = Syntax(
        comment: NSColor(hex: 0xAA5500), string: NSColor(hex: 0xAA1111), keyword: NSColor(hex: 0x770088),
        number: NSColor(hex: 0x116644), atom: NSColor(hex: 0x221199), builtin: NSColor(hex: 0x3300AA),
        type: NSColor(hex: 0x008855), function: NSColor(hex: 0x0055AA), tag: NSColor(hex: 0x117700),
        inserted: NSColor(hex: 0x229922), deleted: NSColor(hex: 0xCC3333)
    )

    // MARK: - Themes

    /// Dark slate, Lucida Grande headings, Helvetica Neue text.
    static let midnight: Theme = {
        let text = NSColor(hex: 0xB8BFC6)
        let heading = NSColor(hex: 0xDEDEDE)
        return Theme(
            name: "Midnight", isDark: true,
            bodyFont: font("HelveticaNeue", 16),
            codeFont: font("Monaco", 14),
            headings: [
                Heading(font: font("LucidaGrande", 36), lineHeight: 40, kern: -1.5, color: heading),
                Heading(font: font("LucidaGrande-Bold", 24), lineHeight: 30, kern: -1, color: heading),
                Heading(font: font("LucidaGrande-Bold", 18), lineHeight: 24, kern: -1, color: heading),
                Heading(font: font("LucidaGrande", 16), lineHeight: 22, color: .white),
                Heading(font: font("LucidaGrande-Bold", 16), lineHeight: 22, color: heading),
                Heading(font: font("LucidaGrande", 16), lineHeight: 16, color: .white)
            ],
            lineHeight: 26, codeLineHeight: 24, blockSpacing: 24,
            columnWidth: 914, wideColumnWidth: 1024,
            listIndent: 30,
            quoteBarX: 30, quoteBarWidth: 2, quoteIndent: 62,
            codeIndent: 30, codePadding: 10,
            background: NSColor(hex: 0x363B40), text: text, marker: NSColor(hex: 0x7C838A),
            link: heading, linkUnderline: true,
            codeText: text, codePanel: NSColor(hex: 0x333333), inlineCode: NSColor(white: 0, alpha: 0.05), inlineCodePadding: 5,
            quoteText: NSColor(hex: 0x9DA2A6), quoteBar: NSColor(hex: 0x474D54), rule: NSColor(hex: 0x474D54),
            selection: NSColor(hex: 0x4A89DC), syntax: darkSyntax, strongColor: heading
        )
    }()

    /// Clean white page with Open Sans, like a code-hosting readme.
    static let plain: Theme = {
        let text = NSColor(hex: 0x333333)
        let bold = "OpenSans-Bold"
        return Theme(
            name: "Plain", isDark: false,
            bodyFont: font("OpenSans-Regular", 16),
            codeFont: font("Courier", 14.4),
            headings: [
                Heading(font: font(bold, 36), lineHeight: 43, color: text, rule: .full, spaceBefore: 8),
                Heading(font: font(bold, 28), lineHeight: 34, color: text, rule: .full, spaceBefore: 8),
                Heading(font: font(bold, 24), lineHeight: 34, color: text, spaceBefore: 8),
                Heading(font: font(bold, 20), lineHeight: 28, color: text, spaceBefore: 8),
                Heading(font: font(bold, 16), lineHeight: 22, color: text, spaceBefore: 8),
                Heading(font: font(bold, 16), lineHeight: 22, color: NSColor(hex: 0x777777), spaceBefore: 8)
            ],
            lineHeight: 25.6, codeLineHeight: 24, blockSpacing: 16,
            columnWidth: 860, wideColumnWidth: 860,
            listIndent: 30,
            quoteBarX: 0, quoteBarWidth: 4, quoteIndent: 19,
            codeIndent: 16, codePadding: 8, codeRadius: 3, codeBorder: NSColor(hex: 0xE7EAED),
            background: .white, text: text, marker: NSColor(hex: 0xA0A0A0),
            link: NSColor(hex: 0x4183C4),
            codeText: text, codePanel: NSColor(hex: 0xF8F8F8), inlineCode: NSColor(hex: 0xF3F4F4),
            quoteText: NSColor(hex: 0x777777), quoteBar: NSColor(hex: 0xDFE2E5), rule: NSColor(hex: 0xE7E7E7),
            selection: NSColor(hex: 0xB5D6FC), syntax: lightSyntax
        )
    }()

    /// Warm newsprint paper with PT Serif.
    static let broadsheet: Theme = {
        let text = NSColor(hex: 0x1F0909)
        return Theme(
            name: "Broadsheet", isDark: false,
            bodyFont: font("PTSerif-Regular", 16),
            codeFont: font("Menlo", 14),
            headings: [
                Heading(font: font("PTSerif-Regular", 30), lineHeight: 39, color: text, rule: .full, spaceBefore: 24),
                Heading(font: font("PTSerif-Bold", 21), lineHeight: 24, color: text, spaceBefore: 24),
                Heading(font: font("PTSerif-Regular", 21), lineHeight: 24, color: text, spaceBefore: 24),
                Heading(font: font("PTSerif-Bold", 18), lineHeight: 24, color: text, spaceBefore: 24),
                Heading(font: font("PTSerif-Bold", 16), lineHeight: 24, color: text, spaceBefore: 12),
                Heading(font: font("PTSerif-Bold", 16), lineHeight: 24, color: text, spaceBefore: 12)
            ],
            lineHeight: 24, codeLineHeight: 24, blockSpacing: 24,
            columnWidth: 914, wideColumnWidth: 914,
            listIndent: 48,
            quoteBarX: 32, quoteBarWidth: 5, quoteIndent: 53, quoteItalic: true,
            codePanelX: 32, codeIndent: 42, codePadding: 6,
            background: NSColor(hex: 0xF3F2EE), text: text, marker: NSColor(hex: 0x9A9590),
            link: NSColor(hex: 0x065588),
            codeText: text, codePanel: NSColor(hex: 0xDADADA), inlineCode: NSColor(hex: 0xDADADA), inlineCodePadding: 2,
            quoteText: NSColor(hex: 0x656565), quoteBar: NSColor(hex: 0xBABABA), rule: NSColor(hex: 0xC5C5C5),
            selection: NSColor(hex: 0xB5D6FC), syntax: lightSyntax
        )
    }()

    /// Airy reading layout: light Merriweather text with heavy Lato headings.
    static let airy: Theme = {
        let text = NSColor(hex: 0x333333)
        let black = "Lato-Black"
        return Theme(
            name: "Airy", isDark: false,
            bodyFont: font("MerriweatherLight18pt-Light", 20),
            codeFont: font("Menlo", 16),
            headings: [
                Heading(font: font(black, 52), lineHeight: 62, color: text, spaceBefore: 36),
                Heading(font: font(black, 36.8), lineHeight: 44, color: text, spaceBefore: 20),
                Heading(font: font(black, 26), lineHeight: 31, color: text, spaceBefore: 10),
                Heading(font: font(black, 20.8), lineHeight: 25, color: text, spaceBefore: 4),
                Heading(font: font(black, 19.2), lineHeight: 23, color: text, spaceBefore: 4),
                Heading(font: font(black, 16), lineHeight: 19, color: text)
            ],
            lineHeight: 36, codeLineHeight: 24, blockSpacing: 16, listItemSpacing: 8,
            columnWidth: 914, wideColumnWidth: 1100,
            listIndent: 34,
            quoteBarX: 0, quoteBarWidth: 5, quoteIndent: 31, quoteItalic: true,
            codeIndent: 18, codePadding: 8, codeBorder: NSColor(hex: 0x7A7A7A),
            background: .white, text: text, marker: NSColor(hex: 0xA0A0A0),
            link: NSColor(hex: 0x463F5C), linkUnderline: true,
            codeText: NSColor(hex: 0x7A7A7A), codePanel: .clear, inlineCode: .clear, inlineCodePadding: 0,
            quoteText: NSColor(hex: 0x555555), quoteBar: NSColor(hex: 0x7A7A7A), rule: NSColor(hex: 0xDDDDDD),
            selection: NSColor(hex: 0xB5D6FC), syntax: lightSyntax
        )
    }()

    /// Bookish Vollkorn with centered headings and square bullets.
    static let ivory: Theme = {
        let text = NSColor(hex: 0x333333)
        return Theme(
            name: "Ivory", isDark: false,
            bodyFont: font("Vollkorn-Regular", 19),
            codeFont: font("Menlo", 17),
            headings: [
                Heading(font: font("Vollkorn-Regular", 57), lineHeight: 68, color: text, alignment: .center, spaceBefore: 40),
                Heading(font: font("Vollkorn-Regular", 34), lineHeight: 41, color: text, rule: .short, alignment: .center, spaceBefore: 40),
                Heading(font: font("Vollkorn-Italic", 30), lineHeight: 36, color: text, alignment: .center, spaceBefore: 40),
                Heading(font: font("Vollkorn-Bold", 26.6), lineHeight: 32, color: text, spaceBefore: 12),
                Heading(font: font("Vollkorn-Bold", 22.8), lineHeight: 28, color: text, spaceBefore: 12),
                Heading(font: font("Vollkorn-Bold", 19), lineHeight: 24, color: text, spaceBefore: 12)
            ],
            lineHeight: 29, codeLineHeight: 26, blockSpacing: 19, bodyAlignment: .justified,
            columnWidth: 960, wideColumnWidth: 1100,
            listIndent: 28, bullet: .square,
            quoteBarX: 19, quoteBarWidth: 1, quoteIndent: 39,
            codePanelX: 19, codeIndent: 38, codePadding: 7, codeBorder: NSColor(hex: 0xDDDDDD),
            background: NSColor(hex: 0xFEFEFE), text: text, marker: NSColor(hex: 0xAAAAAA),
            link: NSColor(hex: 0x2484C1),
            codeText: text, codePanel: .white, inlineCode: .white, inlineCodePadding: 0,
            quoteText: text, quoteBar: NSColor(hex: 0xDDDDDD), rule: NSColor(hex: 0xDDDDDD),
            selection: NSColor(hex: 0xB5D6FC), syntax: lightSyntax
        )
    }()

    /// Geometric TeX Gyre Adventor with uppercase centered titles.
    static let grotesk: Theme = {
        let text = NSColor(hex: 0x111111)
        let regular = "TeXGyreAdventor-Regular"
        return Theme(
            name: "Grotesk", isDark: false,
            bodyFont: font(regular, 16),
            codeFont: font("Courier", 14.4),
            headings: [
                Heading(font: font(regular, 45), lineHeight: 64, color: text, alignment: .center, uppercase: true, spaceBefore: 44),
                Heading(font: font(regular, 32), lineHeight: 48, color: text, alignment: .center, uppercase: true, spaceBefore: 28),
                Heading(font: font(regular, 22.6), lineHeight: 32, color: text, spaceBefore: 12),
                Heading(font: font(regular, 20), lineHeight: 28, color: text, spaceBefore: 12),
                Heading(font: font(regular, 18.4), lineHeight: 26, color: text, spaceBefore: 8),
                Heading(font: font("TeXGyreAdventor-Bold", 16), lineHeight: 24, color: text, spaceBefore: 8)
            ],
            lineHeight: 28, codeLineHeight: 24, blockSpacing: 20, bodyAlignment: .justified,
            columnWidth: 914, wideColumnWidth: 1024,
            listIndent: 30,
            quoteBarX: 0, quoteBarWidth: 1, quoteIndent: 18,
            codeIndent: 16, codePadding: 6, codeBorder: NSColor(hex: 0xCCCCCC),
            background: NSColor(hex: 0xFCFCFC), text: text, marker: NSColor(hex: 0xA0A0A0),
            link: NSColor(hex: 0x990000),
            codeText: text, codePanel: .clear, inlineCode: NSColor(hex: 0xF0F0F0), inlineCodePadding: 2,
            quoteText: NSColor(hex: 0x6F6F6F), quoteBar: NSColor(hex: 0x808080), rule: NSColor(hex: 0xCCCCCC),
            selection: NSColor(hex: 0xB5D6FC), syntax: lightSyntax
        )
    }()

    private static func font(_ name: String, _ size: CGFloat) -> NSFont {
        FontRegistry.registerBundledFonts()
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }
}

/// The themes offered in the Themes menu.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case midnight, plain, broadsheet, airy, ivory, grotesk

    var id: String { rawValue }

    var theme: Theme {
        switch self {
        case .midnight: return .midnight
        case .plain: return .plain
        case .broadsheet: return .broadsheet
        case .airy: return .airy
        case .ivory: return .ivory
        case .grotesk: return .grotesk
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
