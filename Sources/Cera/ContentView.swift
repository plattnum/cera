import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    /// The file the document is saved in; nil until the first save.
    var fileURL: URL?
    @Environment(\.undoManager) private var undoManager
    @AppStorage("theme") private var themeChoice: ThemeChoice = .midnight
    @AppStorage("checksSpelling") private var checksSpelling = false
    @AppStorage("joinsHardWrappedLines") private var joinsHardWrappedLines = false

    var body: some View {
        let theme = themeChoice.theme
        MarkdownEditor(text: $document.text, theme: theme,
                       baseURL: fileURL?.deletingLastPathComponent(), checksSpelling: checksSpelling,
                       joinsHardWrappedLines: joinsHardWrappedLines, undoManager: undoManager)
            .frame(minWidth: 520, minHeight: 360)
            .ignoresSafeArea(.container, edges: .top)
            .background(Color(nsColor: theme.background))
            .toolbarBackground(Color(nsColor: theme.background), for: .windowToolbar)
            .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}
