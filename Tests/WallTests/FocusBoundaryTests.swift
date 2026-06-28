import XCTest
@testable import Wall

final class FocusBoundaryTests: XCTestCase {

    /// The text covered by the active-sentence range, for readable assertions.
    private func active(_ text: String, caret: Int) -> String {
        let r = FocusBoundary.sentenceRange(in: text, caret: caret)
        return (text as NSString).substring(with: r)
    }

    func testCaretInsideSentence() {
        let t = "First one. Second one."
        // caret in "Second"
        XCTAssertEqual(active(t, caret: 15), "Second one.")
    }

    // The bug the locale tokenizer caused: dimming depended on whether the next
    // word was capitalized. The deterministic boundary must NOT.
    func testPeriodBoundaryIsConsistentRegardlessOfCapitalization() {
        let lower = "One sentence. another sentence"
        let upper = "One sentence. Another sentence"
        // caret at end of each — active sentence should be the second run in both
        XCTAssertEqual(active(lower, caret: lower.count), "another sentence")
        XCTAssertEqual(active(upper, caret: upper.count), "Another sentence")
    }

    func testExclamationAndQuestionAreBoundaries() {
        XCTAssertEqual(active("Wow! Next.", caret: 6), "Next.")          // in "Next"
        XCTAssertEqual(active("Really? Yes.", caret: 9), "Yes.")        // in "Yes"
    }

    func testJustFinishedSentenceStaysLit() {
        // Caret right after the terminator, nothing typed yet → keep the
        // finished sentence active rather than going fully dim.
        let t = "All done."
        XCTAssertEqual(active(t, caret: t.count), "All done.")
    }

    func testNewlineBoundsTheSentence() {
        let t = "Paragraph one\nParagraph two"
        XCTAssertEqual(active(t, caret: 20), "Paragraph two")          // in second line
    }

    func testEmptyText() {
        XCTAssertEqual(FocusBoundary.sentenceRange(in: "", caret: 0).length, 0)
    }

    // Enumerators ("1.", "2.") must not segment the active text — a period right
    // after a digit isn't a sentence end.
    func testInlineEnumeratorsAreNotBoundaries() {
        let t = "I need to 1. rest and 2. reflect on things"
        // caret near the end — the whole run stays one active sentence, not cut
        // at "1." or "2."
        XCTAssertEqual(active(t, caret: t.count), "I need to 1. rest and 2. reflect on things")
    }

    func testListMarkerAtLineStartNotABoundary() {
        let t = "1. first point that runs on"
        XCTAssertEqual(active(t, caret: t.count), "1. first point that runs on")
    }

    func testDecimalNumberNotABoundary() {
        let t = "It cost 3.14 dollars today"
        XCTAssertEqual(active(t, caret: t.count), "It cost 3.14 dollars today")
    }

    func testRealPeriodStillBoundsAfterEnumerator() {
        // A genuine sentence end after a list item still bounds.
        let t = "1. do this. Then that"
        XCTAssertEqual(active(t, caret: t.count), "Then that")
    }
}
