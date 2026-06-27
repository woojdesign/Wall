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

    /// Every .md in Documents/Wall, newest first.
    static func allWritings() -> [URL] {
        guard let dir = FileManager.wallDocuments else { return [] }
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
    }

    /// The most recent .md in Documents/Wall, or nil if none exist yet.
    static func mostRecentWriting() -> URL? { allWritings().first }

    /// Move a writing to the Trash (recoverable — never a hard delete). Returns
    /// true on success.
    @discardableResult
    static func trash(_ url: URL) -> Bool {
        (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }

    /// Read a writing file, or empty string on failure.
    static func contents(of url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
