import AppKit
import SwiftUI

/// The smallest edit that turns one text into another: the changed middle, after the
/// shared start and end. Applying only this keeps the caret and scroll position put.
struct TextChange {
    let range: NSRange
    let replacement: String

    init(from old: String, to new: String) {
        let a = old as NSString, b = new as NSString
        let shortest = min(a.length, b.length)
        var start = 0
        while start < shortest, a.character(at: start) == b.character(at: start) { start += 1 }
        var shared = 0 // characters shared at the end, not overlapping the shared start
        while shared < shortest - start, a.character(at: a.length - 1 - shared) == b.character(at: b.length - 1 - shared) {
            shared += 1
        }
        // Never cut through a character made of several UTF-16 units, such as an emoji.
        while start > 0, Self.splits(a, at: start) || Self.splits(b, at: start) { start -= 1 }
        while shared > 0, Self.splits(a, at: a.length - shared) || Self.splits(b, at: b.length - shared) { shared -= 1 }

        range = NSRange(location: start, length: a.length - shared - start)
        replacement = b.substring(with: NSRange(location: start, length: b.length - shared - start))
    }

    private static func splits(_ text: NSString, at index: Int) -> Bool {
        index < text.length && text.rangeOfComposedCharacterSequence(at: index).location < index
    }
}

/// What to do when the open file changes on disk.
enum DiskChange: Equatable {
    /// Nothing changed, such as Cera's own save coming back.
    case ignore
    /// Show the new contents; there's nothing of the user's to lose.
    case reload
    /// The user has unsaved edits; let them choose.
    case ask

    static func action(disk: String, editor: String, hasUnsavedEdits: Bool) -> DiskChange {
        if disk == editor { return .ignore }
        return hasUnsavedEdits ? .ask : .reload
    }
}

/// Watches a file and reports when its contents change, whether it is written in place
/// or replaced by a new file (as editors, agents, and Cera's own saves do). After a
/// replacement it carries on watching the new file at the same path.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var stopped = false

    /// Starts watching `url`. `onChange` runs on the main queue.
    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        watch(retries: 0)
    }

    deinit {
        source?.cancel()
    }

    func stop() {
        stopped = true
        source?.cancel()
        source = nil
    }

    /// Opens the file at `url` and listens to it. When it isn't there, which happens for a
    /// moment during a replacement, tries again shortly, for up to about five seconds.
    private func watch(retries: Int) {
        guard !stopped else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            if retries < 50 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.watch(retries: retries + 1) }
            }
            return
        }
        // A file that reappears after a replacement has new contents.
        if retries > 0 { onChange() }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename, .revoke], queue: .main)
        source.setEventHandler { [weak self, unowned source] in
            guard let self, !self.stopped else { return }
            if source.data.isDisjoint(with: [.delete, .rename, .revoke]) {
                self.onChange()
            } else {
                // The file we were watching is gone or moved away; follow the path to its replacement.
                source.cancel()
                self.source = nil
                self.watch(retries: 1)
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source?.cancel()
        self.source = source
        source.resume()
    }

    /// The file's text and modification date, read in coordination with other writers.
    static func read(_ url: URL) -> (text: String, modified: Date)? {
        var result: (String, Date)?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: nil) { url in
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8),
                  let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            else { return }
            result = (text, modified)
        }
        return result
    }
}

extension MarkdownTextView {
    /// Replaces the text by its smallest changed range, without an undo action, so text
    /// that didn't change keeps its place and the caret moves with the text around it.
    func replaceText(with text: String) {
        guard let textStorage else { return }
        let change = TextChange(from: string, to: text)
        guard change.range.length > 0 || !change.replacement.isEmpty else { return }
        textStorage.replaceCharacters(in: change.range, with: change.replacement)
    }

