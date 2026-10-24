import AppKit

/// Task checkboxes: a click on a drawn box checks or unchecks it, and Toggle Checked (⌘L, as in
/// Obsidian) does the same for the selected lines. Either way it is one undoable edit of the `[ ]`.
extension MarkdownTextView {

    /// Groups: 1 quote markers and indentation, 2 the list marker, 3 the box's state character.
    private static let taskPrefix = try! NSRegularExpression(
        pattern: "^((?:[ \\t]*>[ \\t]?)*[ \\t]*)(?:([-*+]|\\d+[.)])(?:[ \\t]+|$)(?:\\[([ xX])\\](?:[ \\t]+|$))?)?")

    /// How far around a drawn box a click still counts, so the small box is easy to hit.
    private static let checkboxSlop: CGFloat = 4

    // MARK: - Clicking

    /// The list marker of the task whose drawn box is under a point in view coordinates.
    /// A box is drawn only off the line being edited, and never in source view.
    func checkboxMarker(at point: NSPoint) -> NSRange? {
        guard let layoutManager = layoutManager as? MarkdownLayoutManager, let textContainer, let textStorage,
              textStorage.length > 0 else { return nil }
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        // The box sits left of the text, so the nearest character is on its line.
        let glyph = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let index = min(layoutManager.characterIndexForGlyph(at: glyph), textStorage.length - 1)
        let line = (string as NSString).lineRange(for: NSRange(location: index, length: 0))
        var marker = NSRange()
        guard let symbol = textStorage.attribute(.listBullet, at: line.location, effectiveRange: &marker) as? String,
              symbol == "☐" || symbol == "☑" else { return nil }
        let box = layoutManager.checkboxRect(at: marker.location)
        guard box.insetBy(dx: -Self.checkboxSlop, dy: -Self.checkboxSlop).contains(containerPoint) else { return nil }
        return marker
    }

    /// Checks or unchecks the box under a point in view coordinates. Returns whether there was one.
    /// The selection stays where it is, so the line stays rendered and the box flips in place.
    @discardableResult
    func toggleCheckbox(at point: NSPoint) -> Bool {
        guard let marker = checkboxMarker(at: point) else { return false }
        let text = string as NSString
        let lineRange = text.lineRange(for: marker)
        guard let state = taskParts(text.substring(with: lineRange))?.stateRange else { return false }
        let box = NSRange(location: lineRange.location + state.location, length: 1)
        let replacement = text.substring(with: box) == " " ? "x" : " "
        let selection = selectedRanges
        guard shouldChangeText(in: box, replacementString: replacement) else { return false }
        replaceCharacters(in: box, with: replacement)
        didChangeText()
        undoManager?.setActionName("Toggle Checked")
        selectedRanges = selection
        return true
    }

    // MARK: - Toggle Checked

    /// Checks the tasks on the selected lines, or unchecks them if all are checked already. Like
    /// Obsidian, a line that isn't a task becomes an open one, keeping its quote markers, indentation
    /// and list marker.
    @objc func toggleChecked(_ sender: Any?) {
        let hadSelection = selectedRange().length > 0
        let caret = selectedRange().location
        let text = string as NSString
        let firstLine = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))

        var anyOpen = false
        for line in selectedLines() {
            if let state = taskParts(line)?.state, state == " " { anyOpen = true }
        }
        var firstLineGrowth = 0
        var firstLineEdit = Int.max
        transformSelectedLines { lines in
            lines.enumerated().map { offset, line in
                guard let parts = self.taskParts(line) else { return line }
                let ns = line as NSString
                let result: String
                let editAt: Int
                if let stateRange = parts.stateRange {
                    result = ns.replacingCharacters(in: stateRange, with: anyOpen ? "x" : " ")
                    editAt = stateRange.location
                } else if let markerEnd = parts.markerEnd {
                    // "- item" or "1. item": the box goes after the marker's space. A bare "-" gets a space first.
                    result = ns.replacingCharacters(in: NSRange(location: markerEnd, length: 0),
                                                    with: parts.markerHasSpace ? "[ ] " : " [ ] ")
                    editAt = markerEnd
                } else {
                    result = ns.replacingCharacters(in: NSRange(location: parts.prefixEnd, length: 0), with: "- [ ] ")
                    editAt = parts.prefixEnd
                }
                if offset == 0 {
                    firstLineGrowth = (result as NSString).length - ns.length
                    firstLineEdit = editAt
                }
                return result
            }
        }
        undoManager?.setActionName("Toggle Checked")
        guard !hadSelection else { return }
        // Keep the caret on the same character; text added before it pushes it along.
        let column = caret - firstLine.location
        let moved = column >= firstLineEdit ? column + firstLineGrowth : column
        setSelectedRange(NSRange(location: firstLine.location + max(0, moved), length: 0))
    }

    /// A line's task structure, or nil for a blank line (nothing after its quote markers and indentation).
    /// `prefixEnd` is where the quote markers and indentation end, `markerEnd` where the list marker and its
    /// space end, and `stateRange` the character inside the box.
    private func taskParts(_ line: String)
        -> (prefixEnd: Int, markerEnd: Int?, markerHasSpace: Bool, stateRange: NSRange?, state: String?)? {
        let ns = line as NSString
        guard let match = Self.taskPrefix.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let prefixEnd = NSMaxRange(match.range(at: 1))
        let marker = match.range(at: 2)
        guard marker.location != NSNotFound || prefixEnd < ns.length else { return nil }
        let stateRange = match.range(at: 3).location != NSNotFound ? match.range(at: 3) : nil
        let markerEnd = marker.location != NSNotFound ? NSMaxRange(match.range) : nil
        return (prefixEnd, markerEnd, markerEnd.map { $0 > NSMaxRange(marker) } ?? false,
                stateRange, stateRange.map { ns.substring(with: $0) })
    }
}
