import AppKit
import Markdown

/// Reads the code out of a code block: the lines between the fences, without the
/// indentation or quote markers that nest the block in a list or quote.
enum CodeBlockText {
    /// The code of the code block on the line holding `location`. `region` must hold whole
    /// top-level blocks, so the block parses in its real context.
    static func code(in text: NSString, at location: Int, region: NSRange) -> String? {
        guard NSLocationInRange(location, region) else { return nil }
        let source = text.substring(with: region) as NSString
        let map = SourceMap(source)
        // 1-based, as swift-markdown counts lines.
        let line = (map.lineStarts.lastIndex { $0 <= location - region.location } ?? 0) + 1
        guard let block = codeBlock(in: Document(parsing: source as String), onLine: line) else { return nil }
        var code = block.code
        if code.hasSuffix("\n") { code.removeLast() }
        return code
    }

    /// The code block in `markup` whose lines include `line` (1-based).
    static func codeBlock(in markup: Markup, onLine line: Int) -> CodeBlock? {
        if let block = markup as? CodeBlock, let lines = lines(of: block) {
            return lines.contains(line) ? block : nil
        }
        for child in markup.children {
            if let found = codeBlock(in: child, onLine: line) { return found }
        }
        return nil
    }
    /// An opening fence line: what comes before the fence (quote markers, list marker, indentation;
    /// group 1), the fence (group 2), and the rest (group 3).
    static let fenceLine = try! NSRegularExpression(
        pattern: "^((?:[ \\t]*>[ \\t]?|[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+|[ \\t])*)(`{3,}|~{3,})(.*)$")

    /// The closing fence line of a fenced block whose opening fence is on `opening` (a line's
    /// characters, without its line break), or nil while the block is open. As CommonMark reads it:
    /// the line straight after the code, starting with the block's container prefix, then at most
    /// three spaces, then at least as many of the opening fence's characters, then only spaces.
    /// A line that only looks like a fence (indented too far, too short, the other character) is
    /// code, and leaves the block open.
    static func closingFence(of block: CodeBlock, in text: NSString, opening: NSRange) -> NSRange? {
        let openingText = text.substring(with: opening)
        guard let open = fenceLine.firstMatch(in: openingText, range: NSRange(location: 0, length: (openingText as NSString).length))
        else { return nil }
        let fence = (openingText as NSString).substring(with: open.range(at: 2))
        let prefix = String((openingText as NSString).substring(with: open.range(at: 1))
            .map { $0 == ">" || $0 == " " || $0 == "\t" ? $0 : " " })

        // Step past the opening line and one line per line of code.
        var code = block.code
        if code.hasSuffix("\n") { code.removeLast() }
        let codeLines = block.code.isEmpty ? 0 : code.split(separator: "\n", omittingEmptySubsequences: false).count
        var lineStart = NSMaxRange(text.lineRange(for: opening))
        for _ in 0..<codeLines {
            guard lineStart < text.length else { return nil }
            lineStart = NSMaxRange(text.lineRange(for: NSRange(location: lineStart, length: 0)))
        }
        guard lineStart < text.length else { return nil }
        let full = text.lineRange(for: NSRange(location: lineStart, length: 0))
        var end = NSMaxRange(full)
        while end > full.location, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
        let line = NSRange(location: full.location, length: end - full.location)

        var rest = Substring(text.substring(with: line))
        // The container prefix. Only the space after a quote marker may be left out.
        var previous: Character?
        for character in prefix {
            if rest.first == character {
                rest = rest.dropFirst()
            } else if !(character == " " && previous == ">") {
                return nil
            }
            previous = character
        }
        let spaces = rest.prefix { $0 == " " }.count
        guard spaces <= 3 else { return nil }
        rest = rest.dropFirst(spaces)
        let run = rest.prefix { $0 == fence.first }.count
        guard run >= fence.count, rest.dropFirst(run).allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        return line
    }

    /// The block's first and last lines (1-based).
    static func lines(of block: CodeBlock) -> ClosedRange<Int>? {
        guard let range = block.range else { return nil }
        // A range ending at column 1 ends with the previous line's line break.
        let lastLine = range.upperBound.column == 1 ? range.upperBound.line - 1 : range.upperBound.line
        return range.lowerBound.line...max(range.lowerBound.line, lastLine)
    }
}

/// The button that appears in a code block's corner while the pointer is over the block.
final class CodeCopyButton: NSButton {
    static let size = NSSize(width: 26, height: 26)
    /// A character in the code block the button copies.
    var location = 0
    private var theme: Theme?
    private var reset: DispatchWorkItem?

    convenience init() {
        self.init(frame: NSRect(origin: .zero, size: Self.size))
        isBordered = false
        imagePosition = .imageOnly
        refusesFirstResponder = true
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        toolTip = "Copy"
        setAccessibilityLabel("Copy Code")
        showIcon(copied: false)
    }

