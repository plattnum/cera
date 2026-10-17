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
    /// Follows changes other apps and agents make to the file.
    @StateObject private var diskSync = DiskSync()
    @StateObject private var outline = OutlineModel()
    /// Whether this window shows the outline; new windows start as the last one was left.
    @State private var showsOutline = UserDefaults.standard.bool(forKey: "showsOutline")

    var body: some View {
        let theme = themeChoice.theme
        HStack(spacing: 0) {
            if showsOutline {
                OutlineSidebar(model: outline, theme: theme)
            }
            MarkdownEditor(text: $document.text, theme: theme,
                           baseURL: fileURL?.deletingLastPathComponent(), checksSpelling: checksSpelling,
                           joinsHardWrappedLines: joinsHardWrappedLines, undoManager: undoManager, outline: outline)
                .frame(minWidth: showsOutline ? 360 : 520, minHeight: 360)
                .ignoresSafeArea(.container, edges: .top)
                .overlay(alignment: .top) {
                    if diskSync.changedUnderEdits {
                        DiskChangeBanner(theme: theme, keepMine: diskSync.keepMine, loadFromDisk: diskSync.loadFromDisk)
                    }
                }
        }
        .background(Color(nsColor: theme.background))
        .toolbarBackground(Color(nsColor: theme.background), for: .windowToolbar)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onChange(of: fileURL, initial: true) { diskSync.watch(fileURL, for: document) }
        // Revert hands the window a new document object for the same file.
        .onChange(of: ObjectIdentifier(document)) { diskSync.watch(fileURL, for: document) }
        .onDisappear { diskSync.stop() }
        .onChange(of: document.text) {
            if showsOutline { outline.update(text: document.text) }
        }
        .onChange(of: showsOutline, initial: true) {
            UserDefaults.standard.set(showsOutline, forKey: "showsOutline")
            if showsOutline { outline.update(text: document.text, immediately: true) }
        }
        .focusedSceneValue(\.showsOutline, $showsOutline)
    }
}

extension FocusedValues {
    /// Whether the focused window shows the outline, for the View menu.
    var showsOutline: Binding<Bool>? {
        get { self[ShowsOutlineKey.self] }
        set { self[ShowsOutlineKey.self] = newValue }
    }

    private struct ShowsOutlineKey: FocusedValueKey {
        typealias Value = Binding<Bool>
    }
}
