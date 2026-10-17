import AppKit

/// The list of languages offered after typing ``` at the start of a code block.
enum CodeLanguagePicker {
    /// Names offered: the languages Cera highlights, and Mermaid, which it draws.
    static let names: [String] = (CodeLanguages.all.map(\.name) + ["mermaid"]).sorted()

    /// The names matching what has been typed after the fence: an exact name or alias first,
    /// then names starting with it, then the languages with an alias starting with it.
    static func candidates(for typed: String) -> [String] {
        let typed = typed.lowercased()
        guard !typed.isEmpty else { return names }
        var result: [String] = []
        func add(_ name: String) { if !result.contains(name) { result.append(name) } }
        if names.contains(typed) { add(typed) }
        if let language = CodeLanguages.language(info: typed) { add(language.name) }
        for name in names where name.hasPrefix(typed) { add(name) }
        for language in CodeLanguages.all where language.aliases.contains(where: { $0.hasPrefix(typed) }) { add(language.name) }
        return result
    }

    /// An opening fence line being typed: quote and list markers, the fence, then letters.
    static let fenceLineRegex = try! NSRegularExpression(
        pattern: "^(?:[ \\t]*>[ \\t]?|[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+|[ \\t])*(?:`{3,}|~{3,})([A-Za-z0-9_+#.-]*)$")
}

extension MarkdownTextView {
    /// While the cursor ends an opening fence line, the language typed after the fence (possibly
    /// empty), which the language list completes. Nil anywhere else, including on a closing fence.
    func fenceLanguageRange() -> NSRange? {
        let selection = selectedRange()
        guard selectedRanges.count == 1, selection.length == 0 else { return nil }
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: selection.location, length: 0))
        var end = NSMaxRange(line)
        while end > line.location, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
        guard selection.location == end,
              let match = CodeLanguagePicker.fenceLineRegex.firstMatch(
                in: string, range: NSRange(location: line.location, length: end - line.location)),
              let block = fencedCodeBlock(at: selection.location),
              block.opening.location == line.location // It opens a block; it doesn't close one.
        else { return nil }
        return match.range(at: 1)
    }

    override var rangeForUserCompletion: NSRange {
        fenceLanguageRange() ?? super.rangeForUserCompletion
    }

    override func completions(forPartialWordRange charRange: NSRange,
                              indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard let range = fenceLanguageRange(), NSEqualRanges(range, charRange) else {
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }
        let typed = (string as NSString).substring(with: charRange)
        let candidates = CodeLanguagePicker.candidates(for: typed)
        // Nothing is chosen until a letter is typed, so Return right after ``` makes a plain block.
        index.pointee = typed.isEmpty ? -1 : 0
        return candidates.isEmpty ? nil : candidates
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        guard let range = fenceLanguageRange(), NSEqualRanges(range, charRange) else {
            super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
            return
        }
        // The default inserts each name while arrowing through the list; leave the text alone until
        // a choice is made.
        guard flag else { return }
        languageChosen = true
        switch movement {
        case NSReturnTextMovement, NSTabTextMovement:
            let typed = (string as NSString).substring(with: charRange)
            if word != typed, CodeLanguagePicker.names.contains(word) {
                // Not insertText: that is typing, and would open the list again.
                edit(charRange, with: word, selection: NSRange(location: charRange.location + (word as NSString).length, length: 0))
            }
            // Return also opens the block, closing its fence.
            if movement == NSReturnTextMovement { insertNewline(nil) }
        case NSCancelTextMovement:
            languagesDismissedOnLine = (string as NSString).lineRange(for: charRange).location
        default:
            break // Typing on: keep what was typed.
        }
    }

    /// Typing ``` at the start of a new block opens the language list; typing a name keeps it
    /// current, until nothing matches.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard !isOfferingLanguages, let range = fenceLanguageRange() else { return }
        let line = (self.string as NSString).lineRange(for: range).location
        guard languagesDismissedOnLine != line else { return }
        languagesDismissedOnLine = nil
        let typed = (self.string as NSString).substring(with: range)
        guard !CodeLanguagePicker.candidates(for: typed).isEmpty else { return }
        isOfferingLanguages = true
        languageChosen = false
        complete(nil) // Returns when the list closes.
        isOfferingLanguages = false
        // Closed without a choice: by Return with nothing selected, which opens a plain block, or by
        // Escape, which keeps the list away from this line.
        guard !languageChosen, let event = NSApp.currentEvent, event.type == .keyDown else { return }
        switch event.keyCode {
        case 36, 76: insertNewline(nil) // Return, Enter
        case 53: languagesDismissedOnLine = line // Escape
        default: break
        }
    }
}
