import AppKit

/// The open file's name and path, for grabbing again while the document is open: shown as the file name at the
/// left of the status bar, whose menu copies either or shows the file in Finder, and in the File menu as Copy Name
/// (⌃⇧⌘C), Copy Path (⌥⇧⌘C, Finder's key for copying a pathname), and Reveal in Finder.
enum FileLocation {
    /// The file's name with its extension (`notes.md`), or `Untitled` for a document not saved yet.
    static func name(of url: URL?) -> String {
        url?.lastPathComponent ?? "Untitled"
    }

    /// The full path, with spaces and other characters as they are in Finder; nil for a document not saved yet.
    static func path(of url: URL?) -> String? {
        url?.path(percentEncoded: false)
    }

    static func copyName(of url: URL, to pasteboard: NSPasteboard = .general) {
        copy(name(of: url), to: pasteboard)
    }

    static func copyPath(of url: URL, to pasteboard: NSPasteboard = .general) {
        guard let path = path(of: url) else { return }
        copy(path, to: pasteboard)
    }

    /// Shows the file selected in a Finder window.
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private static func copy(_ string: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
