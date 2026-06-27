import SwiftUI
import AppKit

/// Where finished writing is saved. Defaults to ~/Documents/Wall, but the user
/// can repoint it at any folder — e.g. a Dropbox/iCloud Drive folder to back up
/// or sync across Macs. Wall is non-sandboxed, so an arbitrary user-chosen path
/// works directly (no security-scoped bookmarks needed).
///
/// Only *writing* lives here. In-progress session state (session.json) stays in
/// Application Support — you don't want scratch state syncing.
enum Storage {
    private static let key = "writingsDirectoryPath"

    static var directoryURL: URL {
        let url: URL
        if let path = UserDefaults.standard.string(forKey: key), !path.isEmpty {
            url = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            url = defaultDirectory
        }
        ensure(url)
        return url
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Wall", isDirectory: true)
    }

    static var isDefault: Bool {
        let path = UserDefaults.standard.string(forKey: key)
        return path == nil || path?.isEmpty == true || path == defaultDirectory.path
    }

    static func setDirectory(_ url: URL) {
        ensure(url)
        UserDefaults.standard.set(url.path, forKey: key)
        NotificationCenter.default.post(name: .wallStorageChanged, object: nil)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: .wallStorageChanged, object: nil)
    }

    private static func ensure(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Count of .md writings in a folder — used to size the "move existing?" prompt.
    static func writingCount(in dir: URL) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension == "md" }.count
    }

    /// Move every .md writing from `old` to `new`, never clobbering an existing
    /// destination. Returns how many moved.
    @discardableResult
    static func moveWritings(from old: URL, to new: URL) -> Int {
        guard old != new else { return 0 }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: old, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var moved = 0
        for file in files where file.pathExtension == "md" {
            let dest = uniqueDestination(new.appendingPathComponent(file.lastPathComponent))
            if (try? FileManager.default.moveItem(at: file, to: dest)) != nil { moved += 1 }
        }
        return moved
    }

    /// If `url` is taken, append -1, -2, … before the extension.
    static func uniqueDestination(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 1
        while true {
            let candidate = dir.appendingPathComponent("\(base)-\(n).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}

extension Notification.Name {
    static let wallStorageChanged = Notification.Name("WallStorageChanged")
}
