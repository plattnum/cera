// swift-tools-version:5.9
// Written by scripts/update-grammars.sh; edit the list there, not this file.
import PackageDescription

/// Each grammar, and whether it has an external scanner. Only these files are compiled:
/// a scanner may include other C files from its folder.
let grammars: [(name: String, hasScanner: Bool)] = [
    ("TreeSitterBash", true),
    ("TreeSitterC", false),
    ("TreeSitterCPP", true),
    ("TreeSitterCSharp", true),
    ("TreeSitterCSS", true),
    ("TreeSitterDiff", false),
    ("TreeSitterGo", false),
    ("TreeSitterHTML", true),
    ("TreeSitterJava", false),
    ("TreeSitterJavaScript", true),
    ("TreeSitterJSON", false),
    ("TreeSitterKotlin", true),
    ("TreeSitterMarkdown", true),
    ("TreeSitterMarkdownInline", true),
    ("TreeSitterPython", true),
    ("TreeSitterRuby", true),
    ("TreeSitterRust", true),
    ("TreeSitterSQL", true),
    ("TreeSitterSwift", true),
    ("TreeSitterTOML", true),
    ("TreeSitterTSX", true),
    ("TreeSitterTypeScript", true),
    ("TreeSitterYAML", true),
]

let package = Package(
    name: "Grammars",
    products: [.library(name: "Grammars", targets: grammars.map(\.name))],
    targets: grammars.map { grammar in
        .target(name: grammar.name, path: "Sources/\(grammar.name)",
                sources: grammar.hasScanner ? ["src/parser.c", "src/scanner.c"] : ["src/parser.c"],
                cSettings: [.headerSearchPath("src"), .unsafeFlags(["-w"])])
    },
    cLanguageStandard: .c11
)
