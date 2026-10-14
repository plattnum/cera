import AppKit

/// The small toolbar that floats above selected text, so formatting doesn't
/// require remembering Markdown or shortcuts.
final class FormatBar: NSVisualEffectView {
    private weak var textView: MarkdownTextView?
    private let headingButton: NSButton

    init(textView: MarkdownTextView) {
        self.textView = textView
        headingButton = NSButton(title: "H", target: nil, action: nil)
        super.init(frame: .zero)

        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.masksToBounds = true

        headingButton.target = self
        headingButton.action = #selector(showHeadingMenu(_:))
        style(headingButton, tooltip: "Heading")
        headingButton.attributedTitle = NSAttributedString(string: "H", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor
        ])

        let groups: [[NSView]] = [
            [
                button("bold", "Bold (⌘B)", #selector(MarkdownTextView.toggleBold(_:))),
                button("italic", "Italic (⌘I)", #selector(MarkdownTextView.toggleItalic(_:))),
                button("strikethrough", "Strikethrough (⇧⌘X)", #selector(MarkdownTextView.toggleStrikethrough(_:))),
                button("chevron.left.forwardslash.chevron.right", "Inline Code (⌘E)", #selector(MarkdownTextView.toggleInlineCode(_:))),
                button("link", "Link (⌘K)", #selector(MarkdownTextView.insertLink(_:)))
            ],
            [
                headingButton,
                button("text.quote", "Quote (⌥⌘Q)", #selector(MarkdownTextView.toggleQuote(_:)))
            ],
            [
                button("list.bullet", "Bulleted List (⌥⌘U)", #selector(MarkdownTextView.toggleBulletedList(_:))),
                button("list.number", "Numbered List (⌥⌘O)", #selector(MarkdownTextView.toggleNumberedList(_:))),
                button("checklist", "Task List (⌥⌘X)", #selector(MarkdownTextView.toggleTaskList(_:)))
            ],
            [
                button("eraser", "Clear Formatting (⌘\\)", #selector(MarkdownTextView.clearFormatting(_:)))
            ]
        ]

        var items: [NSView] = []
        for (index, group) in groups.enumerated() {
            if index > 0 { items.append(divider()) }
            items += group
        }
        let stack = NSStackView(views: items)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Clicks on the bar must not reach the text view underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit == nil && frame.contains(point) ? self : hit
    }

    override func mouseDown(with event: NSEvent) {} // Swallow clicks between buttons.

    // MARK: - Controls

    private func button(_ symbol: String, _ tooltip: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage()
        let button = NSButton(image: image, target: textView, action: action)
        style(button, tooltip: tooltip)
        return button
    }

    private func style(_ button: NSButton, tooltip: String) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = button.image == nil ? .noImage : .imageOnly
        button.contentTintColor = .labelColor
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func divider() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return line
    }

    @objc private func showHeadingMenu(_ sender: NSButton) {
        guard let textView else { return }
        let menu = NSMenu()
        let entries: [(String, Selector)] = [
            ("Paragraph", #selector(MarkdownTextView.paragraph(_:))),
            ("Heading 1", #selector(MarkdownTextView.heading1(_:))),
            ("Heading 2", #selector(MarkdownTextView.heading2(_:))),
            ("Heading 3", #selector(MarkdownTextView.heading3(_:))),
            ("Heading 4", #selector(MarkdownTextView.heading4(_:)))
        ]
        for (title, action) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = textView
            menu.addItem(item)
        }
        let below = NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4)
        menu.popUp(positioning: nil, at: below, in: sender)
    }
}

extension MarkdownTextView {
    /// Shows the format bar above the selection, or below it when there is no room above.
    /// Hides it when nothing is selected.
    func updateFormatBar() {
        let selection = selectedRange()
        guard selection.length > 0, window != nil,
              let layoutManager, let textContainer, let bar = formatBar
        else {
            formatBar?.isHidden = true
            return
        }

        let glyphs = layoutManager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        let firstLine = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let selected = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let top = firstLine.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y).minY

        let size = bar.fittingSize
        let visible = visibleRect
        let anchorX = selected.height > firstLine.height * 1.5
            ? layoutManager.location(forGlyphAt: glyphs.location).x + firstLine.minX + textContainerOrigin.x
            : selected.midX - size.width / 2
        let x = min(max(anchorX, visible.minX + 8), visible.maxX - size.width - 8)
        var y = top - size.height - 6
        if y < visible.minY + 4 {
            y = selected.maxY + 6
        }
        bar.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        bar.isHidden = false
    }
}
