import AppKit
import SwiftUI

/// The status bar along the bottom of a window: the file's name at the left (click it for Copy Name, Copy Path,
/// and Reveal in Finder), and at the right where the insertion point is (`Ln 12, Col 5`) and how many words the
/// document has, or the selection (`9 of 1,234 words`).
struct StatusBar: View {
    @ObservedObject var model: StatusModel
    /// The file the document is saved in; nil until the first save.
    var fileURL: URL?
    let theme: Theme

    var body: some View {
        HStack(spacing: 24) {
            FileNameMenu(fileURL: fileURL)
            Spacer(minLength: 0)
            Text(model.positionText)
            Text(model.wordsText)
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color(nsColor: theme.marker))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 22)
        .background(Color(nsColor: theme.background))
    }
}

/// The file name in the status bar, and the menu it opens: the ways to grab the name or path again without leaving
/// the document. An unsaved document reads `Untitled`, with the copy items disabled.
private struct FileNameMenu: View {
    var fileURL: URL?

    var body: some View {
        Menu {
            Button("Copy Name") { if let fileURL { FileLocation.copyName(of: fileURL) } }
            Button("Copy Path") { if let fileURL { FileLocation.copyPath(of: fileURL) } }
            Divider()
            Button("Reveal in Finder") { if let fileURL { FileLocation.revealInFinder(fileURL) } }
        } label: {
            Text(FileLocation.name(of: fileURL))
                .truncationMode(.middle)
        }
        .disabled(fileURL == nil)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help(FileLocation.path(of: fileURL) ?? "Not saved yet")
        .accessibilityLabel("File name")
    }
}

/// What the status bar shows, kept current from the editor. Line, column, and the selected characters update
/// right after the selection changes; words are counted on a background queue, a moment after typing stops,
/// so typing never waits for them. Nothing is counted while the bar is hidden.
@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var line = 1
    @Published private(set) var column = 1
    @Published private(set) var selectedCharacters = 0
    @Published private(set) var words = 0
    @Published private(set) var selectedWords = 0

    /// The editor whose text and selection are shown. Set by the editor.
    weak var textView: NSTextView? {
        didSet { if textView !== oldValue { refresh() } }
    }

    /// Whether the bar is on screen; while it isn't, nothing is counted.
    var isShown = false {
        didSet { if isShown, !oldValue { refresh() } }
    }

    private var positionScheduled = false
    private var documentCount: DispatchWorkItem?
    private var selectionCount: DispatchWorkItem?
    private var documentGeneration = 0
    private var selectionGeneration = 0
    private static let queue = DispatchQueue(label: "cera.status.words", qos: .utility)

    var positionText: String {
        "Ln \(line.formatted()), Col \(column.formatted())" + (selectedCharacters > 0 ? " (\(selectedCharacters.formatted()) selected)" : "")
    }

    var wordsText: String {
        if selectedCharacters > 0 { return "\(selectedWords.formatted()) of \(words.formatted()) \(words == 1 ? "word" : "words")" }
        return "\(words.formatted()) \(words == 1 ? "word" : "words")"
    }

    /// Everything again: when the bar appears or the editor changes.
    func refresh() {
        guard isShown, textView != nil else { return }
        textChanged(delay: 0)
        selectionChanged()
    }

    func selectionChanged() {
        guard isShown, !positionScheduled else { return }
        // Once per turn of the run loop, however many selection changes an edit makes.
        positionScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.updateSelection() }
        }
    }

    /// Counts the document's words again, `delay` seconds after the last change.
    func textChanged(delay: TimeInterval = 0.3) {
        guard isShown, let textView else { return }
        documentCount?.cancel()
        documentGeneration += 1
        let generation = documentGeneration
        let work = DispatchWorkItem { [weak self, weak textView] in
            guard let text = textView?.string else { return }
            Self.queue.async {
                let count = StatusCounts.words(in: text)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.documentGeneration == generation else { return }
                        self.words = count
                    }
                }
            }
        }
        documentCount = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func updateSelection() {
        positionScheduled = false
        guard isShown, let textView else { return }
        let text = textView.string as NSString
        let ranges = textView.selectedRanges.map(\.rangeValue).map { NSIntersectionRange($0, NSRange(location: 0, length: text.length)) }
        let start = ranges.first?.location ?? 0
        let position = StatusCounts.position(in: text, at: start)
        line = position.line
        column = position.column
        let selected = ranges.filter { $0.length > 0 }
        selectedCharacters = selected.reduce(0) { $0 + text.substring(with: $1).count }

        // The selection's words, in the background like the document's: a selection can be the whole document.
        selectionCount?.cancel()
        selectionGeneration += 1
        let generation = selectionGeneration
        guard !selected.isEmpty else {
            selectedWords = 0
            return
        }
        // Front matter isn't counted, in a selection either.
        let frontMatterEnd = FrontMatter.range(in: text).map(NSMaxRange) ?? 0
        let pieces = selected.compactMap { range -> String? in
            let start = max(range.location, frontMatterEnd)
            return start < NSMaxRange(range) ? text.substring(with: NSRange(location: start, length: NSMaxRange(range) - start)) : nil
        }
        let work = DispatchWorkItem { [weak self] in
            Self.queue.async {
                let count = pieces.reduce(0) { $0 + StatusCounts.words(in: $1, skippingFrontMatter: false) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, self.selectionGeneration == generation else { return }
                        self.selectedWords = count
                    }
                }
            }
        }
        selectionCount = work
        DispatchQueue.main.async(execute: work)
    }
}

