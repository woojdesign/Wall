import XCTest
@testable import Wall

final class ArchiveTests: XCTestCase {

    private func entry(_ url: String, _ date: Date, _ text: String) -> Entry {
        Entry(url: URL(fileURLWithPath: url), date: date, text: text)
    }

    // MARK: Entry derivation

    func testWordCount() {
        XCTAssertEqual(entry("/tmp/a.md", .now, "the quick brown fox").wordCount, 4)
    }

    func testPreviewSkipsLeadingBlankLines() {
        let e = entry("/tmp/a.md", .now, "\n\n   First real line  \nsecond line")
        XCTAssertEqual(e.preview, "First real line")
    }

    func testPreviewEmptyText() {
        XCTAssertEqual(entry("/tmp/a.md", .now, "   \n\n").preview, "Empty")
    }

    func testFilenameStampParses() {
        let d = Entry.filenameFormatter.date(from: "2026-06-27-1430")
        XCTAssertNotNil(d)
    }

    // MARK: Grouping

    private func fixedCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    func testBucketTitles() {
        let cal = fixedCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 27, hour: 12))!
        XCTAssertEqual(EntryGrouping.bucketTitle(for: now, now: now, calendar: cal), "Today")

        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(EntryGrouping.bucketTitle(for: yesterday, now: now, calendar: cal), "Yesterday")

        let midWeek = cal.date(byAdding: .day, value: -4, to: now)!
        XCTAssertEqual(EntryGrouping.bucketTitle(for: midWeek, now: now, calendar: cal), "This Week")

        let old = cal.date(byAdding: .day, value: -60, to: now)!
        let title = EntryGrouping.bucketTitle(for: old, now: now, calendar: cal)
        XCTAssertFalse(["Today", "Yesterday", "This Week"].contains(title))
        XCTAssertTrue(title.contains("2026"))   // "April 2026"
    }

    func testGroupedPreservesOrderWithoutDuplicateHeaders() {
        let cal = fixedCalendar()
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 27, hour: 12))!
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }

        // Newest-first, as allWritings() returns them.
        let entries = [
            entry("/tmp/0a.md", daysAgo(0), "a"),
            entry("/tmp/0b.md", daysAgo(0), "b"),
            entry("/tmp/1.md",  daysAgo(1), "c"),
            entry("/tmp/4.md",  daysAgo(4), "d"),
        ]
        let groups = EntryGrouping.grouped(entries, now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday", "This Week"])
        XCTAssertEqual(groups.first?.entries.count, 2)   // two Today entries coalesced
    }
}
