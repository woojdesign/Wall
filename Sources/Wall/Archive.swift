import SwiftUI
import AppKit
import WoojTokens

// A quiet, read-only library of finished writing. Not an editor, not a file
// manager — somewhere to revisit and retrieve what you've already put down.
// Entries are the .md files in ~/Documents/Wall; the files are the store.

struct Entry: Identifiable, Equatable {
    let url: URL
    let date: Date
    let text: String
    var id: URL { url }

    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace }).count }

    /// First non-empty line, for the list preview.
    var preview: String {
        for line in text.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return "Empty"
    }

    /// Filenames are stamped `yyyy-MM-dd-HHmm` (see SessionModel.fileStamp);
    /// fall back to the file's modification date if that ever fails to parse.
    static func load(_ url: URL) -> Entry {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let stamp = url.deletingPathExtension().lastPathComponent
        let date = filenameFormatter.date(from: stamp)
            ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        return Entry(url: url, date: date, text: text)
    }

    static let filenameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()
}

/// Relative date buckets for the sidebar, in newest-first order. Pure so it's
/// unit-testable (inject `now`/`calendar`).
enum EntryGrouping {
    static func bucketTitle(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return "This Week"
        }
        return date.formatted(.dateTime.month(.wide).year())
    }

    /// Groups already-sorted (newest-first) entries, preserving order and not
    /// re-emitting a bucket header once it's been seen.
    static func grouped(_ entries: [Entry], now: Date, calendar: Calendar = .current)
        -> [(title: String, entries: [Entry])] {
        var out: [(String, [Entry])] = []
        for e in entries {
            let title = bucketTitle(for: e.date, now: now, calendar: calendar)
            if out.last?.0 == title { out[out.count - 1].1.append(e) }
            else { out.append((title, [e])) }
        }
        return out.map { (title: $0.0, entries: $0.1) }
    }
}

@MainActor
final class ArchiveModel: ObservableObject {
    @Published private(set) var entries: [Entry] = []
    @Published var selection: Entry.ID?
    @Published var query: String = ""

    func reload() {
        // Skip empty/whitespace-only files — an abandoned session that never
        // got any words isn't worth showing.
        entries = WallActions.allWritings()
            .map(Entry.load)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if selection == nil || !entries.contains(where: { $0.id == selection }) {
            selection = filtered.first?.id
        }
    }

    var filtered: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return entries }
        return entries.filter { $0.text.lowercased().contains(q) }
    }

    var selected: Entry? { entries.first { $0.id == selection } }

    func delete(_ entry: Entry) {
        WallActions.trash(entry.url)
        if selection == entry.id { selection = nil }
        reload()
    }
}

struct ArchiveView: View {
    @StateObject private var model = ArchiveModel()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 300)
            Rectangle().fill(Palette.line).frame(width: 1)
            reader.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
        .task { model.reload() }
        // Catch sessions finished while the window sat open.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in model.reload() }
        // And reflect a changed writing folder immediately.
        .onReceive(NotificationCenter.default.publisher(for: .wallStorageChanged)) { _ in
            model.reload()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Back to the editor — lives here (top-leading) so it never collides
            // with the reader's Copy/Reveal/Delete actions on the right. ⌘L
            // toggles the same thing.
            HStack(spacing: WoojSpace.xs) {
                Button {
                    Navigation.shared.tab = .write
                } label: {
                    HStack(spacing: WoojSpace.xxs) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("Write")
                    }
                    .font(WoojType.label.font)
                    .foregroundStyle(Palette.clay)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, WoojSpace.sm)
            .padding(.top, WoojSpace.sm)

            searchField
                .padding(WoojSpace.sm)
            Rectangle().fill(Palette.line).frame(height: 1)

            if model.entries.isEmpty {
                emptyState("Nothing written yet.")
            } else if model.filtered.isEmpty {
                emptyState("No matches.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(EntryGrouping.grouped(model.filtered, now: .now), id: \.title) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    EntryRow(entry: entry, selected: entry.id == model.selection)
                                        .contentShape(Rectangle())
                                        .onTapGesture { model.selection = entry.id }
                                }
                            } header: {
                                Text(group.title)
                                    .wallLabel()
                                    .padding(.horizontal, WoojSpace.md)
                                    .padding(.vertical, WoojSpace.xs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Palette.ground)
                            }
                        }
                    }
                }
            }
        }
        .background(Palette.surface.opacity(0.4))
    }

    private var searchField: some View {
        HStack(spacing: WoojSpace.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Palette.tertiary)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(WoojType.body.font)
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, WoojSpace.sm)
        .padding(.vertical, WoojSpace.xs)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().stroke(Palette.line, lineWidth: 1))
    }

    private func emptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(WoojType.body.font)
                .foregroundStyle(Palette.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Reader

    @ViewBuilder
    private var reader: some View {
        if let entry = model.selected {
            EntryReader(entry: entry) { model.delete(entry) }
                .id(entry.id)   // reset scroll when switching entries
        } else {
            emptyState(model.entries.isEmpty ? "" : "Select an entry.")
        }
    }
}

