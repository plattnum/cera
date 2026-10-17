import AppKit

/// The editor's text view. Adds Markdown-aware editing: Return continues lists
/// and quotes, and the Format menu wraps or toggles syntax around the selection.
final class MarkdownTextView: NSTextView {

    /// Matches the start of a list item or quote: indentation, then the marker.
    /// Group 3 is set only for numbered items.
    private static let continuationRegex = try! NSRegularExpression(
        pattern: "^([ \\t]*)(>[ \\t]?|[-*+][ \\t]+(?:\\[[ xX]\\][ \\t]+)?|(\\d+)\\.[ \\t]+)"
    )

    /// Creates an editor with its text system built explicitly. A text view created
    /// without a container silently ignores later changes to its string.
    static func makeEditor(frame: NSRect) -> MarkdownTextView {
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        // Lay out only what is on screen, so large documents open quickly.
        layoutManager.allowsNonContiguousLayout = true
        // Line heights are exact, like CSS line-height; fonts' own leading would add to them.
        layoutManager.usesFontLeading = false
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)

        let textView = MarkdownTextView(frame: frame, textContainer: container)
        // Grow downward with the text and track the window's width.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        // Technical writing: nothing may rewrite what the user typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        return textView
    }

    // MARK: - Format bar

    /// The floating toolbar shown over selected text; created when first needed.
    private(set) var formatBar: FormatBar?

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !stillSelecting else {
            formatBar?.isHidden = true // Wait until the mouse is released.
            return
        }
        if selectedRange().length > 0, formatBar == nil {
            let bar = FormatBar(textView: self)
            bar.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
            bar.isHidden = true
            addSubview(bar)
            formatBar = bar
        }
        updateFormatBar()
    }

    override func didChangeText() {
        super.didChangeText()
        if selectedRange().length == 0 { formatBar?.isHidden = true }
    }

    // MARK: - Theme

    private(set) var theme: Theme = .midnight

    /// Applies the colors and column width; the text itself is styled by `MarkdownStyler`.
    func apply(_ theme: Theme) {
        self.theme = theme
        (layoutManager as? MarkdownLayoutManager)?.theme = theme
        backgroundColor = theme.background
        insertionPointColor = theme.text
        selectedTextAttributes = [.backgroundColor: theme.selection]
        typingAttributes = MarkdownStyler(theme: theme).bodyAttributes()
        enclosingScrollView?.backgroundColor = theme.background
        formatBar?.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        window?.backgroundColor = theme.background
        updateColumnInsets()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Let the document color run up under the title bar.
        window?.titlebarAppearsTransparent = true
        window?.backgroundColor = theme.background
    }

    /// Called when the text column's width changes, so images and tables can be resized.
    var onWidthChange: (() -> Void)?

    /// The reading position waiting to be put back after a change, by `keepReadingPosition`.
    var heldReadingPosition: ReadingPosition?

    /// The document's top-level block ranges, kept current by the editor's styler.
    /// Formatting commands parse whole blocks, so Markdown is read in its real context.
    var topLevelBlocks: () -> [NSRange] = { [] }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        // A new width rewraps the text; keep the text in view in place, as when the outline
        // opens. While the user drags the window's edge, AppKit's own behavior is left alone.
        if widthChanged, !inLiveResize { keepReadingPosition() }
        super.setFrameSize(newSize)
        updateColumnInsets()
        if widthChanged {
            onWidthChange?()
            if formatBar?.isHidden == false { updateFormatBar() }
        }
    }

    /// Centers a column no wider than the theme's width; wider windows add margin on both sides.
    private func updateColumnInsets() {
        let column = frame.width >= 1400 ? theme.wideColumnWidth : theme.columnWidth
        let horizontal = max(theme.pageMargin, (frame.width - column) / 2)
        let inset = NSSize(width: horizontal, height: theme.topMargin)
        if textContainerInset != inset {
            textContainerInset = inset
        }
    }

    // MARK: - Images

    /// The saved document's folder, or nil for an untitled document. Set by the editor.
    var documentFolder: URL?

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL]
    }

    override func dragOperation(for dragInfo: NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        imageFiles(on: dragInfo.draggingPasteboard).isEmpty ? super.dragOperation(for: dragInfo, type: type) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = imageFiles(on: sender.draggingPasteboard)
        guard !files.isEmpty else { return super.performDragOperation(sender) }
        let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        insertImages(files, at: index)
        return true
    }

    /// Pastes image files copied in Finder, or image data such as a screenshot.
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let files = imageFiles(on: pasteboard)
        if !files.isEmpty {
            insertImages(files, at: selectedRange().location, replacing: selectedRange())
            return
        }
        if pasteboard.string(forType: .string) == nil, let image = NSImage(pasteboard: pasteboard) {
            do {
                let path = try ImageImporter(documentFolder: documentFolder).reference(forPasted: image)
                insertImageMarkdown([ImageImporter.markdown(for: path)], at: selectedRange().location, replacing: selectedRange())
            } catch {
                presentImageError(error)
            }
            return
        }
        super.paste(sender)
    }

    /// Format ▸ Image…: choose image files to insert at the cursor.
    @objc func insertImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = "Insert"
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            self.insertImages(panel.urls, at: self.selectedRange().location, replacing: self.selectedRange())
        }
    }

    private func imageFiles(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter(ImageImporter.isImage)
    }

    private func insertImages(_ files: [URL], at index: Int, replacing selection: NSRange? = nil) {
        let importer = ImageImporter(documentFolder: documentFolder)
        var snippets: [String] = []
        for file in files {
            do {
                snippets.append(ImageImporter.markdown(for: try importer.reference(for: file)))
            } catch {
                presentImageError(error)
            }
        }
        insertImageMarkdown(snippets, at: index, replacing: selection)
    }

    /// Inserts images as their own paragraphs, so each one renders as a picture.
    private func insertImageMarkdown(_ snippets: [String], at index: Int, replacing selection: NSRange? = nil) {
        guard !snippets.isEmpty else { return }
        window?.makeFirstResponder(self)
        insertBlock(snippets.joined(separator: "\n\n"),
                    replacing: selection ?? NSRange(location: min(index, (string as NSString).length), length: 0))
    }

    private func presentImageError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Couldn’t insert the image."
        alert.informativeText = error.localizedDescription
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Links

    /// ⌘-click opens a link; a plain click edits it like any other text.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let url = linkURL(at: event) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    /// Shows the pointing hand while ⌘ is held over a link.
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if event.modifierFlags.contains(.command), linkURL(at: event) != nil {
            NSCursor.pointingHand.set()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        Self.removeUnwantedItems(from: menu)
        if let url = linkURL(at: event) {
            let open = NSMenuItem(title: "Open Link", action: #selector(openLink(_:)), keyEquivalent: "")
            let copy = NSMenuItem(title: "Copy Link", action: #selector(copyLink(_:)), keyEquivalent: "")
            for item in [open, copy] {
                item.target = self
                item.representedObject = url
            }
            menu.insertItem(open, at: 0)
            menu.insertItem(copy, at: 1)
            menu.insertItem(.separator(), at: 2)
        } else if let sizes = imageSizeMenu(at: convert(event.locationInWindow, from: nil)) {
            let item = NSMenuItem(title: "Image Size", action: nil, keyEquivalent: "")
            item.submenu = sizes
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        return menu
    }

    /// The font and color panels do nothing in a plain-text editor, and vertical layout
    /// breaks a Markdown document, so the system's text menu loses those items.
    private static func removeUnwantedItems(from menu: NSMenu) {
        let unwanted: Set<Selector> = [
            #selector(NSTextView.changeLayoutOrientation(_:)),
            #selector(NSFontManager.orderFrontFontPanel(_:)),
            #selector(NSApplication.orderFrontColorPanel(_:)),
        ]
        for item in menu.items {
            if let action = item.action, unwanted.contains(action) {
                menu.removeItem(item)
            } else if let submenu = item.submenu {
                removeUnwantedItems(from: submenu)
                if submenu.items.allSatisfy(\.isSeparatorItem) { menu.removeItem(item) }
            }
        }
        // Drop separators left at either end or next to each other.
        for item in menu.items.reversed() where item.isSeparatorItem {
            let index = menu.index(of: item)
            if index == 0 || index == menu.numberOfItems - 1 || menu.items[index - 1].isSeparatorItem {
                menu.removeItem(item)
            }
        }
    }

    /// Never lay the document out vertically; the menu no longer offers it, but other paths might.
    override func setLayoutOrientation(_ orientation: NSLayoutManager.TextLayoutOrientation) {
        super.setLayoutOrientation(.horizontal)
    }

    // MARK: - Image size

    /// A size choice from an image's right-click menu: the image's line and the line rewritten.
    private struct ImageSizeChoice {
        let range: NSRange
        let line: String
    }

    /// The Image Size submenu for a point on a line holding only an image, or nil.
    private func imageSizeMenu(at point: NSPoint) -> NSMenu? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).contains(containerPoint) else { return nil }

        let text = string as NSString
        var start = 0, contentsEnd = 0
        text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd,
                          for: NSRange(location: layoutManager.characterIndexForGlyph(at: glyph), length: 0))
        let range = NSRange(location: start, length: contentsEnd - start)
        guard let image = ImageLine(text.substring(with: range)) else { return nil }

        let menu = NSMenu()
        for size in ImageSize.allCases {
            let item = NSMenuItem(title: size.title, action: #selector(chooseImageSize(_:)), keyEquivalent: "")
            item.target = self
            item.state = image.width == size.width ? .on : .off
            item.representedObject = ImageSizeChoice(range: range, line: image.settingWidth(size.width))
            menu.addItem(item)
        }
        return menu
    }

    @objc private func chooseImageSize(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ImageSizeChoice else { return }
        // Keep the caret where it was, shifted if it sits after the rewritten line.
        let caret = selectedRange()
        let shift = (choice.line as NSString).length - choice.range.length
        let location = caret.location >= NSMaxRange(choice.range) ? caret.location + shift
            : min(caret.location, choice.range.location + (choice.line as NSString).length)
        edit(choice.range, with: choice.line, selection: NSRange(location: location, length: 0))
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.open(url) }
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func linkURL(at event: NSEvent) -> URL? {
        linkURL(at: convert(event.locationInWindow, from: nil))
    }

    /// The link under a point in view coordinates, if the point is on a link's text.
    func linkURL(at point: NSPoint) -> URL? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard glyphRect.contains(containerPoint) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard index < textStorage.length else { return nil }
        return textStorage.attribute(.linkTarget, at: index, effectiveRange: nil) as? URL
    }

    // MARK: - Return key

    override func insertNewline(_ sender: Any?) {
        let caret = selectedRange()
        let text = string as NSString
        let lineRange = text.lineRange(for: caret)
        let line = text.substring(with: lineRange) as NSString

        guard caret.length == 0,
              let match = Self.continuationRegex.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length)),
              caret.location >= lineRange.location + NSMaxRange(match.range)
        else {
            super.insertNewline(sender)
            return
        }

        let body = line.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            // Return on an empty item ends the list: remove the marker and stay on this line.
            let marker = NSRange(location: lineRange.location, length: match.range.length)
            edit(marker, with: "", selection: NSRange(location: lineRange.location, length: 0))
            return
        }

        insertText("\n" + continuationPrefix(for: line, match: match), replacementRange: caret)
    }

    private func continuationPrefix(for line: NSString, match: NSTextCheckingResult) -> String {
        let indent = line.substring(with: match.range(at: 1))
        let marker = line.substring(with: match.range(at: 2))

        if match.range(at: 3).location != NSNotFound {
            let number = Int(line.substring(with: match.range(at: 3))) ?? 0
            return "\(indent)\(number + 1). "
        }
        if marker.hasPrefix(">") {
            return "\(indent)> "
        }
        let bullet = marker.prefix(1)
        return marker.contains("[") ? "\(indent)\(bullet) [ ] " : "\(indent)\(bullet) "
    }

    // MARK: - Format menu

    @objc func toggleBold(_ sender: Any?) { wrapSelection("**") }
    @objc func toggleItalic(_ sender: Any?) { wrapSelection("*") }
    @objc func toggleStrikethrough(_ sender: Any?) { wrapSelection("~~") }
    @objc func toggleInlineCode(_ sender: Any?) { wrapSelection("`") }

    @objc func insertLink(_ sender: Any?) {
        let range = selectedRange()
        let label = range.length > 0 ? (string as NSString).substring(with: range) : "link text"
        let url = "https://"
        let replacement = "[\(label)](\(url))"
        let urlStart = range.location + (("[" + label + "](") as NSString).length
        edit(range, with: replacement, selection: NSRange(location: urlStart, length: (url as NSString).length))
    }

    /// Wraps the selection in `marker`, or removes the marker if the selection is already wrapped.
    private func wrapSelection(_ marker: String) {
        let range = selectedRange()
        let text = string as NSString
        let selected = text.substring(with: range)
        let length = (marker as NSString).length

        let hasBefore = range.location >= length
            && text.substring(with: NSRange(location: range.location - length, length: length)) == marker
        let afterStart = NSMaxRange(range)
        let hasAfter = afterStart + length <= text.length
            && text.substring(with: NSRange(location: afterStart, length: length)) == marker

        if hasBefore && hasAfter {
            let outer = NSRange(location: range.location - length, length: range.length + 2 * length)
            edit(outer, with: selected, selection: NSRange(location: outer.location, length: range.length))
        } else {
            let inner = NSRange(location: range.location + length, length: range.length)
            edit(range, with: marker + selected + marker, selection: inner)
        }
    }

    // MARK: - Editing

    /// Replaces `range` through the text system so undo and change notifications work.
    func edit(_ range: NSRange, with replacement: String, selection: NSRange) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selection)
    }
}
