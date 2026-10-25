import XCTest
@testable import Cera

/// HTML from the clipboard as Markdown.
final class HTMLMarkdownTests: XCTestCase {
    private func markdown(_ html: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let markdown = HTMLMarkdown.markdown(fromHTML: html) else {
            XCTFail("no Markdown", file: file, line: line)
            return ""
        }
        return markdown
    }

    // MARK: Blocks

    func testHeadingsAndParagraphs() {
        XCTAssertEqual(markdown("<h1>Title</h1><p>One.</p><h3>Sub</h3><p>Two.</p>"), "# Title\n\nOne.\n\n### Sub\n\nTwo.")
    }

    func testHeadingWeightIsNotBold() {
        XCTAssertEqual(markdown("<h2><b>Bold heading</b></h2>"), "## Bold heading")
    }

    func testLineBreaks() {
        XCTAssertEqual(markdown("<p>one<br>two</p>"), "one\\\ntwo")
    }

    func testCodeBlockKeepsLinesAndLanguage() {
        XCTAssertEqual(markdown("<p>Run:</p><pre><code class=\"language-swift\">let a = 1\n  let b = 2\n</code></pre>"),
                       "Run:\n\n```swift\nlet a = 1\n  let b = 2\n```")
        XCTAssertEqual(markdown("<p>x</p><div class=\"highlight highlight-source-python\"><pre>print(1)</pre></div>"),
                       "x\n\n```python\nprint(1)\n```", "GitHub's language class")
        XCTAssertEqual(markdown("<p>x</p><pre>a ``` b</pre>"), "x\n\n````\na ``` b\n````", "a longer fence around backticks")
    }

    func testLists() {
        XCTAssertEqual(markdown("<ul><li>one</li><li>two<ul><li>nested</li></ul></li></ul>"), "- one\n- two\n  - nested")
        XCTAssertEqual(markdown("<ol start=\"3\"><li>three</li><li>four</li></ol>"), "3. three\n4. four")
        XCTAssertEqual(markdown("<ul><li>a</li><ul><li>under a</li></ul><li>b</li></ul>"), "- a\n  - under a\n- b",
                       "a list right inside a list belongs to the item before it")
    }

    func testTaskLists() {
        XCTAssertEqual(markdown("<ul><li><input type=\"checkbox\" disabled> open</li><li><input type=\"checkbox\" checked disabled> done</li></ul>"),
                       "- [ ] open\n- [x] done")
        XCTAssertEqual(markdown("<ul><li role=\"checkbox\" aria-checked=\"true\"><p>done</p></li><li role=\"checkbox\" aria-checked=\"false\"><p>open</p></li></ul>"),
                       "- [x] done\n- [ ] open", "Google Docs checklists")
    }

    func testGoogleDocsLevelsNest() {
        // Docs writes each level as its own list, with the level on the item.
        let html = "<ul><li aria-level=\"1\"><p>top</p></li></ul><ul><li aria-level=\"2\"><p>child</p></li></ul><ul><li aria-level=\"1\"><p>next</p></li></ul>"
        XCTAssertEqual(markdown(html), "- top\n  - child\n- next")
    }

    func testItemWithTwoParagraphsKeepsThemApart() {
        XCTAssertEqual(markdown("<ul><li><p>one</p><p>more</p></li></ul>"), "- one\n\n  more")
    }

    func testQuote() {
        XCTAssertEqual(markdown("<blockquote><p>one</p><p>two</p></blockquote>"), "> one\n>\n> two")
    }

    func testTable() {
        let html = "<table><thead><tr><th>Name</th><th>Note</th></tr></thead><tbody><tr><td>a|b</td><td><p>x</p><p>y</p></td></tr><tr><td>c</td></tr></tbody></table>"
        XCTAssertEqual(markdown(html), "| Name | Note |\n| --- | --- |\n| a\\|b | x y |\n| c |  |")
    }

    func testRule() {
        XCTAssertEqual(markdown("<p>a</p><hr><p>b</p>"), "a\n\n---\n\nb")
    }

    // MARK: Inline

    func testEmphasisFromTags() {
        XCTAssertEqual(markdown("<p><b>bold</b>, <i>italic</i>, <del>gone</del>, <code>x()</code></p>"),
                       "**bold**, *italic*, ~~gone~~, `x()`")
    }

    func testNestedEmphasis() {
        XCTAssertEqual(markdown("<p><b>bold <i>both</i></b> plain</p>"), "**bold *both*** plain")
    }

    func testSpacesStayOutsideMarkers() {
        XCTAssertEqual(markdown("<p>a<b> bold </b>b</p>"), "a **bold** b")
    }

