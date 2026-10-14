import Foundation

extension NSAttributedString.Key {
    /// The resolved destination of a Markdown link (URL), on the link's visible text.
    static let linkTarget = NSAttributedString.Key("CeraLinkTarget")
}

enum LinkResolver {
    /// Resolves a Markdown link destination to something that can be opened:
    /// a URL with a scheme (https, mailto, …), or a file path relative to the
    /// document's folder. In-page anchors (`#section`) return nil.
    static func resolve(_ destination: String, relativeTo base: URL?) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme, scheme.count > 1 {
            return url
        }
        if trimmed.lowercased().hasPrefix("www.") {
            return URL(string: "https://" + trimmed)
        }

        // A path: drop any #fragment, then resolve like an image source.
        let path = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
        return ImageStore.resolve(path, relativeTo: base)
    }
}
