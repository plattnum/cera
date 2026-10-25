import AppKit
import SwiftUI

/// Lock Editing: a window as a pure viewer. The text can be read, selected, copied, and searched, and its task
/// boxes ticked, but not changed; every line stays rendered, and a plain click opens a link. Per window, toggled
/// from View ▸ Lock Editing (⌥⌘L) or the lock in the title bar. Unwritable files and `cera -r` open locked.
extension MarkdownTextView {
    /// Key commands that change the text, from the system's key bindings (Return, Delete, ⌃K, ⌃T, …).
    private static let editingCommandPrefixes = ["insert", "delete", "transpose", "yank"]
    private static let editingCommands: Set<Selector> = [
        #selector(NSTextView.capitalizeWord(_:)), #selector(NSTextView.lowercaseWord(_:)),
        #selector(NSTextView.uppercaseWord(_:)), #selector(NSTextView.changeCaseOfLetter(_:)),
        #selector(NSTextView.indent(_:)),
    ]

    /// Whether a key command changes the text.
    static func editsText(_ command: Selector) -> Bool {
        let name = NSStringFromSelector(command)
        return editingCommands.contains(command) || editingCommandPrefixes.contains { name.hasPrefix($0) }
    }

    /// While editing is locked, a key command that would change the text is refused instead.
    override func doCommand(by selector: Selector) {
        if isLocked, Self.editsText(selector) {
            refuseEdit()
            return
        }
        super.doCommand(by: selector)
    }

    private static let undoCommands: Set<Selector> = [#selector(undo(_:)), #selector(redo(_:))]

    /// While editing is locked, Undo and Redo stop here, disabled: the text view wouldn't apply the change, and
    /// the step would be lost. Unlocked, they go on to the window as usual.
    override func responds(to selector: Selector!) -> Bool {
        if let selector, Self.undoCommands.contains(selector) { return isLocked }
        return super.responds(to: selector)
    }

    @objc func undo(_ sender: Any?) { refuseEdit() }
    @objc func redo(_ sender: Any?) { refuseEdit() }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, Self.undoCommands.contains(action) { return false }
        return super.validateUserInterfaceItem(item)
    }

    /// Says that the text is locked, or beeps when nothing shows it.
    func refuseEdit() {
        if let onRefusedEdit { onRefusedEdit() } else { NSSound.beep() }
    }
}

/// Files to lock when their window opens, asked for by `cera -r`, which sends a `cera://open-locked?path=…` URL.
@MainActor
enum LockRequests {
    /// Posted when a file is asked to open locked, so a window already showing it can lock.
    static let didRequest = Notification.Name("CeraLockRequested")
    private static var pending: Set<URL> = []

    /// The file a `cera://open-locked?path=/absolute/path` URL names, or nil for any other URL.
    nonisolated static func file(in url: URL) -> URL? {
        guard url.scheme == "cera", url.host == "open-locked",
              let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Opens `file` locked: in a new window, or by locking the window already showing it and bringing it forward.
    static func open(_ file: URL) {
        request(file)
        NSDocumentController.shared.openDocument(withContentsOf: file, display: true) { _, _, error in
            Task { @MainActor in
                guard let error else { return }
                pending.remove(key(file))
                NSApp.presentError(error)
            }
        }
    }

    /// Asks for `file` to be locked when a window shows it.
    static func request(_ file: URL) {
        pending.insert(key(file))
        NotificationCenter.default.post(name: didRequest, object: nil)
    }

    /// Whether `file` was asked to open locked. Answers yes once per request.
    static func take(_ file: URL?) -> Bool {
        guard let file else { return false }
        return pending.remove(key(file)) != nil
    }

    /// The same file however its path is written: through symlinks (`/tmp` is `/private/tmp`) and `..`.
    private static func key(_ file: URL) -> URL {
        file.resolvingSymlinksInPath().standardizedFileURL
    }
}

/// Receives the `cera://` URLs that `cera -r` sends. URLs go through Apple events so that files, which the
/// document system opens, never pass through here.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string), let file = LockRequests.file(in: url) else { return }
        MainActor.assumeIsolated { LockRequests.open(file) }
    }
}

/// The lock at the right of the title bar: open and muted while the window is editable, closed while it is locked.
/// A title bar accessory, not a SwiftUI toolbar: a toolbar makes the title bar taller, which moves the window
/// buttons and covers the top of the text.
struct LockTitlebarButton: NSViewRepresentable {
    @Binding var isLocked: Bool
    var theme: Theme

    func makeNSView(context: Context) -> Anchor {
        Anchor()
    }

    func updateNSView(_ anchor: Anchor, context: Context) {
        anchor.toggle = { isLocked.toggle() }
        anchor.update(isLocked: isLocked, theme: theme)
    }

    /// An empty view in the window's content that adds the button to the title bar once it is in a window.
    final class Anchor: NSView {
        var toggle: () -> Void = {}
        private let button = NSButton()
        private let accessory = NSTitlebarAccessoryViewController()

        override init(frame: NSRect) {
            super.init(frame: frame)
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(clicked(_:))
            // The title bar sets the height; the width leaves room around the symbol for clicking.
            button.frame = NSRect(x: 0, y: 0, width: 36, height: 28)
            accessory.view = button
            accessory.layoutAttribute = .trailing
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        func update(isLocked: Bool, theme: Theme) {
            let title = isLocked ? "Unlock Editing" : "Lock Editing"
            button.image = NSImage(systemSymbolName: isLocked ? "lock.fill" : "lock.open", accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            button.contentTintColor = isLocked ? theme.text : theme.marker
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !window.titlebarAccessoryViewControllers.contains(accessory) else { return }
            window.addTitlebarAccessoryViewController(accessory)
        }

        @objc private func clicked(_ sender: NSButton) {
            toggle()
        }
    }
}

/// Shown for a moment at the bottom of a locked editor when typing is refused.
struct LockedNotice: View {
    var theme: Theme

    var body: some View {
        Label("Locked — ⌥⌘L to edit", systemImage: "lock.fill")
            .font(.system(size: 12))
            .foregroundStyle(Color(nsColor: theme.text))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color(nsColor: theme.rule)))
            .padding(.bottom, 16)
            .allowsHitTesting(false)
    }
}
