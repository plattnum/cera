import Foundation

/// The anchors headings answer to, so `[Install](#install)` can jump to `## Install`.
/// Anchors follow GitHub's rules, which READMEs are written against.
enum HeadingAnchors {
    /// The anchor for a heading's text: lowercased, with everything but letters, marks,
    /// numbers, spaces, `-` and `_` dropped, then each space turned into `-`.
    static func slug(_ title: String) -> String {
        var slug = String.UnicodeScalarView()
        for scalar in title.lowercased().unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark,
                 .decimalNumber, .letterNumber, .otherNumber:
                slug.append(scalar)
            default:
                if scalar == " " { slug.append("-") } else if scalar == "-" || scalar == "_" { slug.append(scalar) }
            }
        }
        return String(slug)
    }

    /// Each heading's anchor and where its line starts, in document order. A repeated
    /// anchor gets `-1`, `-2`, … as on GitHub.
    static func anchors(in text: String) -> [(anchor: String, location: Int)] {
        var taken = Set<String>()
        var counts: [String: Int] = [:]
        return Outline.items(in: text).map { item in
            let base = slug(item.title)
            var anchor = base
            while taken.contains(anchor) {
                counts[base, default: 0] += 1
                anchor = "\(base)-\(counts[base]!)"
            }
            taken.insert(anchor)
            return (anchor, item.location)
        }
    }

    /// Where the heading named by `anchor` starts, compared ignoring case. With no such
    /// heading, `top` means the start of the document, as in a browser; anything else, nil.
    static func location(of anchor: String, in text: String) -> Int? {
        guard !anchor.isEmpty else { return nil }
        let wanted = anchor.lowercased()
        if let match = anchors(in: text).first(where: { $0.anchor == wanted }) { return match.location }
        return wanted == "top" ? 0 : nil
    }
}
