import AppKit

/// Loads and caches images referenced by documents. Local files load right away;
/// web images load in the background and post `didLoad` so editors can restyle.
final class ImageStore {
    static let shared = ImageStore()
    static let didLoad = Notification.Name("CeraImageDidLoad")

    private var images: [URL: NSImage] = [:]
    private var failed: Set<URL> = []
    private var loading: Set<URL> = []

    /// The image at `url`, or nil if it is missing or still loading. Call on the main thread.
    func image(for url: URL) -> NSImage? {
        if let image = images[url] { return image }
        guard !failed.contains(url), !loading.contains(url) else { return nil }

        if url.isFileURL {
            if let image = NSImage(contentsOf: url) {
                images[url] = image
                return image
            }
            failed.insert(url)
            return nil
        }

        loading.insert(url)
        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                self.loading.remove(url)
                if let data, let image = NSImage(data: data) {
                    self.images[url] = image
                    NotificationCenter.default.post(name: Self.didLoad, object: nil)
                } else {
                    self.failed.insert(url)
                }
            }
        }.resume()
        return nil
    }

    /// Resolves an image source from Markdown: a web or file URL, an absolute or
    /// home-relative path, or a path relative to the document's folder.
    static func resolve(_ source: String, relativeTo base: URL?) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https", "file"].contains(scheme.lowercased()) {
            return url
        }
        let path = trimmed.removingPercentEncoding ?? trimmed
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path.hasPrefix("~") { return URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        guard let base else { return nil }
        return base.appendingPathComponent(path).standardizedFileURL
    }
}
