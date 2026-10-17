import AppKit
import XCTest
@testable import Cera

final class CodeHighlighterTests: XCTestCase {
    private let highlighter = SyntaxHighlighter.shared

    /// The role of the `occurrence`th appearance of `token` in `code`, or nil for body text.
    private func role(of token: String, in code: String, language name: String, occurrence: Int = 1,
                      file: StaticString = #filePath, line: UInt = #line) -> SyntaxRole? {
        guard let language = CodeLanguages.language(info: name) else {
            XCTFail("no language \(name)", file: file, line: line)
            return nil
        }
        let text = code as NSString
        var range = NSRange(location: 0, length: 0)
        var searchFrom = 0
        for _ in 0..<occurrence {
            range = text.range(of: token, range: NSRange(location: searchFrom, length: text.length - searchFrom))
            guard range.location != NSNotFound else {
                XCTFail("\(token) not in the \(name) sample", file: file, line: line)
                return nil
            }
            searchFrom = NSMaxRange(range)
        }
        let runs = highlighter.runs(for: code, language: language) ?? []
        return runs.first { $0.location <= range.location && range.location < $0.location + $0.length }?.role
    }

    // MARK: - Every grammar

    func testEveryLanguageLoads() {
        XCTAssertEqual(CodeLanguages.all.count, 22)
        for language in CodeLanguages.all {
            XCTAssertNotNil(highlighter.runs(for: "x\n", language: language), "\(language.name) grammar and queries load")
        }
    }

