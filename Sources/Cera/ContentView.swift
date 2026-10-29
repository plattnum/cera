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
    /// Whether this window's editing is locked (see LockEditing.swift). New windows start editable, unless the
    /// file can't be written or `cera -r` opened it.
    @State private var isLocked = false
    /// Counts typing refused while locked; each one shows the locked notice for a moment.
    @State private var refusedEdits = 0
    @State private var showsLockedNotice = false

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
                               isLocked: isLocked, onRefusedEdit: { refusedEdits += 1 },
                               undoManager: undoManager, outline: outline, status: status, zoom: zoom)
                    .frame(minWidth: showsOutline ? 360 : 520, minHeight: 360)
                    .ignoresSafeArea(.container, edges: .top)
                    .overlay(alignment: .top) {
                        if diskSync.changedUnderEdits {
                            DiskChangeBanner(theme: theme, keepMine: diskSync.keepMine, loadFromDisk: diskSync.loadFromDisk)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if showsLockedNotice {
                            LockedNotice(theme: theme)
                        }
                    }
                if showsStatusBar {
                    StatusBar(model: status, fileURL: fileURL, theme: theme)
                }
            }
        }
        .background(Color(nsColor: theme.background))
        .toolbarBackground(Color(nsColor: theme.background), for: .windowToolbar)
        .background(LockTitlebarButton(isLocked: $isLocked, theme: theme))
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onChange(of: fileURL, initial: true) {
            diskSync.watch(fileURL, for: document)
            if LockRequests.take(fileURL) || fileURL.map({ !FileManager.default.isWritableFile(atPath: $0.path) }) == true {
                isLocked = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: LockRequests.didRequest)) { _ in
            if LockRequests.take(fileURL) { isLocked = true }
        }
        .onChange(of: isLocked) {
            if !isLocked { showsLockedNotice = false }
        }
        .task(id: refusedEdits) {
            guard refusedEdits > 0 else { return }
            showsLockedNotice = true
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { showsLockedNotice = false }
        }
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
        .focusedSceneValue(\.isLocked, $isLocked)
        .focusedSceneValue(\.fileURL, fileURL)
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

    /// Whether the focused window's editing is locked, for the View and Format menus.
    var isLocked: Binding<Bool>? {
        get { self[IsLockedKey.self] }
        set { self[IsLockedKey.self] = newValue }
    }

    private struct IsLockedKey: FocusedValueKey {
        typealias Value = Binding<Bool>
    }

    /// The file the focused window's document is saved in, for the File menu's Copy Name, Copy Path, and Reveal
    /// in Finder; nil for a document not saved yet.
    var fileURL: URL? {
        get { self[FileURLKey.self] }
        set { self[FileURLKey.self] = newValue }
    }

    private struct FileURLKey: FocusedValueKey {
        typealias Value = URL
    }
}
