import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterC
import TreeSitterCPP
import TreeSitterCSharp
import TreeSitterCSS
import TreeSitterDiff
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJava
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterKotlin
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterPython
import TreeSitterRuby
import TreeSitterRust
import TreeSitterSQL
import TreeSitterSwift
import TreeSitterTOML
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

/// A language Cera highlights with a tree-sitter grammar.
struct CodeLanguage {
    /// The usual fence name, which the language list inserts.
    let name: String
    /// Other names people write after the fence.
    let aliases: [String]
    /// The grammar.
    let grammar: () -> OpaquePointer?
    /// Highlight query files, as `folder/file` under Resources/Queries, in the order they
    /// combine: a grammar that builds on another comes after the one it builds on, and Cera's
    /// own corrections (`cera/`) come last.
    let queries: [String]
    /// Which of two patterns capturing the same text wins. Most grammars' queries start with
    /// general patterns and refine them further down, so the later one wins; a few (JSON, Go)
    /// put the specific ones first. Checked per language against its sample in
    /// TestDocuments/code-languages.md.
    var laterPatternsWin = true
    /// Capture names that mean something particular in this language, such as the keys of
    /// a data format.
    var roles: [String: SyntaxRole] = [:]
    /// One level of indentation when a block has none yet.
    var indent = "    "
    /// For Markdown: the grammar and queries for the text inside its blocks.
    var inline: (grammar: () -> OpaquePointer?, queries: [String])?
}

/// The languages Cera highlights, and the names they go by.
enum CodeLanguages {
    static let all: [CodeLanguage] = [
        CodeLanguage(name: "bash", aliases: ["sh", "shell", "zsh", "console", "shellscript", "shell-session"],
                     grammar: { tree_sitter_bash() }, queries: ["bash/highlights.scm"]),
        CodeLanguage(name: "c", aliases: ["h"], grammar: { tree_sitter_c() }, queries: ["c/highlights.scm"]),
        CodeLanguage(name: "cpp", aliases: ["c++", "cc", "cxx", "hpp", "hh", "hxx", "h++"],
                     grammar: { tree_sitter_cpp() }, queries: ["c/highlights.scm", "cpp/highlights.scm"]),
        CodeLanguage(name: "csharp", aliases: ["cs", "c#"], grammar: { tree_sitter_c_sharp() },
                     queries: ["c_sharp/highlights.scm"]),
        CodeLanguage(name: "css", aliases: [], grammar: { tree_sitter_css() }, queries: ["css/highlights.scm"],
                     indent: "  "),
        CodeLanguage(name: "diff", aliases: ["patch", "udiff"], grammar: { tree_sitter_diff() },
                     queries: ["diff/highlights.scm"]),
        CodeLanguage(name: "go", aliases: ["golang"], grammar: { tree_sitter_go() }, queries: ["go/highlights.scm"],
                     laterPatternsWin: false, indent: "\t"),
        CodeLanguage(name: "html", aliases: ["htm", "xhtml"], grammar: { tree_sitter_html() },
                     queries: ["html/highlights.scm"], indent: "  "),
        CodeLanguage(name: "java", aliases: [], grammar: { tree_sitter_java() }, queries: ["java/highlights.scm"]),
        CodeLanguage(name: "javascript", aliases: ["js", "jsx", "mjs", "cjs", "node"], grammar: { tree_sitter_javascript() },
                     queries: ["javascript/highlights.scm", "javascript/highlights-jsx.scm"], indent: "  "),
        CodeLanguage(name: "json", aliases: ["jsonc", "json5", "geojson", "webmanifest"], grammar: { tree_sitter_json() },
                     queries: ["json/highlights.scm"], laterPatternsWin: false, roles: ["string.special.key": .type], indent: "  "),
        CodeLanguage(name: "kotlin", aliases: ["kt", "kts"], grammar: { tree_sitter_kotlin() },
                     queries: ["kotlin/highlights.scm"]),
        CodeLanguage(name: "markdown", aliases: ["md", "mdown", "gfm"], grammar: { tree_sitter_markdown() },
                     queries: ["markdown/highlights.scm"], roles: ["punctuation.special": .atom], indent: "  ",
                     inline: ({ tree_sitter_markdown_inline() }, ["markdown_inline/highlights.scm"])),
        CodeLanguage(name: "python", aliases: ["py", "python3", "py3", "gyp"], grammar: { tree_sitter_python() },
                     queries: ["python/highlights.scm"]),
        CodeLanguage(name: "ruby", aliases: ["rb", "gemspec", "podspec", "rake"], grammar: { tree_sitter_ruby() },
                     queries: ["ruby/highlights.scm"], indent: "  "),
        CodeLanguage(name: "rust", aliases: ["rs"], grammar: { tree_sitter_rust() },
                     queries: ["rust/highlights.scm", "cera/rust.scm"]),
        CodeLanguage(name: "sql", aliases: ["postgres", "postgresql", "mysql", "sqlite", "plsql", "tsql"],
                     grammar: { tree_sitter_sql() }, queries: ["sql/highlights.scm", "cera/sql.scm"]),
        CodeLanguage(name: "swift", aliases: [], grammar: { tree_sitter_swift() }, queries: ["swift/highlights.scm"]),
        CodeLanguage(name: "toml", aliases: [], grammar: { tree_sitter_toml() }, queries: ["toml/highlights.scm"],
                     roles: ["property": .type, "type": .type]),
        CodeLanguage(name: "tsx", aliases: [], grammar: { tree_sitter_tsx() },
                     queries: ["javascript/highlights.scm", "javascript/highlights-jsx.scm", "typescript/highlights.scm"],
                     indent: "  "),
        CodeLanguage(name: "typescript", aliases: ["ts", "mts", "cts"], grammar: { tree_sitter_typescript() },
                     queries: ["javascript/highlights.scm", "typescript/highlights.scm"], indent: "  "),
        CodeLanguage(name: "yaml", aliases: ["yml"], grammar: { tree_sitter_yaml() }, queries: ["yaml/highlights.scm"],
                     roles: ["property": .type], indent: "  "),
    ]

    private static let byName: [String: Int] = {
        var names: [String: Int] = [:]
        for (index, language) in all.enumerated() {
            for name in [language.name] + language.aliases { names[name] = index }
        }
        return names
    }()

    /// The language a code block's info string names: its first word, in any case. Pandoc's
    /// `{.python}` form works too.
    static func language(info: String?) -> CodeLanguage? {
        guard let name = fenceName(info: info) else { return nil }
        return byName[name].map { all[$0] }
    }

    /// The first word of an info string, lowercased, without Pandoc's braces and dot.
    static func fenceName(info: String?) -> String? {
        guard var word = info?.split(whereSeparator: \.isWhitespace).first.map(String.init) else { return nil }
        if word.hasPrefix("{") {
            word = String(word.dropFirst().prefix { $0 != "}" && !$0.isWhitespace })
            if word.hasPrefix(".") { word.removeFirst() }
        }
        return word.isEmpty ? nil : word.lowercased()
    }
}
