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
    @AppStorage(TextZoom.key) private var zoom = 1.0
    /// Follows changes other apps and agents make to the file.
    @StateObject private var diskSync = DiskSync()
    @StateObject private var outline = OutlineModel()
    @StateObject private var status = StatusModel()
    /// Whether this window shows the outline; new windows start as the last one was left.
    @State private var showsOutline = UserDefaults.standard.bool(forKey: "showsOutline")
    /// Whether this window shows the Markdown source instead of rendering it; new windows
    /// start as the last one was left.
    @State private var showsSource = UserDefaults.standard.bool(forKey: "showsSource")
    /// Whether this window shows the status bar; shown at first, then new windows start as the last one was left.
    @State private var showsStatusBar = UserDefaults.standard.object(forKey: "showsStatusBar") as? Bool ?? true

    var body: some View {
        let theme = themeChoice.theme
        HStack(spacing: 0) {
            if showsOutline {
                OutlineSidebar(model: outline, theme: theme)
            }
            VStack(spacing: 0) {
                MarkdownEditor(text: $document.text, theme: theme,
                               baseURL: fileURL?.deletingLastPathComponent(), checksSpelling: checksSpelling,
                               joinsHardWrappedLines: joinsHardWrappedLines, showsSource: showsSource,
                               undoManager: undoManager, outline: outline, status: status, zoom: zoom)
                    .frame(minWidth: showsOutline ? 360 : 520, minHeight: 360)
                    .ignoresSafeArea(.container, edges: .top)
                    .overlay(alignment: .top) {
                        if diskSync.changedUnderEdits {
                            DiskChangeBanner(theme: theme, keepMine: diskSync.keepMine, loadFromDisk: diskSync.loadFromDisk)
                        }
                    }
                if showsStatusBar {
                    StatusBar(model: status, theme: theme)
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
            status.textChanged()
        }
        .onChange(of: showsOutline, initial: true) {
            UserDefaults.standard.set(showsOutline, forKey: "showsOutline")
            if showsOutline { outline.update(text: document.text, immediately: true) }
        }
        .onChange(of: showsSource) {
            UserDefaults.standard.set(showsSource, forKey: "showsSource")
        }
        .onChange(of: showsStatusBar, initial: true) {
            UserDefaults.standard.set(showsStatusBar, forKey: "showsStatusBar")
            status.isShown = showsStatusBar
        }
        .focusedSceneValue(\.showsOutline, $showsOutline)
        .focusedSceneValue(\.showsSource, $showsSource)
        .focusedSceneValue(\.showsStatusBar, $showsStatusBar)
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

    /// Whether the focused window shows the Markdown source, for the View menu.
    var showsSource: Binding<Bool>? {
        get { self[ShowsSourceKey.self] }
        set { self[ShowsSourceKey.self] = newValue }
    }

    private struct ShowsSourceKey: FocusedValueKey {
        typealias Value = Binding<Bool>
    }

    /// Whether the focused window shows the status bar, for the View menu.
    var showsStatusBar: Binding<Bool>? {
        get { self[ShowsStatusBarKey.self] }
        set { self[ShowsStatusBarKey.self] = newValue }
    }

    private struct ShowsStatusBarKey: FocusedValueKey {
        typealias Value = Binding<Bool>
    }
}
