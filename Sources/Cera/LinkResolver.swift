import AppKit

extension NSAttributedString.Key {
    /// The resolved destination of a Markdown link (URL), on the link's visible text.
    static let linkTarget = NSAttributedString.Key("CeraLinkTarget")
}

enum LinkResolver {
    /// Resolves a Markdown link destination to something that can be opened:
    /// a URL with a scheme (https, mailto, …), a file path relative to the
    /// document's folder, or an in-page anchor (`#section`), which becomes a URL
    /// holding only that fragment.
    static func resolve(_ destination: String, relativeTo base: URL?) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != "#" else { return nil }
        if trimmed.hasPrefix("#") { return URL(string: trimmed) }

        if let url = URL(string: trimmed), let scheme = url.scheme, scheme.count > 1 {
            return url
        }
        if trimmed.lowercased().hasPrefix("www.") {
            return URL(string: "https://" + trimmed)
        }

        // A path: resolve it like an image source, then put back any #fragment, so a link
        // to a Markdown file can open at a heading.
        let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard let file = ImageStore.resolve(String(parts[0]), relativeTo: base) else { return nil }
        guard parts.count > 1, !parts[1].isEmpty,
              var components = URLComponents(url: file, resolvingAgainstBaseURL: true) else { return file }
        components.fragment = parts[1].removingPercentEncoding ?? String(parts[1])
        return components.url ?? file
    }

    /// What following a resolved link does.
    static func action(for url: URL) -> LinkAction {
        let anchor = url.fragment(percentEncoded: false) ?? ""
        if url.scheme == nil {
            return anchor.isEmpty ? .open(url) : .heading(anchor)
        }
        guard url.isFileURL else { return .open(url) }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        let file = components?.url ?? url
        if markdownExtensions.contains(file.pathExtension.lowercased()) {
            return .markdownFile(file, heading: anchor.isEmpty ? nil : anchor)
        }
        return .open(file)
    }

    private static let markdownExtensions: Set<String> = ["md", "markdown"]
}

/// What following a link does: jump to a heading in this document, open a Markdown file
/// in Cera (at a heading, when the link names one), or hand the link to the app that opens it.
enum LinkAction: Equatable {
    case heading(String)
    case markdownFile(URL, heading: String?)
    case open(URL)
}

extension MarkdownTextView {
    /// Follows a link: a `#heading` scrolls this document to it, a Markdown file opens in
    /// Cera (at its `#heading`, if the link has one), and anything else opens in its own app.
    func followLink(_ url: URL) {
        switch LinkResolver.action(for: url) {
        case .heading(let anchor):
            guard let location = HeadingAnchors.location(of: anchor, in: string) else {
                NSSound.beep()
                return
            }
            scrollLineToTop(at: location)
        case .markdownFile(let file, let anchor):
            Self.open(file, atHeading: anchor)
        case .open(let url):
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens a Markdown file in Cera, or brings its window forward, and scrolls to the heading if there is one.
    private static func open(_ file: URL, atHeading anchor: String?) {
        NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { document, _, error in
            Task { @MainActor in
                if let document {
                    if let anchor { jump(in: document, to: anchor, triesLeft: 20) }
                } else if let error {
                    NSApp.presentError(error)
                }
            }
        }
    }

    /// Scrolls a document's editor to a heading. A document just opened gets its editor
    /// once SwiftUI builds the window, so look again shortly when it isn't there yet.
    private static func jump(in document: NSDocument, to anchor: String, triesLeft: Int) {
        let editor = document.windowControllers.lazy.compactMap { $0.window?.contentView }
            .compactMap(editor(in:)).first
        guard let editor else {
            guard triesLeft > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                jump(in: document, to: anchor, triesLeft: triesLeft - 1)
            }
            return
        }
        guard let location = HeadingAnchors.location(of: anchor, in: editor.string) else { return }
        editor.scrollLineToTop(at: location)
    }

    private static func editor(in view: NSView) -> MarkdownTextView? {
        if let editor = view as? MarkdownTextView { return editor }
        for subview in view.subviews {
            if let editor = editor(in: subview) { return editor }
        }
        return nil
    }
}
