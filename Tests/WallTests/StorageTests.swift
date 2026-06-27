import XCTest
@testable import Wall

final class StorageTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wall-storage-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func write(_ name: String, in dir: URL, _ contents: String = "x") throws {
        try contents.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testMoveWritingsMovesOnlyMarkdown() throws {
        let old = tmp.appendingPathComponent("old")
        let new = tmp.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try write("2026-06-27-1000.md", in: old)
        try write("2026-06-27-1100.md", in: old)
        try write("notes.txt", in: old)   // must be left behind

        let moved = Storage.moveWritings(from: old, to: new)
        XCTAssertEqual(moved, 2)
        XCTAssertEqual(Storage.writingCount(in: new), 2)
        XCTAssertEqual(Storage.writingCount(in: old), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("notes.txt").path))
    }

    func testMoveWritingsDoesNotClobber() throws {
        let old = tmp.appendingPathComponent("old")
        let new = tmp.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try write("clash.md", in: old, "from-old")
        try write("clash.md", in: new, "already-here")

        let moved = Storage.moveWritings(from: old, to: new)
        XCTAssertEqual(moved, 1)
        // Original untouched; the moved file got a unique name.
        XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("clash.md"), encoding: .utf8), "already-here")
        XCTAssertEqual(Storage.writingCount(in: new), 2)
    }

    func testUniqueDestinationAppendsSuffix() throws {
        let target = tmp.appendingPathComponent("a.md")
        XCTAssertEqual(Storage.uniqueDestination(target), target)   // free → unchanged
        try write("a.md", in: tmp)
        XCTAssertEqual(Storage.uniqueDestination(target).lastPathComponent, "a-1.md")
    }
}
