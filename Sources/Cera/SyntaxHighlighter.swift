import AppKit
import SwiftTreeSitter

/// What a piece of code is, for coloring: each role has a color in every theme.
enum SyntaxRole: UInt8, CaseIterable {
    case comment, string, keyword, number, atom, builtin, type, function, tag, inserted, deleted
    /// Body text: a role that clears an enclosing one, such as the expression inside a string.
    case plain
}

/// A colored stretch of code, in UTF-16 units from the start of the code.
struct SyntaxRun: Equatable {
    var location: Int
    var length: Int
    var role: SyntaxRole
}

/// Highlights code with tree-sitter: each language's real grammar, and its highlight
/// queries, mapped onto the theme's syntax colors.
///
/// Parsers and queries are made once per language, on first use. Results are cached by
/// language and code, so moving the cursor or editing next to a block costs a lookup.
/// Call on the main thread, where all styling runs.
final class SyntaxHighlighter {
    static let shared = SyntaxHighlighter()

    /// Longer code gets the simple fallback colors instead, so a huge block can't slow typing.
    static let maxCodeLength = 60_000
    /// A safety stop for pathological input. Code that hits it gets the fallback colors and
    /// isn't parsed again until it changes, so a slow block can't slow every keystroke.
    static var parseTimeout: TimeInterval = 0.05

    private final class Engine {
        let parser: Parser
        let query: Query
        /// Each capture's role, by capture index; nil for captures that don't color.
        let roles: [SyntaxRole?]
        let laterPatternsWin: Bool
        let inline: Engine?

        init(parser: Parser, query: Query, roles: [SyntaxRole?], laterPatternsWin: Bool, inline: Engine?) {
            self.parser = parser
            self.query = query
            self.roles = roles
            self.laterPatternsWin = laterPatternsWin
            self.inline = inline
        }
    }

    private var engines: [String: Engine] = [:]
    private var failedLanguages: Set<String> = []

    /// Runs by language and code; nil runs for code whose parse timed out.
    private var cache: [String: (runs: [SyntaxRun]?, length: Int)] = [:]
    private var cacheOrder: [String] = []
    private var cachedLength = 0
    private let cacheLimit = 4_000_000

    /// The colored runs of `code`, or nil when it is too long, the parser gave up, or the
    /// language's grammar couldn't be loaded.
    func runs(for code: String, language: CodeLanguage) -> [SyntaxRun]? {
        let length = (code as NSString).length
        guard length <= Self.maxCodeLength else { return nil }
        let key = language.name + "\u{0}" + code
        if let entry = cache[key] { return entry.runs }
        guard let engine = engine(for: language) else { return nil }
        let runs = highlight(code, length: length, with: engine) // nil when the parse timed out.
        remember(runs, for: key, length: length)
        return runs
    }

    // MARK: - Highlighting

    private func highlight(_ code: String, length: Int, with engine: Engine) -> [SyntaxRun]? {
        guard length > 0 else { return [] }
        engine.parser.timeout = Self.parseTimeout
        guard let tree = engine.parser.parse(code) else {
            // A parser that times out keeps its half-done parse to resume on its next call, whatever
            // text that call has; start the next one afresh.
            engine.parser.reset()
            return nil
        }
        var roles = [UInt8](repeating: SyntaxRole.plain.rawValue, count: length)
        paint(&roles, captures: captures(of: engine, in: tree, code: code))

        // Markdown: the inline grammar colors the text inside its blocks.
        if let inline = engine.inline, let root = tree.rootNode {
            var ranges: [TSRange] = []
            collect("inline", in: root, into: &ranges)
            if !ranges.isEmpty {
                inline.parser.includedRanges = ranges
                inline.parser.timeout = Self.parseTimeout
                if let inlineTree = inline.parser.parse(code) {
                    paint(&roles, captures: captures(of: inline, in: inlineTree, code: code))
                } else {
                    inline.parser.reset()
                }
            }
        }
        return Self.compress(roles)
    }

    private struct Capture {
        let range: NSRange
        let pattern: Int
        let role: SyntaxRole
    }

    private func captures(of engine: Engine, in tree: MutableTree, code: String) -> (captures: [Capture], laterWins: Bool) {
        var result: [Capture] = []
        let matches = engine.query.execute(in: tree).resolve(with: Predicate.Context(string: code))
        for match in matches {
            for capture in match.captures where capture.index < engine.roles.count {
                guard let role = engine.roles[capture.index], capture.range.length > 0 else { continue }
                result.append(Capture(range: capture.range, pattern: capture.patternIndex, role: role))
            }
        }
        return (result, engine.laterPatternsWin)
    }

    /// Colors the code: nodes nest, so larger ones are painted first and smaller ones inside
    /// them on top. Of two captures of the same text, the winning pattern is painted last.
    private func paint(_ roles: inout [UInt8], captures: (captures: [Capture], laterWins: Bool)) {
        let ordered = captures.captures.sorted { a, b in
            if a.range.length != b.range.length { return a.range.length > b.range.length }
            if a.range.location != b.range.location { return a.range.location < b.range.location }
            return captures.laterWins ? a.pattern < b.pattern : a.pattern > b.pattern
        }
        for capture in ordered {
            let start = max(0, capture.range.location), end = min(roles.count, NSMaxRange(capture.range))
            guard start < end else { continue }
            for index in start..<end { roles[index] = capture.role.rawValue }
        }
    }

    private func collect(_ type: String, in node: Node, into ranges: inout [TSRange]) {
        if node.nodeType == type {
            ranges.append(node.tsRange)
            return
        }
        for index in 0..<node.childCount {
            if let child = node.child(at: index) { collect(type, in: child, into: &ranges) }
        }
    }

