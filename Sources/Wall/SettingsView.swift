import SwiftUI
import AppKit
import WoojTokens

/// Preferences (⌘,). One pane for now: where writing is saved.
struct SettingsView: View {
    @State private var path = Storage.directoryURL.path
    @AppStorage("immersiveSessions") private var immersive = true
    @AppStorage("immersionClock") private var immersionClock = true
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: WoojSpace.lg) {
            VStack(alignment: .leading, spacing: WoojSpace.xs) {
                Text("Appearance").wallLabel()
                Picker("", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 280)
            }

            Divider()

            VStack(alignment: .leading, spacing: WoojSpace.xs) {
                Text("Sessions").wallLabel()
                Toggle(isOn: $immersive) {
                    Text("Full-screen while writing")
                        .font(WoojType.body.font)
                        .foregroundStyle(Palette.ink)
                }
                .toggleStyle(.switch)
                .tint(Palette.clay)
                Text("When a session begins, Wall takes the whole screen and hides the menu bar — the wall, but for your screen too.")
                    .font(WoojType.body.font)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $immersionClock) {
                    Text("Show a quiet clock in full-screen")
                        .font(WoojType.body.font)
                        .foregroundStyle(Palette.ink)
                }
                .toggleStyle(.switch)
                .tint(Palette.clay)
                .disabled(!immersive)
                .opacity(immersive ? 1 : 0.5)
                Text("A small analog clock in the corner — the menu bar's clock is hidden in full-screen, so this hands the time back without breaking flow.")
                    .font(WoojType.body.font)
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Writing folder").wallLabel()

            Text("New writing is saved here. Point it at a synced folder — Dropbox, iCloud Drive — to back it up or keep it across Macs.")
                .font(WoojType.body.font)
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Current path, middle-truncated so the meaningful tail stays visible.
            Text(path)
                .font(WoojType.mono.font)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(WoojSpace.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))

            HStack(spacing: WoojSpace.md) {
                Button("Change…") { chooseFolder() }
                Button("Reveal") { WallActions.revealInFinder(Storage.directoryURL) }
                    .buttonStyle(.plain)
                    .font(WoojType.label.font)
                    .foregroundStyle(Palette.tertiary)
                Spacer()
                if !Storage.isDefault {
                    Button("Use Default") { resetToDefault() }
                        .buttonStyle(.plain)
                        .font(WoojType.label.font)
                        .foregroundStyle(Palette.tertiary)
                }
            }
        }
        .padding(WoojSpace.xl)
        .frame(width: 460)
        .background(Palette.ground)
    }

    private func chooseFolder() {
        let old = Storage.directoryURL

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder for your Wall writing."
        panel.directoryURL = old
        guard panel.runModal() == .OK, let chosen = panel.url, chosen != old else { return }

        // Offer to bring existing writing along so the Archive stays continuous.
        let count = Storage.writingCount(in: old)
        if count > 0 {
            let alert = NSAlert()
            alert.messageText = "Move \(count) existing \(count == 1 ? "entry" : "entries") to the new folder?"
            alert.informativeText = "They'll move from \(old.lastPathComponent) to \(chosen.lastPathComponent). Leaving them keeps them where they are — the Archive will only show the new folder."
            alert.addButton(withTitle: "Move")
            alert.addButton(withTitle: "Leave Them")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertThirdButtonReturn: return                       // Cancel
            case .alertFirstButtonReturn: Storage.moveWritings(from: old, to: chosen)
            default: break                                             // Leave Them
            }
        }

        Storage.setDirectory(chosen)
        path = chosen.path
    }

    private func resetToDefault() {
        let old = Storage.directoryURL
        let def = Storage.defaultDirectory
        guard old != def else { return }
        let count = Storage.writingCount(in: old)
        if count > 0 {
            let alert = NSAlert()
            alert.messageText = "Move \(count) \(count == 1 ? "entry" : "entries") back to the default folder?"
            alert.addButton(withTitle: "Move")
            alert.addButton(withTitle: "Leave Them")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertThirdButtonReturn: return
            case .alertFirstButtonReturn: Storage.moveWritings(from: old, to: def)
            default: break
            }
        }
        Storage.resetToDefault()
        path = Storage.directoryURL.path
    }
}
