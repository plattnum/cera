import AppKit

/// Keeps a text view's Markdown styling up to date without restyling the whole
/// document on every change:
///
/// - Typing restyles only the top-level blocks around the edit.
/// - Moving the cursor to another line restyles only the blocks it left and entered,
///   since that is where markers appear and disappear.
/// - A full restyle (opening a file, changing theme or width) styles the first part
///   right away and the rest in the background, a region at a time.
final class LiveStyler {
    struct Settings {
        var theme: Theme
        var baseURL: URL?
        var availableWidth: CGFloat
        var joinsHardWrappedLines = false
        /// Style the text as Markdown source (see `SourceStyler`) instead of rendering it.
        var showsSource = false
    }

    private let storage: NSTextStorage
    private var settings: Settings
    /// Line ranges of the document's top-level blocks, kept in step with edits.
    private(set) var blocks: [NSRange] = []
    /// The document's front matter, kept in step with edits like `blocks`.
    private var frontMatter: NSRange?
    /// The document's link reference definitions, kept in step with edits like `blocks`.
    private var foundDefinitions: [MarkdownStyler.Definition] = []
    private var definitions = ""
    /// Increments on every full restyle, so a stale background pass stops.
    private var generation = 0
    /// Regions of the current full restyle still waiting to be styled.
    private(set) var pendingRegions: [NSRange] = []
    /// The latest cursor position, used by background styling.
    private var caret = 0

    /// The size of the regions a full restyle is split into.
    private let regionLength: Int

    init(storage: NSTextStorage, settings: Settings, regionLength: Int = MarkdownStyler.regionLength) {
        self.storage = storage
        self.settings = settings
        self.regionLength = regionLength
    }

    var isStylingInBackground: Bool { !pendingRegions.isEmpty }

    // MARK: - Full restyle

    /// Restyles the whole document. Regions up to `immediateLength` are styled now;
    /// the rest follow on the main queue, one region per turn of the run loop.
    func restyleAll(caret: Int, settings: Settings? = nil, immediateLength: Int = 64_000) {
        if let settings { self.settings = settings }
        self.caret = caret
        generation += 1
        let text = NSString(string: storage.string)
        (blocks, foundDefinitions) = MarkdownStyler.structure(in: text)
        frontMatter = FrontMatter.range(in: text)
        definitions = MarkdownStyler.definitionText(foundDefinitions)
        pendingRegions = MarkdownStyler.regions(covering: blocks, length: text.length, target: regionLength)
        if text.length == 0 {
            storage.setAttributes(MarkdownStyler(theme: self.settings.theme).bodyAttributes(), range: NSRange(location: 0, length: 0))
        }

        var styled = 0
        while let region = pendingRegions.first, styled < immediateLength {
            pendingRegions.removeFirst()
            style(region, text: text, caret: caret)
            styled += region.length
        }
        scheduleNextRegion(generation: generation)
    }

