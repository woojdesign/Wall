import Foundation
import SwiftUI

enum CountMode: String, Codable, CaseIterable {
    case words, characters
    var label: String { self == .words ? "words" : "characters" }
}

struct WallSettings: Codable, Equatable {
    var durationMinutes: Int = 20
    var wordTarget: Int = 1250
    var countMode: CountMode = .words
    /// When true, the session runs without touching pf — the writing
    /// container is still real (gates, timer, autosave), but background
    /// network work (e.g., agents) is preserved. Reset every session.
    var keepOnline: Bool = false
}

enum SessionPhase {
    case idle, active, complete
}

@MainActor
final class SessionModel: ObservableObject {
    @Published var phase: SessionPhase = .idle
    @Published var settings = WallSettings()
    @Published var text: String = ""
    @Published private(set) var now: Date = .now
    @Published private(set) var startDate: Date?

    /// Both gates met: the wall has come down, but the session stays open so
    /// you can keep writing if you're on a roll. Leaving is now your call
    /// (`finish()`), not an automatic cut the instant the counter ticks over.
    @Published private(set) var released = false

    private var timer: Timer?
    private let blocker: InternetBlocker
    private let store = SessionStore()
    private var autosaveURL: URL?

    init(blocker: InternetBlocker) {
        self.blocker = blocker
        if let saved = store.load() {
            settings = saved.settings
            text = saved.text
            startDate = saved.startDate
            autosaveURL = saved.autosaveURL
            phase = .active
            startTimer()
            // Reconcile gates immediately: a restored session that already
            // cleared both should come up released (wall down), not flash the
            // gate UI for a tick before catching up.
            tick()
        }
    }

    // MARK: Derived state

    var elapsed: TimeInterval { startDate.map { now.timeIntervalSince($0) } ?? 0 }
    var totalDuration: TimeInterval { Double(settings.durationMinutes) * 60 }
    var timeRemaining: TimeInterval { max(0, totalDuration - elapsed) }
    var timeGateMet: Bool { elapsed >= totalDuration }

    var count: Int {
        switch settings.countMode {
        case .words: return text.split(whereSeparator: { $0.isWhitespace }).count
        case .characters: return text.count
        }
    }
    var wordsRemaining: Int { max(0, settings.wordTarget - count) }
    var wordGateMet: Bool { count >= settings.wordTarget }
    var bothGatesMet: Bool { timeGateMet && wordGateMet }

    var timeProgress: Double { totalDuration > 0 ? min(1, elapsed / totalDuration) : 1 }
    var wordProgress: Double { settings.wordTarget > 0 ? min(1, Double(count) / Double(settings.wordTarget)) : 1 }

    /// Overall progress is the lagging gate — both must complete.
    var progress: Double { min(timeProgress, wordProgress) }

    // MARK: Lifecycle

    func begin() {
        let start = Date.now
        startDate = start
        now = start
        released = false
        phase = .active
        if let dir = FileManager.wallDocuments {
            autosaveURL = dir.appendingPathComponent("\(Self.fileStamp.string(from: start)).md")
        }
        persist()
        startTimer()
        if settings.keepOnline { return }
        // Dead-man's-switch ceiling well past any reasonable session.
        let ceiling = Int(totalDuration) + 6 * 3600
        Task { [blocker] in try? await blocker.block(maxSeconds: ceiling) }
    }

    func textChanged() {
        persist()
        autosave()
    }

    func startNewSession() {
        text = ""
        startDate = nil
        autosaveURL = nil
        released = false
        settings.keepOnline = false
        phase = .idle
    }

    /// Both gates cleared. Bring the wall down — you've served it — but stay
    /// in the writing surface. The session ends only when *you* say so
    /// (`finish()`). Idempotent: safe to call again on a restored session.
    private func release() {
        guard !released else { return }
        released = true
        autosave()
        // Online sessions armed nothing, so there's nothing to unblock (and
        // an unblock call would needlessly prompt for admin).
        if settings.keepOnline { return }
        Task { [blocker] in try? await blocker.unblock() }
    }

    /// User-invoked: leave the writing surface for the done screen. Only
    /// offered once `released`, so the wall is already down — no unblock here.
    func finish() {
        phase = .complete
        timer?.invalidate(); timer = nil
        autosave()
        store.clear()
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        now = .now
        if phase == .active && bothGatesMet { release() }
    }

    private func persist() {
        guard phase == .active, let startDate else { return }
        store.save(PersistedSession(settings: settings, text: text, startDate: startDate, autosaveURL: autosaveURL))
    }

    private func autosave() {
        guard let url = autosaveURL else { return }
        // Don't litter Documents/Wall with empty files for sessions where
        // nothing was written (the archive also hides these, but better not to
        // create them at all).
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()
}

// MARK: - Persistence

struct PersistedSession: Codable {
    var settings: WallSettings
    var text: String
    var startDate: Date
    var autosaveURL: URL?
}

struct SessionStore {
    private var url: URL? { FileManager.wallSupport?.appendingPathComponent("session.json") }

    func load() -> PersistedSession? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedSession.self, from: data)
    }
    func save(_ s: PersistedSession) {
        guard let url, let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: url)
    }
    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension FileManager {
    static var wallSupport: URL? { dir(in: .applicationSupportDirectory) }
    /// The configured writing folder (default ~/Documents/Wall). See Storage.
    static var wallDocuments: URL? { Storage.directoryURL }

    private static func dir(in domain: FileManager.SearchPathDirectory) -> URL? {
        guard let base = FileManager.default.urls(for: domain, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Wall", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
