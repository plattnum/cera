import Foundation
import Markdown

/// Finds the syntax characters of inline formatting, so Clear Formatting can remove them.
enum InlineMarkup {
    /// The marker ranges, in document coordinates, of the emphasis, strong, strikethrough,
    /// code, link, and image spans in `region` that overlap `selection`. Sorted and
    /// non-overlapping. `region` should hold whole top-level blocks, so the Markdown parses
    /// as it does in the document.
    ///
    /// A span counts when the selection touches any part of it: selecting rendered text
    /// selects only the visible characters, never the hidden markers around them.
    static func markers(in text: NSString, region: NSRange, touching selection: NSRange) -> [NSRange] {
        let piece = NSString(string: FrontMatter.parsable(text, region: region).text)
        let map = SourceMap(piece)
        let local = NSRange(location: selection.location - region.location, length: selection.length)
        var found: [NSRange] = []

        func range(_ markup: Markup) -> NSRange? { map.range(of: markup) }

        func touches(_ span: NSRange) -> Bool {
            NSIntersectionRange(span, local).length > 0
                || (local.length == 0 && local.location > span.location && local.location < NSMaxRange(span))
        }

        func visit(_ markup: Markup) {
            if let span = range(markup), span.length > 1, touches(span) {
                switch markup {
                case is Markdown.Emphasis, is Strong, is Strikethrough:
                    found += delimiters(of: markup, span: span)
                case is InlineCode:
                    found += codeMarkers(span)
                case is Link:
                    found += linkMarkers(of: markup, span: span, opening: 1)
                case is Image:
                    found += linkMarkers(of: markup, span: span, opening: 2)
                default:
                    break
                }
            }
            for child in markup.children { visit(child) }
        }

        /// `**text**`, `*text*`, `~~text~~`. In `***text***` the parser gives the inner node
        /// its parent's range, so step inside the markers of enclosing nodes starting at the same place.
        func delimiters(of markup: Markup, span: NSRange) -> [NSRange] {
            var span = span
            var inset = 0
            var ancestor = markup.parent
            while let outer = ancestor, outer is Markdown.Emphasis || outer is Strong || outer is Strikethrough,
                  range(outer)?.location == span.location {
                inset += outer is Markdown.Emphasis ? 1 : 2
                ancestor = outer.parent
            }
            guard span.length > 2 * inset + 1 else { return [] }
            span = NSRange(location: span.location + inset, length: span.length - 2 * inset)
            let delimiter = piece.character(at: span.location)
            let limit = markup is Markdown.Emphasis ? 1 : 2
            var width = 0
            while width < limit, width < span.length / 2, piece.character(at: span.location + width) == delimiter { width += 1 }
            return [NSRange(location: span.location, length: width),
                    NSRange(location: NSMaxRange(span) - width, length: width)]
        }

        /// The backtick runs, plus the single space of padding CommonMark strips inside them.
        func codeMarkers(_ span: NSRange) -> [NSRange] {
            var ticks = 0
            while ticks < span.length / 2, piece.character(at: span.location + ticks) == 96 { ticks += 1 }
            guard ticks > 0 else { return [] }
            var opening = NSRange(location: span.location, length: ticks)
            var closing = NSRange(location: NSMaxRange(span) - ticks, length: ticks)
            let inner = NSRange(location: NSMaxRange(opening), length: closing.location - NSMaxRange(opening))
            let content = piece.substring(with: inner)
            if inner.length >= 2, content.hasPrefix(" "), content.hasSuffix(" "),
               content.contains(where: { $0 != " " }) {
                opening.length += 1
                closing.location -= 1
                closing.length += 1
            }
            return [opening, closing]
        }

        /// `[label](url)` and `![alt](src)` keep their label; `<url>` keeps the URL; bare URLs have no markers.
        func linkMarkers(of markup: Markup, span: NSRange, opening: Int) -> [NSRange] {
            let first = piece.character(at: span.location)
            if first == 60 { // "<url>"
                return [NSRange(location: span.location, length: 1), NSRange(location: NSMaxRange(span) - 1, length: 1)]
            }
            guard first == (opening == 2 ? 33 : 91) else { return [] } // "!" or "["
            let labelStart = span.location + opening
            var labelEnd = labelStart
            if markup.childCount > 0, let last = markup.child(at: markup.childCount - 1), let lastRange = range(last) {
                labelEnd = max(labelStart, min(NSMaxRange(lastRange), NSMaxRange(span)))
            }
            return [NSRange(location: span.location, length: opening),
                    NSRange(location: labelEnd, length: NSMaxRange(span) - labelEnd)]
        }

        visit(Document(parsing: piece as String))

        // Sort, merge any overlap, and move to document coordinates.
        var merged: [NSRange] = []
        for marker in found.filter({ $0.length > 0 }).sorted(by: { $0.location < $1.location }) {
            if let last = merged.last, marker.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSUnionRange(last, marker)
            } else {
                merged.append(marker)
            }
        }
        return merged.map { NSRange(location: $0.location + region.location, length: $0.length) }
    }
}
