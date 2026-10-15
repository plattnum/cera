import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Markdown, as declared by John Gruber's original spec; Info.plist imports it.
    static let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

/// One Markdown file. The system's document architecture handles opening, saving,
/// autosave, Open Recent, and the title bar's rename, move, and save popover.
///
/// It is a reference document: the editor's text view registers its own undo actions
/// on the document's undo manager, which is what marks the document as edited.
final class MarkdownDocument: ReferenceFileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .plainText]
    static let writableContentTypes: [UTType] = [.markdown, .plainText]

    @Published var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
