import XCTest
@testable import Wall

@MainActor
final class NavigationTests: XCTestCase {

    // ⌘L must flip BOTH ways. The first cut only ever went to .archive, leaving
    // no way back via the keyboard.
    func testToggleGoesBothWays() {
        let nav = Navigation()
        XCTAssertEqual(nav.tab, .write)
        nav.toggleArchive()
        XCTAssertEqual(nav.tab, .archive)
        nav.toggleArchive()
        XCTAssertEqual(nav.tab, .write)
    }
}