    /// Runs of the same color, leaving out body text.
    private static func compress(_ roles: [UInt8]) -> [SyntaxRun] {
        var runs: [SyntaxRun] = []
        var index = 0
        while index < roles.count {
            let role = roles[index]
            var end = index + 1
            while end < roles.count, roles[end] == role { end += 1 }
            if role != SyntaxRole.plain.rawValue, let syntaxRole = SyntaxRole(rawValue: role) {
                runs.append(SyntaxRun(location: index, length: end - index, role: syntaxRole))
            }
            index = end
        }
        return runs
    }

    // MARK: - Engines

    private func engine(for language: CodeLanguage) -> Engine? {
        if let engine = engines[language.name] { return engine }
        guard !failedLanguages.contains(language.name) else { return nil }
        let inline = language.inline.flatMap {
            makeEngine(grammar: $0.grammar, queries: $0.queries, roles: language.roles, laterPatternsWin: false, inline: nil)
        }
        guard let engine = makeEngine(grammar: language.grammar, queries: language.queries, roles: language.roles,
                                      laterPatternsWin: language.laterPatternsWin, inline: inline)
        else {
            failedLanguages.insert(language.name)
            return nil
        }
        engines[language.name] = engine
        return engine
    }

    private func makeEngine(grammar: () -> OpaquePointer?, queries: [String], roles: [String: SyntaxRole],
                            laterPatternsWin: Bool, inline: Engine?) -> Engine? {
        guard let pointer = grammar() else { return nil }
        let language = Language(language: pointer)
        let parser = Parser()
        guard (try? parser.setLanguage(language)) != nil,
              let source = Self.querySource(queries),
              let query = try? Query(language: language, data: source)
        else { return nil }
        let captureRoles = (0..<query.captureCount).map { index in
            query.captureName(for: index).flatMap { SyntaxRoles.role(for: $0, overrides: roles) }
        }
        return Engine(parser: parser, query: query, roles: captureRoles, laterPatternsWin: laterPatternsWin, inline: inline)
    }

    /// The query files joined, in order.
    static func querySource(_ files: [String]) -> Data? {
        guard let folder = queriesFolder() else { return nil }
        var source = ""
        for file in files {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8) else { return nil }
            source += text + "\n"
        }
        return source.data(using: .utf8)
    }

    /// `Contents/Resources/Queries` inside the app bundle, or the SwiftPM resource bundle
    /// when running from `swift run` or tests.
    static func queriesFolder() -> URL? {
        if let resources = Bundle.main.resourceURL?.appendingPathComponent("Queries"),
           FileManager.default.fileExists(atPath: resources.path) {
            return resources
        }
        return Bundle.module.resourceURL?.appendingPathComponent("Queries")
    }

    // MARK: - Cache

    private func remember(_ runs: [SyntaxRun]?, for key: String, length: Int) {
        cache[key] = (runs, length)
        cacheOrder.append(key)
        cachedLength += length
        while cachedLength > cacheLimit, !cacheOrder.isEmpty {
            if let evicted = cache.removeValue(forKey: cacheOrder.removeFirst()) {
                cachedLength -= evicted.length
            }
        }
    }
}

/// Which role each tree-sitter capture name colors as. Grammars name captures in two
/// styles (`@keyword` and Neovim's `@keyword.conditional`), so a name is looked up whole,
/// then without its last dotted part, and so on.
enum SyntaxRoles {
    /// Names that color. A name maps to `.plain` when it should show as body text even
    /// inside a colored node.
    static let table: [String: SyntaxRole] = [
        "comment": .comment,
        "string": .string, "character": .string, "escape": .string, "text.uri": .string, "text.literal": .string,
        "keyword": .keyword, "conditional": .keyword, "repeat": .keyword, "include": .keyword, "import": .keyword,
        "exception": .keyword, "storageclass": .keyword, "label": .keyword, "attribute": .keyword,
        "type.qualifier": .keyword, "text.title": .keyword, "charset": .keyword, "media": .keyword,
        "keyframes": .keyword, "supports": .keyword,
        "number": .number, "float": .number,
        "boolean": .atom, "constant": .atom, "string.special.symbol": .atom, "diff.delta": .atom,
        "function.builtin": .builtin, "function.method.builtin": .builtin, "variable.builtin": .builtin,
        "type.builtin": .builtin, "module.builtin": .builtin, "function.macro": .builtin,
        "type": .type, "constructor": .type, "namespace": .type, "module": .type,
        "function": .function, "method": .function, "text.reference": .function,
        "tag": .tag,
        "diff.plus": .inserted, "inserted": .inserted,
        "diff.minus": .deleted, "deleted": .deleted,
        "variable": .plain, "parameter": .plain, "property": .plain, "field": .plain, "operator": .plain,
        "punctuation": .plain, "embedded": .plain, "none": .plain, "delimiter": .plain,
        "text.strong": .plain, "text.emphasis": .plain,
    ]

    /// Names that only mark things for other tools, such as Neovim's spell checking.
    static let ignored: Set<String> = ["spell"]

    static func role(for name: String, overrides: [String: SyntaxRole] = [:]) -> SyntaxRole? {
        // Names starting with an underscore are helpers inside a query, not colors.
        guard !name.hasPrefix("_"), !ignored.contains(name) else { return nil }
        var candidate = name
        while true {
            if let role = overrides[candidate] ?? table[candidate] { return role }
            guard let dot = candidate.lastIndex(of: ".") else { return nil }
            candidate = String(candidate[..<dot])
        }
    }
}
