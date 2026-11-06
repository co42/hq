import SwiftUI

/// First launch: the three things HQ needs, each with a live status and one button.
/// It closes itself once all three are ready.
struct SetupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Set Up HQ").kitType(.section)
                Text("HQ needs three things to follow your Claude sessions, and GitHub for your pull requests.")
                    .kitType(.callout)
                    .foregroundStyle(.secondary)
            }
            .gridProbe("title", area: "setup")

            VStack(spacing: 0) {
                row(icon: .plugin, title: "Claude plugin",
                    detail: model.setup.pluginInstalled ? "Installed for every session" : model.pluginError ?? "Reports each session’s state to HQ, and teaches Claude the hq command",
                    ok: model.setup.pluginInstalled, action: model.pluginInstalling ? "Installing…" : "Install") { model.installPlugin() }
                Divider().padding(.leading, Space.section + Space.md)
                row(icon: .ghostty, title: "Ghostty access",
                    detail: model.setup.ghosttyAllowed ? "Allowed" : "Lets HQ focus a session’s terminal. macOS asks once.",
                    ok: model.setup.ghosttyAllowed, action: "Allow…") { model.allowGhostty() }
                Divider().padding(.leading, Space.section + Space.md)
                row(icon: .vault, title: "Obsidian vault",
                    detail: model.setup.vaultName.map { "Found \($0)" } ?? "Not found at the default path",
                    ok: model.setup.vaultPath != nil, action: "Choose…") { model.chooseVault() }
                Divider().padding(.leading, Space.section + Space.md)
                row(icon: .pullRequest, title: "GitHub (optional)",
                    detail: model.setup.githubAccount.map { "Signed in as \($0) with gh" } ?? (model.setup.ghPath == nil ? "Install gh, then run gh auth login" : "Run gh auth login in a terminal"),
                    ok: model.setup.githubAccount != nil, action: "Copy Command") { Pasteboard.copy("gh auth login") }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .gridProbe("rows", area: "setup")

            HStack {
                Spacer()
                Button(model.setup.isComplete ? "Done" : "Later") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .gridProbe("buttons", area: "setup")
        }
        .padding(Space.margin)
        .gridArea("setup")
        .frame(width: Metric.sheetWidth)
        .noInitialFocus()
        .onChange(of: model.setup.isComplete) { if model.setup.isComplete { dismiss() } }
        // Grants happen in System Settings and nothing calls back: check every 2 s while open.
        .task {
            guard !Store.isOverridden else { return }
            while !Task.isCancelled {
                model.checkSetup()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func row(icon: KitIcon, title: String, detail: String, ok: Bool, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: Space.md) {
            icon.image
                .font(KitType.section.font)
                .foregroundStyle(.secondary)
                .frame(width: Space.section)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metric.lineGap) {
                Text(title).kitType(.titleStrong)
                Text(detail)
                    .kitType(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Space.sm)
            if ok {
                HStack(spacing: Space.xs) {
                    KitIcon.checkPassed.image.foregroundStyle(Ink.done).accessibilityHidden(true)
                    Text("Ready")
                }
                .kitType(.callout)
            } else {
                Button(action, action: perform).disabled(model.pluginInstalling && title == "Claude plugin")
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.md)
    }
}