    func testEveryCaptureNameHasAKnownMeaning() throws {
        let folder = try XCTUnwrap(SyntaxHighlighter.queriesFolder())
        let files = CodeLanguages.all.flatMap { $0.queries + ($0.inline?.queries ?? []) }
        let regex = try NSRegularExpression(pattern: "@([A-Za-z_][A-Za-z0-9_.-]*)")
        for file in Set(files) {
            let text = try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
            let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(";") }
            let source = lines.joined(separator: "\n") as NSString
            for match in regex.matches(in: source as String, range: NSRange(location: 0, length: source.length)) {
                let name = source.substring(with: match.range(at: 1))
                let known = SyntaxRoles.role(for: name) != nil || SyntaxRoles.ignored.contains(name) || name.hasPrefix("_")
                XCTAssertTrue(known, "\(file) uses @\(name), which has no role")
            }
        }
    }

    func testAliases() {
        XCTAssertEqual(CodeLanguages.language(info: "py")?.name, "python")
        XCTAssertEqual(CodeLanguages.language(info: "Python3 title=x")?.name, "python")
        XCTAssertEqual(CodeLanguages.language(info: "{.rust}")?.name, "rust")
        XCTAssertEqual(CodeLanguages.language(info: "c#")?.name, "csharp")
        XCTAssertEqual(CodeLanguages.language(info: "cs")?.name, "csharp")
        XCTAssertEqual(CodeLanguages.language(info: "c++")?.name, "cpp")
        XCTAssertEqual(CodeLanguages.language(info: "yml")?.name, "yaml")
        XCTAssertEqual(CodeLanguages.language(info: "postgresql")?.name, "sql")
        XCTAssertNil(CodeLanguages.language(info: "brainfuck"))
        XCTAssertNil(CodeLanguages.language(info: nil))
        XCTAssertNil(CodeLanguages.language(info: ""))
    }

    // MARK: - Each language colors what matters

    func testSwift() {
        let code = "/// Doc\n@MainActor\nfinal class Loader<T> {\n    func load(page: Int) async throws -> [T] {\n        let url = \"page=\\(page)\"\n        return try await fetch(url, 0xFF, nil)\n    }\n}\n"
        XCTAssertEqual(role(of: "Doc", in: code, language: "swift"), .comment)
        XCTAssertEqual(role(of: "class", in: code, language: "swift"), .keyword)
        XCTAssertEqual(role(of: "Loader", in: code, language: "swift"), .type)
        XCTAssertEqual(role(of: "load", in: code, language: "swift"), .function)
        XCTAssertEqual(role(of: "Int", in: code, language: "swift"), .type)
        XCTAssertEqual(role(of: "page=", in: code, language: "swift"), .string)
        XCTAssertNil(role(of: "page)", in: code, language: "swift"), "an interpolated expression is body text")
        XCTAssertEqual(role(of: "0xFF", in: code, language: "swift"), .number)
        XCTAssertEqual(role(of: "nil", in: code, language: "swift"), .atom)
    }

    func testPython() {
        let code = "# note\n@dataclass\nclass Order:\n    def total(self, rate: float = 0.5) -> int:\n        return sum([1, 2]) if True else None  # done\n    name = f\"x{rate}\"\n"
        XCTAssertEqual(role(of: "note", in: code, language: "python"), .comment)
        XCTAssertEqual(role(of: "class Order", in: code, language: "python"), .keyword)
        XCTAssertEqual(role(of: "Order", in: code, language: "python"), .type)
        XCTAssertEqual(role(of: "total", in: code, language: "python"), .function)
        XCTAssertEqual(role(of: "0.5", in: code, language: "python"), .number)
        XCTAssertEqual(role(of: "sum", in: code, language: "python"), .builtin)
        XCTAssertEqual(role(of: "True", in: code, language: "python"), .atom)
        XCTAssertEqual(role(of: "f\"x", in: code, language: "python"), .string)
    }

    func testJavaScriptAndJSX() {
        let code = "// c\nexport function f(a = 200) {\n  const s = `n=${a}`;\n  return <section className=\"t\">{s}</section>;\n}\n"
        XCTAssertEqual(role(of: "c\n", in: code, language: "jsx"), .comment)
        XCTAssertEqual(role(of: "function", in: code, language: "jsx"), .keyword)
        XCTAssertEqual(role(of: "f(", in: code, language: "jsx"), .function)
        XCTAssertEqual(role(of: "200", in: code, language: "jsx"), .number)
        XCTAssertEqual(role(of: "`n=", in: code, language: "jsx"), .string)
        XCTAssertEqual(role(of: "section", in: code, language: "jsx"), .tag)
        XCTAssertEqual(role(of: "className", in: code, language: "jsx"), .keyword)
    }

    func testTypeScriptAndTSX() {
        let code = "interface Page<T> { items: T[]; total: number }\nenum Role { Admin = 1 }\nconst x: Role = Role.Admin;\n"
        XCTAssertEqual(role(of: "interface", in: code, language: "ts"), .keyword)
        XCTAssertEqual(role(of: "Page", in: code, language: "ts"), .type)
        XCTAssertEqual(role(of: "number", in: code, language: "ts"), .builtin)
        XCTAssertEqual(role(of: "1", in: code, language: "ts"), .number)
        let tsx = "const A: FC = () => <table className=\"x\"><tr /></table>;\n"
        XCTAssertEqual(role(of: "table", in: tsx, language: "tsx"), .tag)
        XCTAssertEqual(role(of: "FC", in: tsx, language: "tsx"), .type)
        XCTAssertEqual(role(of: "\"x\"", in: tsx, language: "tsx"), .string)
    }

    func testJSONKeysStandOutFromValues() {
        let code = "{ \"name\": \"cera\", \"n\": 1.5, \"ok\": true, \"none\": null }\n"
        XCTAssertEqual(role(of: "\"name\"", in: code, language: "json"), .type)
        XCTAssertEqual(role(of: "\"cera\"", in: code, language: "json"), .string)
        XCTAssertEqual(role(of: "1.5", in: code, language: "json"), .number)
        XCTAssertEqual(role(of: "true", in: code, language: "json"), .atom)
        XCTAssertEqual(role(of: "null", in: code, language: "json"), .atom)
    }

    func testBash() {
        let code = "# c\nbackup() {\n  if [[ -f \"$F\" ]]; then echo \"ok $HOME\"; fi\n}\n"
        XCTAssertEqual(role(of: "c\n", in: code, language: "sh"), .comment)
        XCTAssertEqual(role(of: "if", in: code, language: "sh"), .keyword)
        XCTAssertEqual(role(of: "backup", in: code, language: "sh"), .function)
        XCTAssertEqual(role(of: "\"ok", in: code, language: "sh"), .string)
    }

    func testRust() {
        let code = "/// d\n#[derive(Debug)]\npub struct Counter<'a> { n: u64 }\nfn main() { let x = 1.5; println!(\"{}\", x); Ok(()) }\n"
        XCTAssertEqual(role(of: "d\n", in: code, language: "rs"), .comment)
        XCTAssertEqual(role(of: "pub", in: code, language: "rs"), .keyword)
        XCTAssertEqual(role(of: "Counter", in: code, language: "rs"), .type)
        XCTAssertEqual(role(of: "u64", in: code, language: "rs"), .builtin)
        XCTAssertEqual(role(of: "main", in: code, language: "rs"), .function)
        XCTAssertEqual(role(of: "println", in: code, language: "rs"), .builtin)
        XCTAssertEqual(role(of: "1.5", in: code, language: "rs"), .number)
        XCTAssertEqual(role(of: "\"{}\"", in: code, language: "rs"), .string)
    }

    func testGo() {
        let code = "// c\npackage cache\nfunc (c *Cache) Get(key string) error {\n\tc.mu.Lock()\n\treturn fmt.Errorf(\"x %v\", 1)\n}\n"
        XCTAssertEqual(role(of: "c\n", in: code, language: "go"), .comment)
        XCTAssertEqual(role(of: "func", in: code, language: "go"), .keyword)
        XCTAssertEqual(role(of: "Get", in: code, language: "go"), .function)
        XCTAssertEqual(role(of: "Lock", in: code, language: "go"), .function, "method calls keep their color")
        XCTAssertEqual(role(of: "string", in: code, language: "go"), .type)
        XCTAssertEqual(role(of: "\"x", in: code, language: "go"), .string)
        XCTAssertEqual(role(of: "1)", in: code, language: "go"), .number)
    }

    func testCAndCPP() {
        let c = "/* c */\n#define MAX 10\nstatic int push(char *s) { return strlen(s) > 0 ? 1 : 0; }\n"
        XCTAssertEqual(role(of: "c */", in: c, language: "c"), .comment)
        XCTAssertEqual(role(of: "static", in: c, language: "c"), .keyword)
        XCTAssertEqual(role(of: "int", in: c, language: "c"), .type, "C's grammar calls primitive types types")
        XCTAssertEqual(role(of: "push", in: c, language: "c"), .function)
        XCTAssertEqual(role(of: "1 :", in: c, language: "c"), .number)
        let cpp = "namespace geo { class Circle final : public Shape { double area() const noexcept override; }; }\n"
        XCTAssertEqual(role(of: "class", in: cpp, language: "c++"), .keyword)
        XCTAssertEqual(role(of: "Circle", in: cpp, language: "c++"), .type)
        XCTAssertEqual(role(of: "area", in: cpp, language: "c++"), .function)
    }

    func testCSharp() {
        let code = "/// <summary>s</summary>\n[Serializable]\npublic sealed record Order(int Id, string? Coupon = null);\nvar t = $\"Order {Id}\"; var m = 0.5m;\n"
        XCTAssertEqual(role(of: "summary", in: code, language: "cs"), .comment)
        XCTAssertEqual(role(of: "public", in: code, language: "c#"), .keyword)
        XCTAssertEqual(role(of: "Order", in: code, language: "csharp"), .type)
        XCTAssertEqual(role(of: "int", in: code, language: "csharp"), .builtin)
        XCTAssertEqual(role(of: "null", in: code, language: "csharp"), .atom)
        XCTAssertEqual(role(of: "$\"Order", in: code, language: "csharp"), .string)
        XCTAssertEqual(role(of: "0.5m", in: code, language: "csharp"), .number)
    }

    func testJavaAndKotlin() {
        let java = "/** d */\n@Override\npublic final class Inventory { private static final int LEVEL = 10; void f() { list.stream(); } }\n"
        XCTAssertEqual(role(of: "d */", in: java, language: "java"), .comment)
        XCTAssertEqual(role(of: "public", in: java, language: "java"), .keyword)
        XCTAssertEqual(role(of: "Inventory", in: java, language: "java"), .type)
        XCTAssertEqual(role(of: "stream", in: java, language: "java"), .function)
        XCTAssertEqual(role(of: "10", in: java, language: "java"), .number)
        let kotlin = "// c\ndata class Forecast(val day: String, val high: Double = 1.5)\nfun f() = \"x ${day}\"\n"
        XCTAssertEqual(role(of: "c\n", in: kotlin, language: "kt"), .comment)
        XCTAssertEqual(role(of: "class", in: kotlin, language: "kotlin"), .keyword)
        XCTAssertEqual(role(of: "1.5", in: kotlin, language: "kotlin"), .number)
        XCTAssertEqual(role(of: "\"x", in: kotlin, language: "kotlin"), .string)
    }

    func testRuby() {
        let code = "# c\nclass Invoice\n  TAX = 0.2\n  def call(x) = puts(\"n #{x}\") if x.nil?\nend\n"
        XCTAssertEqual(role(of: "c\n", in: code, language: "rb"), .comment)
        XCTAssertEqual(role(of: "class", in: code, language: "ruby"), .keyword)
        XCTAssertEqual(role(of: "Invoice", in: code, language: "ruby"), .type)
        XCTAssertEqual(role(of: "0.2", in: code, language: "ruby"), .number)
        XCTAssertEqual(role(of: "\"n", in: code, language: "ruby"), .string)
    }

    func testYAMLAndTOMLKeys() {
        let yaml = "# c\nname: Build\nretries: 3\nverbose: false\n"
        XCTAssertEqual(role(of: "c\n", in: yaml, language: "yml"), .comment)
        XCTAssertEqual(role(of: "name", in: yaml, language: "yaml"), .type)
        XCTAssertEqual(role(of: "Build", in: yaml, language: "yaml"), .string)
        XCTAssertEqual(role(of: "3", in: yaml, language: "yaml"), .number)
        XCTAssertEqual(role(of: "false", in: yaml, language: "yaml"), .atom)
        let toml = "# c\n[server]\nport = 8_080\nhost = \"x\"\n"
        XCTAssertEqual(role(of: "port", in: toml, language: "toml"), .type)
        XCTAssertEqual(role(of: "8_080", in: toml, language: "toml"), .number)
        XCTAssertEqual(role(of: "\"x\"", in: toml, language: "toml"), .string)
    }

    func testHTMLAndCSS() {
        let html = "<!-- c -->\n<a href=\"/\" class=\"x\">Home</a>\n"
        XCTAssertEqual(role(of: "c -->", in: html, language: "html"), .comment)
        XCTAssertEqual(role(of: "a ", in: html, language: "html"), .tag)
        XCTAssertEqual(role(of: "href", in: html, language: "html"), .keyword)
        XCTAssertEqual(role(of: "/\"", in: html, language: "html"), .string)
        let css = "/* c */\n@media print { .card > .t:hover { color: #4a89dc; width: calc(2px + 1em) !important; } }\n"
        XCTAssertEqual(role(of: "c */", in: css, language: "css"), .comment)
        XCTAssertEqual(role(of: "@media", in: css, language: "css"), .keyword)
        XCTAssertEqual(role(of: "2px", in: css, language: "css"), .number)
        XCTAssertEqual(role(of: "calc", in: css, language: "css"), .function)
    }

    func testSQL() {
        let code = "-- c\nSELECT name, SUM(total) AS revenue FROM orders WHERE status = 'active' AND paid = FALSE LIMIT 10;\n"
        XCTAssertEqual(role(of: "c\n", in: code, language: "sql"), .comment)
        XCTAssertEqual(role(of: "SELECT", in: code, language: "sql"), .keyword)
        XCTAssertEqual(role(of: "SUM", in: code, language: "sql"), .function)
        XCTAssertEqual(role(of: "'active'", in: code, language: "sql"), .string)
        XCTAssertEqual(role(of: "10", in: code, language: "sql"), .number)
        XCTAssertEqual(role(of: "FALSE", in: code, language: "postgres"), .atom)
    }

    func testMarkdownBlocksAndInlineText() {
        let code = "# Title\n\nSome `code` and [a link](https://x.com).\n\n- item\n"
        XCTAssertEqual(role(of: "Title", in: code, language: "md"), .keyword)
        XCTAssertEqual(role(of: "code", in: code, language: "markdown"), .string, "colored by the inline grammar")
        XCTAssertEqual(role(of: "a link", in: code, language: "markdown"), .function)
        XCTAssertEqual(role(of: "https", in: code, language: "markdown"), .string)
    }

    func testDiffLines() {
        let code = "--- a/f.swift\n+++ b/f.swift\n@@ -1,2 +1,2 @@\n-old line\n+new line\n context\n"
        XCTAssertEqual(role(of: "old line", in: code, language: "diff"), .deleted)
        XCTAssertEqual(role(of: "new line", in: code, language: "patch"), .inserted)
        XCTAssertNil(role(of: "context", in: code, language: "diff"))
    }

    // MARK: - In the document

    /// The color at `marker` after styling `text`.
    private func color(at marker: String, in text: String, theme: Theme = .midnight) -> NSColor? {
        let storage = NSTextStorage(string: text)
        MarkdownStyler(theme: theme).style(storage, caret: 0, availableWidth: 600)
        return storage.attribute(.foregroundColor, at: (text as NSString).range(of: marker).location, effectiveRange: nil) as? NSColor
    }

    func testColorsLandOnTheRightCharactersInNestedBlocks() {
        let syntax = Theme.midnight.syntax
        let quoted = "Intro\n\n> ```swift\n> let a = 1\n> ```\n"
        XCTAssertEqual(color(at: "let", in: quoted), syntax.keyword)
        XCTAssertEqual(color(at: "1\n", in: quoted), syntax.number)
        XCTAssertNotEqual(color(at: "> let", in: quoted), syntax.keyword, "the quote marker isn't code")
        let listed = "- Step:\n\n  ```py\n  return None\n  ```\n"
        XCTAssertEqual(color(at: "return", in: listed), syntax.keyword)
        XCTAssertEqual(color(at: "None", in: listed), syntax.atom)
    }

    func testPositionsWithEmojiAndWindowsLineEndings() {
        let syntax = Theme.midnight.syntax
        let emoji = "```js\nconst s = \"😀🎉\"; let n = 42;\n```\n"
        XCTAssertEqual(color(at: "42", in: emoji), syntax.number)
        XCTAssertEqual(color(at: "let", in: emoji), syntax.keyword)
        let crlf = "```py\r\nx = 1\r\nif x:\r\n    pass\r\n```\r\n"
        XCTAssertEqual(color(at: "if", in: crlf), syntax.keyword)
        XCTAssertEqual(color(at: "pass", in: crlf), syntax.keyword)
    }

    func testUnknownLanguagesStayPlainAndOldOnesKeepTheirColors() {
        let text = Theme.midnight.codeText
        XCTAssertEqual(color(at: "if", in: "```brainfuck\nif x\n```\n"), text)
        XCTAssertEqual(color(at: "if", in: "```\nif x\n```\n"), text)
        // PHP has no grammar yet; the simple colorer still knows its keywords.
        XCTAssertEqual(color(at: "function", in: "```php\nfunction f() {}\n```\n"), Theme.midnight.syntax.keyword)
    }

    func testLightThemesGetTheirOwnColors() {
        XCTAssertEqual(color(at: "class", in: "```swift\nclass A {}\n```\n", theme: .plain), Theme.plain.syntax.keyword)
        XCTAssertNotEqual(Theme.plain.syntax.keyword, Theme.midnight.syntax.keyword)
    }

    // MARK: - Cache and limits

    func testTheCacheReturnsTheSameRunsAndEditsChangeThem() throws {
        let python = try XCTUnwrap(CodeLanguages.language(info: "python"))
        let first = highlighter.runs(for: "x = 1\n", language: python)
        XCTAssertEqual(highlighter.runs(for: "x = 1\n", language: python), first)
        XCTAssertNotEqual(highlighter.runs(for: "x = 'a'\n", language: python), first)
    }

    func testHugeBlocksGetTheSimpleColors() throws {
        let python = try XCTUnwrap(CodeLanguages.language(info: "python"))
        let huge = String(repeating: "if x:\n    pass\n", count: SyntaxHighlighter.maxCodeLength / 10)
        XCTAssertNil(highlighter.runs(for: huge, language: python), "too long for tree-sitter")
        XCTAssertEqual(color(at: "if", in: "```python\n" + huge + "```\n"), Theme.midnight.syntax.keyword,
                       "the simple colorer still colors it")
    }

    func testCodeThatTimesOutIsNotParsedAgain() throws {
        let python = try XCTUnwrap(CodeLanguages.language(info: "python"))
        let code = String(repeating: "if x:\n    pass\n", count: 3_000) + "# timeout test\n"
        let saved = SyntaxHighlighter.parseTimeout
        defer { SyntaxHighlighter.parseTimeout = saved }
        SyntaxHighlighter.parseTimeout = 0.000_001
        XCTAssertNil(highlighter.runs(for: code, language: python), "gave up")
        SyntaxHighlighter.parseTimeout = 10 // Plenty, even for a debug build on a slow machine.
        XCTAssertNil(highlighter.runs(for: code, language: python), "the same code isn't tried again")
        XCTAssertNotNil(highlighter.runs(for: code + "x = 1\n", language: python), "edited code is")
    }

    func testAParseThatTimedOutDoesNotSpoilTheNext() throws {
        // tree-sitter keeps a timed-out parse to resume on the next call, whatever text that call has.
        let python = try XCTUnwrap(CodeLanguages.language(info: "python"))
        let saved = SyntaxHighlighter.parseTimeout
        defer { SyntaxHighlighter.parseTimeout = saved }
        SyntaxHighlighter.parseTimeout = 0.000_001
        XCTAssertNil(highlighter.runs(for: String(repeating: "if y:\n    pass\n", count: 3_000), language: python))
        SyntaxHighlighter.parseTimeout = 10
        XCTAssertEqual(role(of: "None", in: "return None\n", language: "python"), .atom)
    }

    func testParsingHasATimeout() {
        XCTAssertGreaterThan(SyntaxHighlighter.parseTimeout, 0)
        XCTAssertLessThanOrEqual(SyntaxHighlighter.parseTimeout, 0.1)
    }
}