    func testLinksAndImages() {
        XCTAssertEqual(markdown("<p>See <a href=\"https://example.com/a b\">the <b>docs</b></a>.</p>"),
                       "See [the **docs**](https://example.com/a%20b).")
        XCTAssertEqual(markdown("<p><a href=\"/relative\">here</a> and <a href=\"javascript:x()\">there</a></p>"), "here and there",
                       "links that don't work outside the page are dropped")
        XCTAssertEqual(markdown("<p><img src=\"https://a.b/p.png\" alt=\"A pic\"> <img src=\"data:image/png;base64,AA\" alt=\"inline\"></p>"),
                       "![A pic](https://a.b/p.png)")
    }

    func testAFragmentThatIsOneElementKeepsItsFormatting() {
        XCTAssertEqual(markdown("<b>bold</b>"), "**bold**")
        XCTAssertEqual(markdown("<a href=\"https://a.b\">link</a>"), "[link](https://a.b)")
    }

    func testCodeSpanAroundBackticks() {
        XCTAssertEqual(markdown("<p>x <code>a`b</code></p>"), "x ``a`b``")
    }

    // MARK: Google Docs

    func testGoogleDocsStyledSpans() {
        let html = """
        <meta charset='utf-8'><b style="font-weight:normal;" id="docs-internal-guid-1234"><h2 dir="ltr"><span style="font-size:16pt;font-weight:400;">Meeting notes</span></h2>\
        <p dir="ltr"><span style="font-weight:700;">Bold</span><span> and </span><span style="font-style:italic;">italic</span>\
        <span> and </span><span style="text-decoration:line-through;">struck</span><span> and </span>\
        <span style="font-family:'Courier New',monospace;">code</span><span> and </span><a href="https://example.com"><span style="text-decoration:underline;">a link</span></a></p></b>\
        <br class="Apple-interchange-newline">
        """
        XCTAssertEqual(markdown(html), "## Meeting notes\n\n**Bold** and *italic* and ~~struck~~ and `code` and [a link](https://example.com)")
    }

    // MARK: Text stays text

    func testMarkdownCharactersAreEscaped() {
        XCTAssertEqual(markdown("<p>2 * 3 and `x` and [a] and \\ and &lt;div&gt; and a &lt; b</p>"),
                       "2 \\* 3 and \\`x\\` and \\[a] and \\\\ and \\<div> and a < b")
        XCTAssertEqual(markdown("<p>snake_case and _under_ and ~~x~~</p>"), "snake_case and \\_under\\_ and \\~\\~x\\~\\~")
        XCTAssertEqual(markdown("<p>&amp;copy; stays</p>"), "\\&copy; stays")
    }

    func testLineStartsThatWouldBeSyntaxAreEscaped() {
        XCTAssertEqual(markdown("<p># not a heading</p><p>- not a bullet</p><p>2026. A year</p><p>&gt; not a quote</p><p>---</p>"),
                       "\\# not a heading\n\n\\- not a bullet\n\n2026\\. A year\n\n\\> not a quote\n\n\\---")
    }

    func testWhitespaceCollapsesAsInABrowser() {
        XCTAssertEqual(markdown("<p>\n  one\n   two  </p>\n\n<p>three</p>"), "one two\n\nthree")
    }

    // MARK: Not converted

    func testCodeEditorCopyIsLeftToPlainPaste() {
        // VS Code copies colored, monospaced HTML.
        let html = "<div style=\"color: #d4d4d4;font-family: Menlo, Monaco, 'Courier New', monospace;\"><div><span style=\"color: #569cd6;\">let</span><span> a = </span><span>1</span></div></div>"
        XCTAssertNil(HTMLMarkdown.markdown(fromHTML: html))
        XCTAssertNil(HTMLMarkdown.markdown(fromHTML: "<pre>only code</pre>"))
    }

    func testNothingToConvert() {
        XCTAssertNil(HTMLMarkdown.markdown(fromHTML: "<p>  </p><br>"))
        XCTAssertNil(HTMLMarkdown.markdown(fromHTML: ""))
    }

    func testScriptsAndStylesAreDropped() {
        XCTAssertEqual(markdown("<style>p{}</style><script>alert(1)</script><p>text</p>"), "text")
    }

    // MARK: Web archive

    func testHTMLFromAWebArchive() throws {
        let archive: [String: Any] = ["WebMainResource": [
            "WebResourceData": Data("<p><b>hi</b></p>".utf8), "WebResourceTextEncodingName": "UTF-8",
            "WebResourceMIMEType": "text/html", "WebResourceURL": "about:blank"
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        XCTAssertEqual(HTMLMarkdown.html(fromWebArchive: data), "<p><b>hi</b></p>")
    }
}
