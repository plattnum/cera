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

    private static func codeBlock(in markup: Markup, onLine line: Int) -> CodeBlock? {
        if let block = markup as? CodeBlock, let range = block.range {
            // A range ending at column 1 ends with the previous line's line break.
            let lastLine = range.upperBound.column == 1 ? range.upperBound.line - 1 : range.upperBound.line
            return (range.lowerBound.line...max(range.lowerBound.line, lastLine)).contains(line) ? block : nil
        }
        for child in markup.children {
            if let found = codeBlock(in: child, onLine: line) { return found }
        }
        return nil
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
        let inset: CGFloat = 6
        let rect = panel.rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        button.setFrameOrigin(NSPoint(x: rect.maxX - inset - CodeCopyButton.size.width, y: rect.minY + inset))
        button.isHidden = false
    }

    func hideCodeCopyButton() {
        codeCopyButton?.isHidden = true
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
