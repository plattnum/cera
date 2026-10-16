import XCTest
@testable import Cera

final class ImageSizeTests: XCTestCase {
    func testAddsAWidth() {
        XCTAssertEqual(ImageLine("![pic](a.png)")?.settingWidth(300), "![pic|300](a.png)")
    }

    func testReplacesAWidth() {
        XCTAssertEqual(ImageLine("![pic|500](a.png)")?.settingWidth(300), "![pic|300](a.png)")
    }

    func testReplacesAWidthAndHeight() {
        XCTAssertEqual(ImageLine("![pic|30x20](a.png)")?.settingWidth(700), "![pic|700](a.png)")
    }

    func testRemovesTheSize() {
        XCTAssertEqual(ImageLine("![pic|500](a.png)")?.settingWidth(nil), "![pic](a.png)")
    }

    func testEmptyAltText() {
        XCTAssertEqual(ImageLine("![](a.png)")?.settingWidth(300), "![|300](a.png)")
    }

    func testKeepsAPipeThatIsNotASize() {
        XCTAssertEqual(ImageLine("![this|that](a.png)")?.settingWidth(300), "![this|that|300](a.png)")
    }

    func testKeepsTheRestOfTheLine() {
        XCTAssertEqual(ImageLine("  ![café](my%20pic.png \"Title\")")?.settingWidth(300),
                       "  ![café|300](my%20pic.png \"Title\")")
    }

    func testReadsTheCurrentSize() {
        XCTAssertEqual(ImageLine("![pic|300](a.png)")?.width, 300)
        XCTAssertNil(ImageLine("![pic](a.png)")?.width)
        XCTAssertNil(ImageLine("![pic|300x200](a.png)")?.width, "a box isn't a plain width")
    }

    func testOnlyALoneImageCounts() {
        XCTAssertNil(ImageLine("see ![pic](a.png)"))
        XCTAssertNil(ImageLine("plain text"))
        XCTAssertNil(ImageLine("![a](a.png) ![b](b.png)"))
    }

    func testRequestedSizeReadsWidthAndBox() {
        XCTAssertEqual(ImageSize.requested(alt: "pic|300")?.width, 300)
        XCTAssertNil(ImageSize.requested(alt: "pic|300")?.height)
        XCTAssertEqual(ImageSize.requested(alt: "pic|300x200")?.height, 200)
        XCTAssertNil(ImageSize.requested(alt: "this|that"))
        XCTAssertNil(ImageSize.requested(alt: "pic|0"))
    }
}
