import AppKit
import UniformTypeIdentifiers

/// Decides how an image is referenced from a document, copying it next to the
/// document when needed so the Markdown stays portable.
///
/// - An image already inside the document's folder is linked by relative path.
/// - Any other image is copied into `assets/` beside the document and linked there.
/// - An untitled document has no folder yet, so files are linked by absolute path.
struct ImageImporter {
    /// The folder of the saved document, or nil for an untitled one.
    let documentFolder: URL?

    static let assetsFolderName = "assets"

    enum ImportError: LocalizedError {
        case unsavedDocument

        var errorDescription: String? {
            "Save the document first, so the image can be stored in an “assets” folder next to it."
        }
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// The Markdown path to use for an image file, copying the file into `assets/` if it lives elsewhere.
    func reference(for file: URL) throws -> String {
        guard let folder = documentFolder?.standardizedFileURL.resolvingSymlinksInPath() else {
            return Self.encode(file.standardizedFileURL.path)
        }
        let source = file.standardizedFileURL.resolvingSymlinksInPath()
        if let relative = Self.relativePath(of: source, inside: folder) {
            return Self.encode(relative)
        }
        let destination = try uniqueAssetURL(named: source.lastPathComponent, in: folder)
        try FileManager.default.copyItem(at: source, to: destination)
        return Self.encode("\(Self.assetsFolderName)/\(destination.lastPathComponent)")
    }

    /// Saves pasted image data as a PNG in `assets/` and returns its Markdown path.
    func reference(forPasted image: NSImage, date: Date = Date()) throws -> String {
        guard let folder = documentFolder?.standardizedFileURL else { throw ImportError.unsavedDocument }
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }

        let stamp = Self.timestampFormatter.string(from: date)
        let destination = try uniqueAssetURL(named: "pasted-image-\(stamp).png", in: folder)
        try png.write(to: destination)
        return Self.encode("\(Self.assetsFolderName)/\(destination.lastPathComponent)")
    }

    /// `![alt](path)`, with the file name (without extension) as the alt text.
    static func markdown(for path: String) -> String {
        let name = ((path.removingPercentEncoding ?? path) as NSString).lastPathComponent
        let alt = (name as NSString).deletingPathExtension
        return "![\(alt)](\(path))"
    }

    // MARK: - Private

    private func uniqueAssetURL(named name: String, in folder: URL) throws -> URL {
        let assets = folder.appendingPathComponent(Self.assetsFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = assets.appendingPathComponent(name)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            candidate = assets.appendingPathComponent(numbered)
            counter += 1
        }
        return candidate
    }

    private static func relativePath(of file: URL, inside folder: URL) -> String? {
        let folderPath = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        guard file.path.hasPrefix(folderPath) else { return nil }
        return String(file.path.dropFirst(folderPath.count))
    }

    /// Markdown link destinations can't contain spaces, so encode them (and other unsafe characters).
    private static func encode(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