private struct EntryRow: View {
    let entry: Entry
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WoojSpace.xxs) {
            HStack {
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(WoojType.label.font)
                    .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                Spacer()
                Text("\(entry.wordCount)")
                    .font(WoojType.mono.font)
                    .monospacedDigit()
                    .foregroundStyle(Palette.tertiary)
            }
            Text(entry.preview)
                .font(.custom("Charter", fixedSize: WoojType.body.size))
                .foregroundStyle(selected ? Palette.reading : Palette.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, WoojSpace.md)
        .padding(.vertical, WoojSpace.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Palette.surface : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1).opacity(0.5)
        }
    }
}

private struct EntryReader: View {
    let entry: Entry
    let onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: full date + count, then the quiet actions.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: WoojSpace.xxs) {
                    Text(entry.date.formatted(.dateTime.weekday(.wide).month().day().hour().minute()))
                        .font(WoojType.heading.font)
                        .foregroundStyle(Palette.ink)
                    Text("\(entry.wordCount) words")
                        .font(WoojType.mono.font)
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiary)
                }
                Spacer()
                HStack(spacing: WoojSpace.md) {
                    CopyLink(title: "Copy", text: { entry.text })
                    Button("Reveal") { WallActions.revealInFinder(entry.url) }
                        .buttonStyle(.plain)
                        .font(WoojType.label.font)
                        .foregroundStyle(Palette.tertiary)
                    Button("Delete") { confirmingDelete = true }
                        .buttonStyle(.plain)
                        .font(WoojType.label.font)
                        .foregroundStyle(Palette.clay)
                }
            }
            .padding(WoojSpace.lg)
            Rectangle().fill(Palette.line).frame(height: 1)

            ScrollView {
                Text(entry.text.isEmpty ? "Empty" : entry.text)
                    .wallBody()
                    .textSelection(.enabled)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(WoojSpace.xl)
            }
        }
        .confirmationDialog(
            "Move this writing to the Trash?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can recover it from the Trash.")
        }
    }
}

/// Which view the main window is showing. The Archive lives *inside* the editor
/// window now (a tab), not a separate window.
enum MainTab { case write, archive }

@MainActor
final class Navigation: ObservableObject {
    static let shared = Navigation()
    @Published var tab: MainTab = .write

    /// Flip between editor and Archive — the ⌘L behavior. (Was one-way once;
    /// `NavigationTests` guards against that regressing.)
    func toggleArchive() { tab = (tab == .archive) ? .write : .archive }
}

/// "Archive" menu item (⌘L) — toggles the main window between the editor and
/// the Archive, bringing it forward.
struct ArchiveCommand: View {
    @ObservedObject private var nav = Navigation.shared
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(nav.tab == .archive ? "Show Editor" : "Show Archive") {
            openWindow(id: "wall")
            nav.toggleArchive()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("l", modifiers: .command)
    }
}
