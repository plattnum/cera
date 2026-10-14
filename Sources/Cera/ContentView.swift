import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var document: DocumentModel
    @AppStorage("theme") private var themeChoice: ThemeChoice = .midnight
    @AppStorage("checksSpelling") private var checksSpelling = false
    @AppStorage("joinsHardWrappedLines") private var joinsHardWrappedLines = false

    init(document: DocumentModel = DocumentModel()) {
        _document = StateObject(wrappedValue: document)
    }

    var body: some View {
        let theme = themeChoice.theme
        MarkdownEditor(text: $document.text, theme: theme,
                       baseURL: document.fileURL?.deletingLastPathComponent(), checksSpelling: checksSpelling,
                       joinsHardWrappedLines: joinsHardWrappedLines)
            .frame(minWidth: 520, minHeight: 360)
            .ignoresSafeArea(.container, edges: .top)
            .background(Color(nsColor: theme.background))
            .navigationTitle(document.fileURL?.lastPathComponent ?? "Untitled")
            .modifier(DocumentIcon(url: document.fileURL))
            .toolbarBackground(Color(nsColor: theme.background), for: .windowToolbar)
            .preferredColorScheme(theme.isDark ? .dark : .light)
            .background(WindowEditedState(isEdited: document.isDirty))
            // Scene-wide, so the File menu reaches the document while the AppKit text view has focus.
            .focusedSceneObject(document)
            .onOpenURL { document.open(url: $0) }
    }
}

/// Shows the file's icon next to the window title, like a document window.
private struct DocumentIcon: ViewModifier {
    let url: URL?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let url {
            content.navigationDocument(url)
        } else {
            content
        }
    }
}

/// Marks the window as edited (the dot in the close button) while there are unsaved changes.
private struct WindowEditedState: NSViewRepresentable {
    let isEdited: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.isDocumentEdited = isEdited
        }
    }
}