    private func scheduleNextRegion(generation: Int) {
        guard !pendingRegions.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == generation, !self.pendingRegions.isEmpty else { return }
            let region = self.pendingRegions.removeFirst()
            self.style(region, text: NSString(string: self.storage.string), caret: self.caret)
            self.scheduleNextRegion(generation: generation)
        }
    }

    /// Finishes any background styling now. Used by tests and before saving a snapshot.
    func finishBackgroundStyling(caret: Int) {
        let text = NSString(string: storage.string)
        while !pendingRegions.isEmpty {
            style(pendingRegions.removeFirst(), text: text, caret: caret)
        }
    }

    // MARK: - Edits

    /// Restyles after the characters in `editedRange` (new coordinates) replaced
    /// `editedRange.length - delta` old characters.
    ///
    /// `previousLine` is the start of the line the cursor was on before the edit (old
    /// coordinates). Some edits, such as Undo, change text and move the cursor at once;
    /// the line the cursor left must hide its markers again.
    func textChanged(editedRange: NSRange, delta: Int, caret: Int, previousLine: Int? = nil) {
        self.caret = caret
        let text = NSString(string: storage.string)
        guard !blocks.isEmpty else {
            restyleAll(caret: caret)
            return
        }

        // Old coordinates of the edit.
        let oldStart = editedRange.location
        let oldEnd = NSMaxRange(editedRange) - delta

        // Front matter changes how everything in it parses, so an edit that makes, moves, or breaks its
        // closing line restyles the document.
        if frontMatterChanged(by: editedRange, delta: delta, in: text) {
            restyleAll(caret: caret)
            return
        }

        // The blocks the edit touches, plus one on each side, since an edit can merge
        // or split blocks (deleting a blank line, typing a --- under a paragraph).
        let firstTouched = blocks.firstIndex { NSMaxRange($0) >= oldStart } ?? blocks.count
        let lastTouched = blocks.lastIndex { $0.location <= oldEnd } ?? -1
        let first = max(0, min(firstTouched, lastTouched) - 1)
        let last = min(blocks.count - 1, max(firstTouched, lastTouched) + 1)

        var regionStart = min(blocks[first].location, oldStart)
        var regionEnd = max(NSMaxRange(blocks[last]) + delta, NSMaxRange(editedRange))
        regionStart = text.lineRange(for: NSRange(location: min(regionStart, text.length), length: 0)).location
        regionEnd = min(text.length, max(regionEnd, regionStart))
        if regionEnd < text.length {
            regionEnd = NSMaxRange(text.lineRange(for: NSRange(location: max(regionStart, regionEnd - 1), length: 0)))
        }

        // Re-parse the region, growing it while the blocks at its edges would join a
        // neighbor: Markdown structure can shift beyond the blocks next to an edit.
        var newBlocks: [NSRange] = []
        var newDefinitions: [MarkdownStyler.Definition] = []
        while true {
            // Take in the gaps on both sides up to the neighboring blocks: gaps hold blank
            // lines and link definitions, which an edit can merge into a block.
            regionStart = blocks.last(where: { NSMaxRange($0) <= regionStart }).map(NSMaxRange) ?? 0
            regionEnd = blocks.first(where: { $0.location >= regionEnd - delta }).map { $0.location + delta } ?? text.length
            let region = NSRange(location: regionStart, length: regionEnd - regionStart)
            // An unbalanced code fence changes how everything after it parses.
            if MarkdownStyler.leavesFenceOpen(text, region: region), NSMaxRange(region) < text.length {
                restyleAll(caret: caret)
                return
            }
            (newBlocks, newDefinitions) = MarkdownStyler.structure(in: text, region: region)

            if let previous = blocks.last(where: { NSMaxRange($0) <= regionStart }) {
                let windowEnd = newBlocks.first.map(NSMaxRange) ?? regionEnd
                let check = MarkdownStyler.topLevelBlocks(
                    in: text, region: NSRange(location: previous.location, length: windowEnd - previous.location))
                if check.first != previous {
                    regionStart = previous.location
                    continue
                }
            }
            if let nextOld = blocks.first(where: { $0.location >= regionEnd - delta }) {
                let next = NSRange(location: nextOld.location + delta, length: nextOld.length)
                let windowStart = newBlocks.last?.location ?? regionStart
                let check = MarkdownStyler.topLevelBlocks(
                    in: text, region: NSRange(location: windowStart, length: NSMaxRange(next) - windowStart))
                if check.last != next {
                    regionEnd = NSMaxRange(next)
                    continue
                }
            }
            break
        }
        let region = NSRange(location: regionStart, length: regionEnd - regionStart)

        // Splice the region's new blocks into the block list. Blocks before the region
        // are untouched; blocks after it move by `delta`.
        let oldRegionEnd = NSMaxRange(region) - delta
        let before = blocks.prefix { NSMaxRange($0) <= region.location }
        let after = blocks.filter { $0.location >= oldRegionEnd }
            .map { NSRange(location: $0.location + delta, length: $0.length) }
        blocks = Array(before) + newBlocks + after
        realignPendingRegions(afterEditEndingAt: oldEnd, delta: delta)
        foundDefinitions = foundDefinitions.filter { $0.location < region.location }
            + newDefinitions
            + foundDefinitions.filter { $0.location >= oldRegionEnd }.map { .init(location: $0.location + delta, text: $0.text) }

        // Link reference definitions affect every block that uses them, wherever it is.
        let updated = MarkdownStyler.definitionText(foundDefinitions)
        if updated != definitions {
            restyleAll(caret: caret)
            return
        }
        style(region, text: text, caret: caret)

        if let previousLine {
            let moved = previousLine >= oldEnd ? previousLine + delta : previousLine
            if !NSLocationInRange(moved, region),
               let block = block(containing: moved) {
                style(block, text: text, caret: caret)
            }
        }
    }

    /// Restyles the blocks holding the old and new cursor lines, so their markers show or hide.
    func caretMoved(fromLineAt oldLocation: Int, toLineAt newLocation: Int, caret: Int) {
        self.caret = caret
        // Source shows every marker on every line; nothing changes with the cursor.
        guard !settings.showsSource else { return }
        let text = NSString(string: storage.string)
        var regions: [NSRange] = []
        for location in [oldLocation, newLocation] {
            if let block = block(containing: location),
               !regions.contains(where: { NSEqualRanges($0, block) }) {
                regions.append(block)
            }
        }
        for region in regions where NSMaxRange(region) <= text.length {
            style(region, text: text, caret: caret)
        }
    }

    // MARK: - Private

    /// Updates `frontMatter` after an edit, and returns whether it changed other than by the edit's own
    /// length. It is looked for again only when the edit could change it: on the first line, inside it, or,
    /// with an opening line and no front matter yet, on a line that could close it.
    private func frontMatterChanged(by editedRange: NSRange, delta: Int, in text: NSString) -> Bool {
        let firstLine = text.lineRange(for: NSRange(location: 0, length: 0))
        let expected: NSRange?
        let mayChange: Bool
        if let old = frontMatter, editedRange.location <= NSMaxRange(old) {
            expected = NSRange(location: 0, length: old.length + delta)
            mayChange = true
        } else {
            expected = frontMatter
            let edited = text.lineRange(for: NSRange(location: min(editedRange.location, text.length), length: editedRange.length))
            mayChange = editedRange.location < NSMaxRange(firstLine)
                || (frontMatter == nil && FrontMatter.opens(text)
                    && text.substring(with: edited).components(separatedBy: .newlines).contains(where: FrontMatter.isFence))
        }
        guard mayChange else { return false }
        frontMatter = FrontMatter.range(in: text)
        return frontMatter != expected
    }

    /// The block containing `location`, by binary search (blocks are in order and don't overlap).
    private func block(containing location: Int) -> NSRange? {
        var low = 0
        var high = blocks.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let block = blocks[middle]
            if location < block.location {
                high = middle - 1
            } else if location >= NSMaxRange(block) {
                low = middle + 1
            } else {
                return block
            }
        }
        return nil
    }

    /// Keeps a background pass going through an edit: regions after the edit move by
    /// `delta`, and every region is widened to whole blocks of the updated block list.
    private func realignPendingRegions(afterEditEndingAt oldEnd: Int, delta: Int) {
        guard !pendingRegions.isEmpty else { return }
        let length = storage.length
        pendingRegions = pendingRegions.compactMap { region in
            var start = region.location
            var end = NSMaxRange(region)
            if start >= oldEnd { start += delta }
            if end >= oldEnd { end += delta }
            start = min(max(0, start), length)
            end = min(max(start, end), length)
            if let block = block(containing: start) { start = block.location }
            if end > start, let block = block(containing: end - 1) { end = NSMaxRange(block) }
            return end > start ? NSRange(location: start, length: end - start) : nil
        }
    }

    private func style(_ region: NSRange, text: NSString, caret: Int) {
        guard region.length > 0, NSMaxRange(region) <= text.length else { return }
        if settings.showsSource {
            SourceStyler.styleRegion(storage, text: text, region: region, theme: settings.theme)
            return
        }
        MarkdownStyler(theme: settings.theme, joinsHardWrappedLines: settings.joinsHardWrappedLines).styleRegion(
            storage, text: text, region: region, caret: caret, baseURL: settings.baseURL,
            availableWidth: settings.availableWidth, definitions: definitions)
    }
}
