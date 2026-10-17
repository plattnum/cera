import AppKit
import XCTest
@testable import Cera

final class MermaidTests: XCTestCase {
    private static let flowchart = "flowchart TD\n    A[Start] --> B{Choice}\n    B -->|yes| C[Do it]\n    B -->|no| D[Skip]"

    /// Styles `text` with the caret at `caret` and returns the storage.
    private func styled(_ text: String, caret: Int? = nil, theme: Theme = .midnight, width: CGFloat = 600) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler(theme: theme).style(storage, caret: caret ?? (text as NSString).length, availableWidth: width)
        return storage
    }

    private func diagram(in storage: NSTextStorage) -> (block: ImageBlock, range: NSRange)? {
        var found: (ImageBlock, NSRange)?
        storage.enumerateAttribute(.imageBlock, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if let block = value as? ImageBlock { found = (block, range); stop.pointee = true }
        }
        return found
    }

    private func hasCodePanel(_ storage: NSTextStorage, at location: Int) -> Bool {
        storage.attribute(.codeBlock, at: location, effectiveRange: nil) != nil
    }

    // MARK: - Which blocks

    func testLanguageName() {
        XCTAssertTrue(MermaidDiagrams.isMermaid(info: "mermaid"))
        XCTAssertTrue(MermaidDiagrams.isMermaid(info: "Mermaid"))
        XCTAssertTrue(MermaidDiagrams.isMermaid(info: "MERMAID title=\"x\""))
        XCTAssertFalse(MermaidDiagrams.isMermaid(info: "mermaidjs"))
        XCTAssertFalse(MermaidDiagrams.isMermaid(info: "swift"))
        XCTAssertFalse(MermaidDiagrams.isMermaid(info: ""))
        XCTAssertFalse(MermaidDiagrams.isMermaid(info: nil))
    }

    // MARK: - Drawing

    func testClosedBlockIsDrawnAsTheDiagram() throws {
        let text = "Before\n\n```mermaid\n\(Self.flowchart)\n```\n\nAfter\n"
        let storage = styled(text)
        let (block, range) = try XCTUnwrap(diagram(in: storage))
        let opening = (text as NSString).range(of: "```mermaid")
        XCTAssertEqual(range, opening, "on the opening fence's line")
        XCTAssertEqual(block.x, 0)
        XCTAssertGreaterThan(block.size.height, 50)
        XCTAssertFalse(hasCodePanel(storage, at: opening.location), "no code panel behind it")

        // Every line of the block is hidden; all but the first collapse.
        let firstLine = (text as NSString).lineRange(for: opening)
        let style = try XCTUnwrap(storage.attribute(.paragraphStyle, at: opening.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.minimumLineHeight, block.size.height)
        let inside = (text as NSString).range(of: "A[Start]").location
        XCTAssertEqual((storage.attribute(.font, at: inside, effectiveRange: nil) as? NSFont)?.pointSize, MarkdownStyler.hiddenFont.pointSize)
        let collapsed = try XCTUnwrap(storage.attribute(.paragraphStyle, at: inside, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertLessThan(collapsed.maximumLineHeight, 1)
        XCTAssertGreaterThan(collapsed.maximumLineHeight, 0, "zero would mean no limit")
        XCTAssertFalse(NSLocationInRange(inside, firstLine))
        // The text around it is untouched.
        XCTAssertNotEqual((storage.attribute(.font, at: (text as NSString).range(of: "After").location, effectiveRange: nil) as? NSFont)?.pointSize,
                          MarkdownStyler.hiddenFont.pointSize)
    }

    func testCursorInTheBlockShowsTheCode() {
        let text = "```mermaid\n\(Self.flowchart)\n```\n\nAfter\n"
        for marker in ["```mermaid", "B -->|no|", "```\n\nAfter"] {
            let storage = styled(text, caret: (text as NSString).range(of: marker).location)
            XCTAssertNil(diagram(in: storage), "cursor at \(marker)")
            XCTAssertTrue(hasCodePanel(storage, at: 0), "styled as code with the cursor at \(marker)")
        }
    }

    func testBrokenOrUnclosedBlocksStayCode() {
        let broken = "```mermaid\nflowchart TD\n    A[Unclosed --> B\n```\n\nAfter\n"
        XCTAssertNil(diagram(in: styled(broken)))
        XCTAssertTrue(hasCodePanel(styled(broken), at: 0))

        let unknown = "```mermaid\nnotADiagram\n  x\n```\n\nAfter\n"
        XCTAssertNil(diagram(in: styled(unknown)))

        let unclosed = "Before\n\n```mermaid\n\(Self.flowchart)\n"
        XCTAssertNil(diagram(in: styled(unclosed, caret: 0)))

        // A ~~~ line doesn't close a ``` fence.
        let mismatched = "Before\n\n```mermaid\n\(Self.flowchart)\n~~~\n"
        XCTAssertNil(diagram(in: styled(mismatched, caret: 0)))
    }

    func testAFenceTooIndentedToCloseLeavesTheBlockOpen() {
        // In a list item, a closing fence indented four or more spaces past the item's text is code.
        let listed = "- Flow:\n\n  ```mermaid\n  flowchart LR\n    A --> B\n      ```\n\nAfter\n"
        XCTAssertNil(diagram(in: styled(listed)))
        XCTAssertNil(diagram(in: styled("```mermaid\n\(Self.flowchart)\n    ```\n\nAfter\n")), "four spaces at the top level too")
        XCTAssertNotNil(diagram(in: styled("```mermaid\n\(Self.flowchart)\n   ```\n\nAfter\n")), "three spaces still close it")
    }

    func testOtherFenceStyles() {
        XCTAssertNotNil(diagram(in: styled("~~~mermaid\n\(Self.flowchart)\n~~~\n\nAfter\n")))
        XCTAssertNotNil(diagram(in: styled("```` Mermaid\n\(Self.flowchart)\n`````\n\nAfter\n")))
        XCTAssertNil(diagram(in: styled("```swift\n\(Self.flowchart)\n```\n\nAfter\n")), "only mermaid blocks")
    }

    func testNestedInAQuoteOrList() throws {
        let quoted = "> ```mermaid\n" + Self.flowchart.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n") + "\n> ```\n\nAfter\n"
        let inQuote = try XCTUnwrap(diagram(in: styled(quoted)))
        XCTAssertEqual(inQuote.block.x, Theme.midnight.quoteIndent)

        let listed = "- Flow:\n\n  ```mermaid\n" + Self.flowchart.split(separator: "\n").map { "  \($0)" }.joined(separator: "\n") + "\n  ```\n\nAfter\n"
        let inList = try XCTUnwrap(diagram(in: styled(listed)))
        XCTAssertEqual(inList.block.x, Theme.midnight.listIndent)
    }

    // MARK: - Size and theme

    func testWideDiagramsShrinkToTheColumnAndSmallOnesMatchTheBodyText() throws {
        let wide = "```mermaid\nflowchart LR\n  A[A long first step] --> B[A long second step] --> C[A long third step] --> D[A long fourth step]\n```\n\nAfter\n"
        let narrow = try XCTUnwrap(diagram(in: styled(wide, width: 300))).block
        XCTAssertEqual(narrow.size.width, 300)
        let natural = try XCTUnwrap(diagram(in: styled(wide, width: 5000))).block
        XCTAssertEqual(natural.size.width, (natural.image.size.width * 16 / 12).rounded(),
                       "labels drawn at Midnight's 16-point body size")
        XCTAssertEqual(narrow.size.height, natural.size.height * 300 / natural.size.width, accuracy: 1, "keeps its shape")
    }

    func testRestylingReusesTheSameImageUntilTheThemeChanges() throws {
        let text = "```mermaid\n\(Self.flowchart)\n```\n\nAfter\n"
        let first = try XCTUnwrap(diagram(in: styled(text))).block
        let again = try XCTUnwrap(diagram(in: styled(text))).block
        XCTAssertTrue(first.image === again.image)
        XCTAssertEqual(first, again, "an unchanged diagram isn't a change")
        let plain = try XCTUnwrap(diagram(in: styled(text, theme: .plain))).block
        XCTAssertFalse(first.image === plain.image)
    }

    func testScaleMatchesEachThemesBodyText() {
        XCTAssertEqual(MermaidDiagrams.scale(for: .midnight), 16.0 / 12, accuracy: 0.001)
        XCTAssertEqual(MermaidDiagrams.scale(for: .airy), 20.0 / 12, accuracy: 0.001)
        for choice in ThemeChoice.allCases {
            XCTAssertGreaterThanOrEqual(MermaidDiagrams.scale(for: choice.theme), 1, choice.theme.name)
        }
    }

    func testADiagramDrawnAgainIsTheSameDiagram() throws {
        // The cache can let an image go and draw it again as a new image; that mustn't count as a change.
        let one = NSImage(size: NSSize(width: 10, height: 10)), two = NSImage(size: NSSize(width: 10, height: 10))
        let size = NSSize(width: 10, height: 10)
        XCTAssertEqual(ImageBlock(image: one, size: size, x: 0, key: "midnight:A"), ImageBlock(image: two, size: size, x: 0, key: "midnight:A"))
        XCTAssertNotEqual(ImageBlock(image: one, size: size, x: 0, key: "midnight:A"), ImageBlock(image: one, size: size, x: 0, key: "plain:A"))
        XCTAssertNotEqual(ImageBlock(image: one, size: size, x: 0), ImageBlock(image: two, size: size, x: 0), "pictures compare by image")
        XCTAssertNotEqual(ImageBlock(image: one, size: size, x: 0, key: "k"), ImageBlock(image: one, size: size, x: 4, key: "k"))
        // Diagrams carry their theme and source.
        let text = "```mermaid\n\(Self.flowchart)\n```\n\nAfter\n"
        let block = try XCTUnwrap(diagram(in: styled(text))).block
        XCTAssertEqual(block.key, "mermaid\u{0}Midnight\u{0}" + Self.flowchart + "\n")
    }

    func testThemeColors() {
        let theme = MermaidDiagrams.diagramTheme(for: .plain)
        XCTAssertEqual(theme.ink, Theme.plain.text)
        XCTAssertEqual(theme.canvas, Theme.plain.background)
        XCTAssertFalse(theme.prefersDark)
        XCTAssertTrue(MermaidDiagrams.diagramTheme(for: .midnight).prefersDark)
    }

    func testAccentIsARealColorInEveryTheme() {
        // White labels sit on the accent (a mindmap's center), so a gray accent would be unreadable.
        for choice in ThemeChoice.allCases {
            let accent = MermaidDiagrams.accent(for: choice.theme).usingColorSpace(.sRGB)!
            XCTAssertGreaterThanOrEqual(accent.saturationComponent, 0.2, choice.theme.name)
        }
        XCTAssertEqual(MermaidDiagrams.accent(for: .midnight), Theme.midnight.selection, "Midnight's links are gray")
        XCTAssertEqual(MermaidDiagrams.accent(for: .plain), Theme.plain.link)
    }

    // MARK: - In a text view

    @MainActor
    func testLaidOutAtTheDiagramsHeight() throws {
        let text = "Before\n\n```mermaid\n\(Self.flowchart)\n```\n\nAfter\n"
        let textView = MarkdownTextView.makeEditor(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        textView.string = text
        MarkdownStyler(theme: .midnight).style(textView.textStorage!, caret: 0, availableWidth: 600)
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        layoutManager.ensureLayout(for: try XCTUnwrap(textView.textContainer))
        let (block, _) = try XCTUnwrap(diagram(in: textView.textStorage!))
        let ns = text as NSString
        func lineTop(_ marker: String) -> CGFloat {
            layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: ns.range(of: marker).location),
                                           effectiveRange: nil).minY
        }
        // From the diagram's line to the line after the block: the diagram plus a hair per collapsed line.
        let blockHeight = lineTop("\nAfter") - lineTop("```mermaid")
        XCTAssertEqual(blockHeight, block.size.height, accuracy: 2)
    }
}
