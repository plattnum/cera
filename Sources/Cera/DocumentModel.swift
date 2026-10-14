import AppKit
import UniformTypeIdentifiers

/// One Markdown document: its text, the file it lives in, and saving.
final class DocumentModel: ObservableObject {
    @Published var text: String = ""
    @Published private(set) var fileURL: URL?

    /// The text as it was last read from or written to disk.
    private var savedText: String = ""

    var isDirty: Bool { text != savedText }

    var windowTitle: String {
        let name = fileURL?.lastPathComponent ?? "Untitled"
        return isDirty ? "\(name) — Edited" : name
    }

    func newDocument() {
        guard confirmDiscard() else { return }
        fileURL = nil
        savedText = ""
        text = ""
    }

    func openFile() {
        guard confirmDiscard() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.markdownTypes
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    /// Loads a file, replacing the current document. Used by Open and by Finder.
    func open(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            RecentDocuments.shared.remove(url)
            presentError("Couldn’t open \(url.lastPathComponent).", CocoaError(.fileReadNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The file “\(url.lastPathComponent)” can’t be found. It may have been moved or deleted."
            ]))
            return
        }
        guard confirmDiscard() else { return }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            savedText = contents
            text = contents
            RecentDocuments.shared.note(url)
        } catch {
            presentError("Couldn’t open \(url.lastPathComponent).", error)
        }
    }

    @discardableResult
    func save() -> Bool {
        guard let url = fileURL else { return saveAs() }
        return write(to: url, reportErrors: true)
    }

    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.markdownTypes.first ?? .plainText]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return write(to: url, reportErrors: true)
    }

    // MARK: - Private

    private static let markdownTypes: [UTType] = [
        UTType("net.daringfireball.markdown"),
        UTType(filenameExtension: "md"),
        .plainText
    ].compactMap { $0 }

    @discardableResult
    private func write(to url: URL, reportErrors: Bool) -> Bool {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            fileURL = url
            savedText = text
            RecentDocuments.shared.note(url)
            return true
        } catch {
            if reportErrors {
                presentError("Couldn’t save \(url.lastPathComponent).", error)
            }
            return false
        }
    }

    /// Asks before throwing away unsaved changes. Returns true if it is safe to continue.
    private func confirmDiscard() -> Bool {
        guard isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to \(fileURL?.lastPathComponent ?? "Untitled")?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    private func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.runModal()
    }
}