    func apply(_ theme: Theme) {
        guard theme.name != self.theme?.name else { return }
        self.theme = theme
        layer?.backgroundColor = theme.codePanel.cgColor
        layer?.borderColor = (theme.codeBorder ?? theme.rule).cgColor
        showIcon(copied: reset != nil)
    }

    /// Shows a checkmark for a moment after copying.
    func showCopied() {
        reset?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reset = nil
            self?.showIcon(copied: false)
        }
        reset = work
        showIcon(copied: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func showIcon(copied: Bool) {
        let name = copied ? "checkmark" : "doc.on.doc"
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        image = NSImage(systemSymbolName: name, accessibilityDescription: copied ? "Copied" : "Copy Code")?
            .withSymbolConfiguration(configuration)
        contentTintColor = copied ? theme?.text : theme?.marker
    }
}

extension MarkdownTextView {
    /// The code of the code block holding `location`, or nil when it isn't in one.
    func codeBlockText(at location: Int) -> String? {
        guard let panel = (layoutManager as? MarkdownLayoutManager)?.codePanel(at: location) else { return nil }
        let text = string as NSString
        // Parse the top-level block holding the code block, so a block nested in a list
        // or quote reads in context; without the block list, parse the block's own lines.
        let region = topLevelBlocks().first { NSLocationInRange(location, $0) && NSMaxRange($0) <= text.length }
            ?? panel.block
        return CodeBlockText.code(in: text, at: location, region: region)
    }

    /// The character under `point` (view coordinates) when the point is on a code block's panel.
    func codeBlockLocation(at point: NSPoint) -> Int? {
        guard let layoutManager = layoutManager as? MarkdownLayoutManager, let container = textContainer,
              let storage = textStorage, storage.length > 0
        else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: inContainer, in: container)
        let location = min(layoutManager.characterIndexForGlyph(at: glyph), storage.length - 1)
        guard let panel = layoutManager.codePanel(at: location), panel.rect.contains(inContainer) else { return nil }
        return location
    }

    /// Shows the copy button on the code block under the pointer, or hides it. `point` is in
    /// view coordinates and defaults to where the pointer is now.
    func updateCodeCopyButton(at point: NSPoint? = nil) {
        guard let window else { return hideCodeCopyButton() }
        let point = point ?? convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if let button = codeCopyButton, !button.isHidden, button.frame.contains(point) { return }
        guard visibleRect.contains(point), let location = codeBlockLocation(at: point),
              let panel = (layoutManager as? MarkdownLayoutManager)?.codePanel(at: location)
        else { return hideCodeCopyButton() }

        let button = codeCopyButton ?? {
            let button = CodeCopyButton()
            button.target = self
            button.action = #selector(copyCodeBlock(_:))
            addSubview(button)
            codeCopyButton = button
            return button
        }()
        button.apply(theme)
        // Remember the block's first character, which stays in the block while the pointer moves within it.
        button.location = panel.block.location
        showLanguageLabel(onBlockAt: panel.block.location)
        let inset: CGFloat = 6
        let rect = panel.rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        button.setFrameOrigin(NSPoint(x: rect.maxX - inset - CodeCopyButton.size.width, y: rect.minY + inset))
        button.isHidden = false
    }

    func hideCodeCopyButton() {
        codeCopyButton?.isHidden = true
        showLanguageLabel(onBlockAt: nil)
    }

    /// The copy button takes over its block's corner from the language label: hide the label on
    /// the block at `location` (nil: on none), and redraw the corners that change.
    private func showLanguageLabel(onBlockAt location: Int?) {
        guard let layoutManager = layoutManager as? MarkdownLayoutManager,
              layoutManager.codeBlockWithCopyButton != location else { return }
        for block in [layoutManager.codeBlockWithCopyButton, location].compactMap({ $0 }) {
            if let panel = layoutManager.codePanel(at: block) {
                let corner = NSRect(x: panel.rect.maxX - 160, y: panel.rect.minY, width: 160, height: 40)
                setNeedsDisplay(corner.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y))
            }
        }
        layoutManager.codeBlockWithCopyButton = location
    }

    @objc func copyCodeBlock(_ sender: Any?) {
        let location: Int
        if let button = sender as? CodeCopyButton {
            location = button.location
        } else if let item = sender as? NSMenuItem, let value = item.representedObject as? Int {
            location = value
        } else {
            return
        }
        guard let code = codeBlockText(at: location) else { return }
        codeCopyPasteboard.clearContents()
        codeCopyPasteboard.setString(code, forType: .string)
        (sender as? CodeCopyButton)?.showCopied()
    }
}