    /// Replaces the text like `replaceText(with:)`, runs `restyle`, and scrolls so the text
    /// that was in view stays in the same place on screen.
    func replaceTextKeepingPosition(with text: String, restyle: () -> Void) {
        let change = TextChange(from: string, to: text)
        // At the very top, stay at the top, so text added there is seen.
        let top = visibleRect.minY - textContainerOrigin.y
        guard let layoutManager, let textContainer, top > 0 else {
            replaceText(with: text)
            restyle()
            return
        }
        // Anchor on the first line in view: its first character and how far above the window's top edge it starts.
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: top), in: textContainer)
        let anchor = layoutManager.characterIndexForGlyph(at: glyph)
        let offset = top - layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY

        replaceText(with: text)
        restyle()

        // Where the anchor character is now: shifted by the change before it, or the change's start if it was inside it.
        let delta = (change.replacement as NSString).length - change.range.length
        let moved = anchor >= NSMaxRange(change.range) ? anchor + delta : min(anchor, change.range.location)
        let length = (string as NSString).length
        guard length > 0 else { return }
        let target = min(moved, length - 1)
        // Lay out everything above for real; estimated heights would put the anchor in the wrong place.
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: target + 1))
        let line = layoutManager.lineFragmentRect(
            forGlyphAt: layoutManager.glyphIndexForCharacter(at: target), effectiveRange: nil)
        scroll(NSPoint(x: visibleRect.minX, y: line.minY + offset + textContainerOrigin.y))
    }
}

/// Keeps an open document in step with its file on disk. When an agent or another app
/// changes the file, the editor shows the new text; if the user has unsaved edits, the
/// window asks first. Saving over a changed file is still caught by the system's
/// "changed by another application" alert.
///
/// Reloading goes through the system's Revert, so the document's own record of the file
/// (its date, edited state, and undo history) always matches what is on disk.
@MainActor
final class DiskSync: ObservableObject {
    /// True while the file has changed on disk under unsaved edits, until the user chooses.
    @Published private(set) var changedUnderEdits = false

    private var watcher: FileWatcher?
    private var url: URL?
    private weak var document: MarkdownDocument?
    private var pendingCheck: DispatchWorkItem?
    /// The text last seen in the file. The editor holds unsaved edits when its text differs;
    /// the system's edited flag can't be used, as it lags behind typing.
    private var savedText = ""

    /// Watches `url` for `document`; nil (an untitled document) watches nothing.
    func watch(_ url: URL?, for document: MarkdownDocument) {
        guard url != self.url || self.document !== document else { return }
        stop()
        changedUnderEdits = false
        self.url = url
        self.document = document
        savedText = document.text
        guard let url else { return }
        watcher = FileWatcher(url: url) { [weak self] in self?.checkSoon() }
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        pendingCheck?.cancel()
    }

    /// Replaces the user's unsaved edits with the file's contents.
    func loadFromDisk() {
        revert()
    }

    /// Saves the user's version over the file's.
    func keepMine() {
        guard let url, let document else { return }
        var failure: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: nil) { url in
            do { try Data(document.text.utf8).write(to: url, options: .atomic) } catch { failure = error }
        }
        if let failure {
            NSAlert(error: failure).runModal()
            return
        }
        // Reverting to what was just written changes no text, but tells the document the file is its own again.
        revert()
    }

    /// Writers often save in several steps (empty the file, then fill it), so wait for
    /// a burst of changes to settle before reading.
    private func checkSoon() {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func check() {
        guard let url, let document, let disk = FileWatcher.read(url) else { return }
        switch DiskChange.action(disk: disk.text, editor: document.text, hasUnsavedEdits: document.text != savedText) {
        case .ignore:
            savedText = disk.text
            changedUnderEdits = false
        case .reload:
            revert()
        case .ask:
            changedUnderEdits = true
        }
    }

    /// Reloads the document from its file through the system's Revert. The window then gets
    /// a new document object, which `watch` picks up; the editor applies only the text that
    /// changed, so the caret and scroll position stay.
    private func revert() {
        guard let url, let platformDocument = NSDocumentController.shared.document(for: url),
              let type = platformDocument.fileType else { return }
        do {
            try platformDocument.revert(toContentsOf: url, ofType: type)
            changedUnderEdits = false
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// The strip across the top of the window when the file changed under unsaved edits.
struct DiskChangeBanner: View {
    var theme: Theme
    var keepMine: () -> Void
    var loadFromDisk: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("This file changed on disk.")
                .foregroundStyle(Color(nsColor: theme.text))
            Spacer()
            Button("Keep Mine", action: keepMine)
            Button("Load from Disk", action: loadFromDisk)
                .keyboardShortcut(.defaultAction)
        }
        .font(.system(size: 12))
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Color(nsColor: theme.rule).frame(height: 1) }
    }
}
