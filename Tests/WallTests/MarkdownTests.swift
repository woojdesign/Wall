import XCTest
@testable import Wall

final class MarkdownTests: XCTestCase {

    func testHeadingLevels() {
        XCTAssertEqual(Markdown.headingLevel(of: "# Title"), 1)
        XCTAssertEqual(Markdown.headingLevel(of: "## Section"), 2)
        XCTAssertEqual(Markdown.headingLevel(of: "###### Deep"), 6)
    }

    func testHashesAloneStyleWhileTyping() {
        // Styled before the space is typed, so headers grow live.
        XCTAssertEqual(Markdown.headingLevel(of: "###"), 3)
    }

    func testNotAHeading() {
        XCTAssertEqual(Markdown.headingLevel(of: "no hash"), 0)
        XCTAssertEqual(Markdown.headingLevel(of: "#hashtag"), 0)   // no space, has trailing text
        XCTAssertEqual(Markdown.headingLevel(of: "####### too many"), 0)  // 7 = not a heading
        XCTAssertEqual(Markdown.headingLevel(of: ""), 0)
    }
}
