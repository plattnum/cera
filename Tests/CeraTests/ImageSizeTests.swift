import XCTest
@testable import Cera

final class ImageSizeTests: XCTestCase {
    func testRequestedSizeReadsWidthAndBox() {
        XCTAssertEqual(ImageSize.requested(alt: "pic|300")?.width, 300)
        XCTAssertNil(ImageSize.requested(alt: "pic|300")?.height)
        XCTAssertEqual(ImageSize.requested(alt: "pic|300x200")?.height, 200)
        XCTAssertNil(ImageSize.requested(alt: "this|that"))
        XCTAssertNil(ImageSize.requested(alt: "pic|0"))
    }
}
