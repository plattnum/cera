import SwiftUI

@main
struct CeraApp: App {
    init() {
        // Start with an empty document, like Notepad, instead of an Open panel.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    var body: some Scene {
        // The system's document architecture provides the File menu (New, Open, Open Recent,
        // Save, Duplicate, Rename, Move To, Revert), autosave, and the title bar popover for
        // naming the file and choosing where it lives.
        DocumentGroup(newDocument: { MarkdownDocument() }) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 900, height: 700)
        // Don't reopen last session's windows; each launch starts clean.
        .restorationBehavior(.disabled)
        .commands {
            CeraCommands()
        }
    }
}

/// Menu bar items. Formatting actions are sent down the responder chain to the
/// editor that has focus.
struct CeraCommands: Commands {
    @AppStorage("theme") private var themeChoice: ThemeChoice = .midnight
    @AppStorage("checksSpelling") private var checksSpelling = false
    @AppStorage("joinsHardWrappedLines") private var joinsHardWrappedLines = false
    @FocusedBinding(\.showsOutline) private var showsOutline

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") { Self.newTab() }
                .keyboardShortcut("t")
        }

        CommandGroup(after: .textEditing) {
            Toggle("Check Spelling While Typing", isOn: $checksSpelling)
        }

        CommandGroup(replacing: .sidebar) {
            Button(showsOutline == true ? "Hide Outline" : "Show Outline") { showsOutline?.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(showsOutline == nil)
        }

        CommandGroup(after: .toolbar) {
            Toggle("Flow Hard-Wrapped Paragraphs", isOn: $joinsHardWrappedLines)
        }

        CommandMenu("Themes") {
            Picker("Theme", selection: $themeChoice) {
                ForEach(ThemeChoice.allCases) { choice in
                    Text(choice.theme.name).tag(choice)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        CommandMenu("Format") {
            Button("Bold") { send(#selector(MarkdownTextView.toggleBold(_:))) }
                .keyboardShortcut("b")
            Button("Italic") { send(#selector(MarkdownTextView.toggleItalic(_:))) }
                .keyboardShortcut("i")
            Button("Strikethrough") { send(#selector(MarkdownTextView.toggleStrikethrough(_:))) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { send(#selector(MarkdownTextView.toggleInlineCode(_:))) }
                .keyboardShortcut("e")
            Button("Link") { send(#selector(MarkdownTextView.insertLink(_:))) }
                .keyboardShortcut("k")
            Button("Clear Formatting") { send(#selector(MarkdownTextView.clearFormatting(_:))) }
                .keyboardShortcut("\\")

            Divider()

            Menu("Heading") {
                Button("Paragraph") { send(#selector(MarkdownTextView.paragraph(_:))) }
                    .keyboardShortcut("0")
                Button("Heading 1") { send(#selector(MarkdownTextView.heading1(_:))) }
                    .keyboardShortcut("1")
                Button("Heading 2") { send(#selector(MarkdownTextView.heading2(_:))) }
                    .keyboardShortcut("2")
                Button("Heading 3") { send(#selector(MarkdownTextView.heading3(_:))) }
                    .keyboardShortcut("3")
                Button("Heading 4") { send(#selector(MarkdownTextView.heading4(_:))) }
                    .keyboardShortcut("4")
                Button("Heading 5") { send(#selector(MarkdownTextView.heading5(_:))) }
                    .keyboardShortcut("5")
                Button("Heading 6") { send(#selector(MarkdownTextView.heading6(_:))) }
                    .keyboardShortcut("6")
                Divider()
                Button("Make Heading Larger") { send(#selector(MarkdownTextView.makeHeadingLarger(_:))) }
                    .keyboardShortcut("=")
                Button("Make Heading Smaller") { send(#selector(MarkdownTextView.makeHeadingSmaller(_:))) }
                    .keyboardShortcut("-")
            }

            Menu("List") {
                Button("Bulleted") { send(#selector(MarkdownTextView.toggleBulletedList(_:))) }
                    .keyboardShortcut("u", modifiers: [.command, .option])
                Button("Numbered") { send(#selector(MarkdownTextView.toggleNumberedList(_:))) }
                    .keyboardShortcut("o", modifiers: [.command, .option])
                Button("Task") { send(#selector(MarkdownTextView.toggleTaskList(_:))) }
                    .keyboardShortcut("x", modifiers: [.command, .option])
                Divider()
                Button("Indent") { send(#selector(MarkdownTextView.indentList(_:))) }
                    .keyboardShortcut("]")
                Button("Outdent") { send(#selector(MarkdownTextView.outdentList(_:))) }
                    .keyboardShortcut("[")
            }

            Button("Quote") { send(#selector(MarkdownTextView.toggleQuote(_:))) }
                .keyboardShortcut("q", modifiers: [.command, .option])

            Divider()

            Menu("Insert") {
                Button("Image…") { send(#selector(MarkdownTextView.insertImage(_:))) }
                    .keyboardShortcut("i", modifiers: [.command, .control])
                Button("Table") { send(#selector(MarkdownTextView.insertTable(_:))) }
                    .keyboardShortcut("t", modifiers: [.command, .option])
                Button("Code Block") { send(#selector(MarkdownTextView.insertCodeBlock(_:))) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("Horizontal Rule") { send(#selector(MarkdownTextView.insertHorizontalRule(_:))) }
                    .keyboardShortcut("-", modifiers: [.command, .option])
            }
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    /// Opens a new document as a tab of the front document window, or in a window of its
    /// own when no document window is open.
    @MainActor
    static func newTab() {
        let documents = NSDocumentController.shared
        // The main window, not the key one: a panel such as About can be key but never main.
        guard let window = NSApp.mainWindow, documents.document(for: window) != nil,
              window.tabbingMode != .disallowed else {
            documents.newDocument(nil)
            return
        }
        let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
        documents.newDocument(nil)
        guard let tab = NSApp.windows.first(where: { !existing.contains(ObjectIdentifier($0)) && documents.document(for: $0) != nil })
        else { return }
        window.addTabbedWindow(tab, ordered: .above)
        tab.makeKeyAndOrderFront(nil)
    }
}
