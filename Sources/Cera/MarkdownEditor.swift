import AppKit
import SwiftUI

/// Hosts a `MarkdownTextView` in SwiftUI and keeps its text in sync with the document.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var theme: Theme
    /// The document's folder, for resolving relative image paths.
    var baseURL: URL?
    var checksSpelling = false
    var joinsHardWrappedLines = false
    /// The document's undo manager. Edits registered on it mark the document as edited.
    var undoManager: UndoManager?
    /// The outline sidebar's model, told when the editor scrolls.
    var outline: OutlineModel?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// A scroll view holding a fresh editor that tracks the scroll view's width.
    static func makeScrollView() -> (NSScrollView, MarkdownTextView) {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        // Start at zero width: AppKit resizes the text view by adding the scroll
        // view's change in width, so any starting width would stay as extra width.
        let textView = MarkdownTextView.makeEditor(frame: .zero)
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = Self.makeScrollView()
        textView.delegate = context.coordinator
        textView.onWidthChange = { [weak coordinator = context.coordinator] in
            coordinator?.restyleSoon()
        }
        textView.textStorage?.delegate = context.coordinator

        context.coordinator.textView = textView
        outline?.textView = textView
        context.coordinator.observeScrolling(of: scrollView)

        textView.string = text
        context.coordinator.restyle()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.parent = self
        outline?.textView = textView
        textView.documentFolder = baseURL
        if textView.isContinuousSpellCheckingEnabled != checksSpelling {
            textView.isContinuousSpellCheckingEnabled = checksSpelling
        }
        // Only replace the text when it changed elsewhere (Open, New, or the file changing
        // on disk). Replacing it while typing would move the insertion point; replacing
        // just the part that changed, styled like typing, keeps the caret and the text in view.
        if textView.string != text {
            textView.replaceTextKeepingPosition(with: text) { context.coordinator.styleChangedText() }
        }
        if textView.theme.name != theme.name || context.coordinator.baseURL != baseURL
            || context.coordinator.joinsHardWrappedLines != joinsHardWrappedLines {
            context.coordinator.restyle()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownEditor
        weak var textView: MarkdownTextView?
        private var liveStyler: LiveStyler?
        private var activeLineStart = NSNotFound
        /// The characters changed since the last restyle, reported by the text storage.
        private var pendingEdit: (range: NSRange, delta: Int)?
        private var scheduledRestyle: DispatchWorkItem?

        /// The base URL and reflow setting the text was last styled with.
        private(set) var baseURL: URL?
        private(set) var joinsHardWrappedLines = false
        private var imageObserver: NSObjectProtocol?
        private var scrollObserver: NSObjectProtocol?

        init(parent: MarkdownEditor) {
            self.parent = parent
            super.init()
            // Web images arrive after the first styling pass.
            imageObserver = NotificationCenter.default.addObserver(forName: ImageStore.didLoad, object: nil, queue: .main) { [weak self] _ in
                self?.restyleSoon()
            }
        }

        deinit {
            if let imageObserver { NotificationCenter.default.removeObserver(imageObserver) }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        /// Tells the outline when the text in view changes: on scrolling and resizing. The
        /// copy button follows too, since scrolling moves a different block under the pointer.
        func observeScrolling(of scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.parent.outline?.visibleAreaChanged()
                    self?.textView?.updateCodeCopyButton()
                }
            }
        }

        // MARK: Edits

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return } // Our own styling changes only attributes.
            if let pending = pendingEdit {
                pendingEdit = (NSUnionRange(pending.range, editedRange), pending.delta + delta)
            } else {
                pendingEdit = (editedRange, delta)
            }
        }

        /// Typing and formatting commands register their undo actions with the document.
        func undoManager(for view: NSTextView) -> UndoManager? {
            parent.undoManager ?? view.window?.undoManager
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            styleChangedText()
        }

        /// Restyles just the blocks around the latest change to the text.
        func styleChangedText() {
            guard let textView else { return }
            let caret = textView.selectedRange().location
            if let edit = pendingEdit, let liveStyler {
                pendingEdit = nil
                liveStyler.textChanged(editedRange: edit.range, delta: edit.delta, caret: caret,
                                       previousLine: activeLineStart == NSNotFound ? nil : activeLineStart)
            } else {
                restyle()
            }
            activeLineStart = lineStart(at: caret)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            // Only the lines the cursor left and entered need restyling: that is where markers show or hide.
            let caret = textView.selectedRange().location
            let newLine = lineStart(at: caret)
            guard newLine != activeLineStart else { return }
            let oldLine = activeLineStart
            activeLineStart = newLine
            if oldLine != NSNotFound, pendingEdit == nil {
                liveStyler?.caretMoved(fromLineAt: oldLine, toLineAt: newLine, caret: caret)
            }
        }

        // MARK: Full restyle

        /// Restyles the whole document: on open, and when the theme, folder, or width changes.
        func restyle() {
            scheduledRestyle?.cancel()
            guard let textView, let storage = textView.textStorage else { return }
            // Restyling changes line heights; keep the text in view where it is.
            textView.keepReadingPosition()
            textView.apply(parent.theme)
            baseURL = parent.baseURL
            joinsHardWrappedLines = parent.joinsHardWrappedLines
            pendingEdit = nil
            let caret = textView.selectedRange().location
            activeLineStart = lineStart(at: caret)

            let padding = textView.textContainer?.lineFragmentPadding ?? 0
            let width = (textView.textContainer?.size.width ?? 760) - 2 * padding
            let settings = LiveStyler.Settings(theme: parent.theme, baseURL: baseURL, availableWidth: max(200, width),
                                               joinsHardWrappedLines: joinsHardWrappedLines)
            let styler = liveStyler ?? LiveStyler(storage: storage, settings: settings)
            liveStyler = styler
            textView.topLevelBlocks = { [weak styler] in styler?.blocks ?? [] }
            styler.restyleAll(caret: caret, settings: settings)
        }

        /// Restyles shortly, once, after a burst of changes such as a window resize.
        func restyleSoon() {
            scheduledRestyle?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.restyle() }
            scheduledRestyle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        private func lineStart(at location: Int) -> Int {
            guard let text = textView?.string as NSString? else { return NSNotFound }
            return text.lineRange(for: NSRange(location: min(location, text.length), length: 0)).location
        }
    }
}
