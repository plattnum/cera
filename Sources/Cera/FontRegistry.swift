import CoreText
import Foundation

/// Makes the fonts shipped with the app (open-licensed, see the LICENSE files
/// beside them) available to this process.
enum FontRegistry {
    private static var registered = false

    static func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        guard let directory = fontsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for file in files where ["woff2", "otf", "ttf"].contains(file.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    /// `Contents/Resources/Fonts` inside the app bundle, or the SwiftPM resource
    /// bundle when running from `swift run` or tests.
    private static func fontsDirectory() -> URL? {
        if let resources = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
           FileManager.default.fileExists(atPath: resources.path) {
            return resources
        }
        return Bundle.module.resourceURL?.appendingPathComponent("Fonts")
    }
}
