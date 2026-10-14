import AppKit

/// The files listed in File ▸ Open Recent, most recent first.
final class RecentDocuments: ObservableObject {
    static let shared = RecentDocuments()
    static let limit = 10

    @Published private(set) var urls: [URL]

    private let defaults: UserDefaults
    private static let key = "recentDocuments"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        urls = (defaults.stringArray(forKey: Self.key) ?? []).map { URL(fileURLWithPath: $0) }
    }

    /// Moves `url` to the top of the list. Also tells macOS, which shows it in the Dock menu.
    func note(_ url: URL) {
        let url = url.standardizedFileURL
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        urls = Array(urls.prefix(Self.limit))
        save()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url.standardizedFileURL }
        save()
    }

    func clear() {
        urls = []
        save()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    /// The menu title: the file name, plus its folder when another entry has the same name.
    func title(for url: URL) -> String {
        let name = url.lastPathComponent
        let sameName = urls.filter { $0.lastPathComponent == name }.count > 1
        return sameName ? "\(name) — \(url.deletingLastPathComponent().lastPathComponent)" : name
    }

    private func save() {
        defaults.set(urls.map(\.path), forKey: Self.key)
    }
}