/// Counting for the status bar.
enum StatusCounts {
    /// The words a reader sees: runs of letters and digits, kept whole across an apostrophe, hyphen, or underscore
    /// inside a word (`don't`, `well-known`, `snake_case`). Front matter, link and image destinations, link
    /// reference definitions, and HTML tags aren't counted; Markdown symbols aren't letters, so they never are.
    static func words(in text: String, skippingFrontMatter: Bool = true) -> Int {
        var body = text
        if skippingFrontMatter, let frontMatter = FrontMatter.range(in: text as NSString) {
            body = (text as NSString).substring(from: NSMaxRange(frontMatter))
        }
        body = hidden.stringByReplacingMatches(in: body, range: NSRange(location: 0, length: (body as NSString).length),
                                               withTemplate: " ")
        var count = 0
        var inWord = false
        var afterJoiner = false
        for scalar in body.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if !inWord { count += 1 }
                inWord = true
                afterJoiner = false
            } else if inWord, !afterJoiner, joiners.contains(scalar) {
                afterJoiner = true
            } else {
                inWord = false
                afterJoiner = false
            }
        }
        return count
    }

    private static let joiners: Set<Unicode.Scalar> = ["'", "\u{2019}", "-", "_"]

    /// Link and image destinations (one level of parentheses inside, as in Wikipedia's), the labels of full
    /// reference links (`[text][label]`), link reference definitions, and HTML tags.
    private static let hidden = try! NSRegularExpression(
        pattern: "\\]\\((?:[^()\\n]|\\([^()\\n]*\\))*\\)|\\]\\[[^\\]\\n]*\\]|^ {0,3}\\[[^\\]\\n]+\\]:.*$|<[A-Za-z/!][^>\\n]*>",
        options: [.anchorsMatchLines])

    /// The line and column of `location`, both from 1: lines of the file (a line break is `\n`, `\r\n`, or `\r`),
    /// and characters from the line's start.
    static func position(in text: NSString, at location: Int) -> (line: Int, column: Int) {
        let location = min(max(0, location), text.length)
        var line = 1
        var lineStart = 0
        let chunk = 65_536
        var buffer = [unichar](repeating: 0, count: chunk)
        var index = 0
        var previousWasReturn = false
        while index < location {
            let count = min(chunk, location - index)
            text.getCharacters(&buffer, range: NSRange(location: index, length: count))
            for offset in 0..<count {
                switch buffer[offset] {
                case 10:
                    if !previousWasReturn { line += 1 }
                    lineStart = index + offset + 1
                    previousWasReturn = false
                case 13:
                    line += 1
                    lineStart = index + offset + 1
                    previousWasReturn = true
                default:
                    previousWasReturn = false
                }
            }
            index += count
        }
        let column = text.substring(with: NSRange(location: lineStart, length: location - lineStart)).count + 1
        return (line, column)
    }
}
