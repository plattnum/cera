import XCTest
@testable import Cera

final class RecentDocumentsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "cera.tests.recent.\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    func testMostRecentFirstWithoutDuplicates() {
        let recents = RecentDocuments(defaults: defaults)
        recents.note(url("/a/one.md"))
        recents.note(url("/a/two.md"))
        recents.note(url("/a/one.md"))
        XCTAssertEqual(recents.urls.map(\.path), ["/a/one.md", "/a/two.md"])
    }

    func testKeepsOnlyTheLimit() {
        let recents = RecentDocuments(defaults: defaults)
        for index in 0..<(RecentDocuments.limit + 3) {
            recents.note(url("/a/\(index).md"))
        }
        XCTAssertEqual(recents.urls.count, RecentDocuments.limit)
        XCTAssertEqual(recents.urls.first?.path, "/a/\(RecentDocuments.limit + 2).md")
    }

    func testSurvivesRelaunch() {
        RecentDocuments(defaults: defaults).note(url("/a/kept.md"))
        XCTAssertEqual(RecentDocuments(defaults: defaults).urls.map(\.path), ["/a/kept.md"])
    }

    func testRemoveAndClear() {
        let recents = RecentDocuments(defaults: defaults)
        recents.note(url("/a/one.md"))
        recents.note(url("/a/two.md"))
        recents.remove(url("/a/one.md"))
        XCTAssertEqual(recents.urls.map(\.path), ["/a/two.md"])
        recents.clear()
        XCTAssertTrue(recents.urls.isEmpty)
        XCTAssertTrue(RecentDocuments(defaults: defaults).urls.isEmpty)
    }

    func testSameNamesShowTheirFolder() {
        let recents = RecentDocuments(defaults: defaults)
        recents.note(url("/repos/alpha/README.md"))
        recents.note(url("/repos/beta/README.md"))
        recents.note(url("/repos/beta/notes.md"))
        XCTAssertEqual(recents.title(for: url("/repos/alpha/README.md")), "README.md — alpha")
        XCTAssertEqual(recents.title(for: url("/repos/beta/notes.md")), "notes.md")
    }
}
