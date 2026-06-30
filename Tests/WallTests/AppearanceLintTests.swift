import XCTest

/// Structural guard: no view may pin `.preferredColorScheme(.light)`.
///
/// Wall has dark mode now — appearance is applied app-wide via
/// `NSApplication.appearance`. A stray light pin silently strands its view in
/// light regardless of the user's choice; that exact bug shipped in 0.2.4 (the
/// Archive, About, and menu-bar popover each kept a leftover pin). Catch it in CI
/// instead of by eye.
final class AppearanceLintTests: XCTestCase {
    func testNoLightColorSchemePins() throws {
        let sources = try Self.sourcesDirectory()
        let files = try FileManager.default
            .contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }

        let offenders = try files.filter {
            try String(contentsOf: $0, encoding: .utf8).contains("preferredColorScheme(.light)")
        }.map(\.lastPathComponent).sorted()

        XCTAssertTrue(offenders.isEmpty,
            "preferredColorScheme(.light) found in \(offenders.joined(separator: ", ")) — "
            + "this strands the view in light. Remove the pin; appearance is app-wide via AppAppearance.")
    }

    /// Walk up from this test file to the package root, then into Sources/Wall.
    private static func sourcesDirectory() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Sources/Wall", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("Sources/Wall not found from \(#filePath)")
    }
}
