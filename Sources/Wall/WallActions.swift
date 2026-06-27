import AppKit
import Foundation

/// Quiet exits from the wall.
///
/// The app refuses to be a notepad — these are the side doors: take the text
/// with you (clipboard), or find the file on disk (Finder). Browsing,
/// previewing, and searching live in the user's own tools, not here.
enum WallActions {
    @MainActor
    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @MainActor
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// The most recent .md in Documents/Wall, or nil if none exist yet.
    static func mostRecentWriting() -> URL? {
        guard let dir = FileManager.wallDocuments else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { $0.pathExtension == "md" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
            .first
    }

    /// Read a writing file, or empty string on failure.
    static func contents(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
