import HQKit
import SwiftUI

/// Model and Effort, two pop-ups with Claude Code's own first, by name ("Opus", "High"): Start a Session's and a role's
/// (T-446).
struct ModelPickers: View {
    let model: String?
    let effort: String?
    let anchor: String
    let set: (_ model: String?, _ effort: String?) -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let own = app.claudeDefaults
        let ownModel = own.model.map(ClaudeModel.family)
        // A pick that is Claude Code's own shows as its first item.
        let shownModel = model.flatMap { ClaudeModel.family($0) == ownModel ? nil : $0 }
        let shownEffort = effort.flatMap { $0 == own.effort ? nil : $0 }
        HStack(spacing: Space.sm) {
            Picker("Model", selection: Binding(get: { shownModel ?? "" }, set: { set($0.isEmpty ? nil : $0, effort) })) {
                Text(ownModel ?? "Default Model").tag("")
                Divider()
                ForEach(models(but: ownModel), id: \.self) { Text(ClaudeModel.family($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .clickable()
            .help("The model it starts on; the first: Claude Code’s own")
            .uiTestAnchor("\(anchor)-model")
            .background(Self.shows("\(anchor)-model", shownModel.map(ClaudeModel.family) ?? ownModel ?? "Default"))
            Picker("Effort", selection: Binding(get: { shownEffort ?? "" }, set: { set(model, $0.isEmpty ? nil : $0) })) {
                Text(own.effort.map(ClaudeModel.effortTitle) ?? "Default Effort").tag("")
                Divider()
                ForEach(ClaudeModel.efforts.filter { $0 != own.effort }, id: \.self) { Text(ClaudeModel.effortTitle($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .clickable()
            .help("How hard it thinks; the first: Claude Code’s own")
            .uiTestAnchor("\(anchor)-effort")
            .background(Self.shows("\(anchor)-effort", shownEffort.map(ClaudeModel.effortTitle) ?? own.effort.map(ClaudeModel.effortTitle) ?? "Default"))
        }
    }

    /// The aliases, and a full name a role or a session already has, without Claude Code's own.
    private func models(but own: String?) -> [String] {
        (ClaudeModel.aliases + (model.map { ClaudeModel.aliases.contains($0) ? [] : [$0] } ?? [])).filter { ClaudeModel.family($0) != own }
    }

    /// What a pop-up shows, as an anchor of its own for the UI checks.
    private static func shows(_ anchor: String, _ value: String) -> some View {
        Color.clear.uiTestAnchor("\(anchor)=\(value)").id(value)
    }
}

extension SessionItem {
    /// "Opus VH · 442k" on a card: its model's family, its effort short, its context in k; nil before its first reply.
    var modelLine: String? {
        let parts = [model.map(ClaudeModel.family), effort.map(ClaudeModel.shortEffort)].compactMap(\.self).joined(separator: " ")
        let line = [parts.isEmpty ? nil : parts, contextTokens.map(ClaudeModel.shortTokens)].compactMap(\.self).joined(separator: " · ")
        return line.isEmpty ? nil : line
    }

    /// The same in full, for its tooltip: "claude-opus-5-5, effort Very High, 441,898 tokens in its context".
    var modelHelp: String? {
        let parts = [model, effort.map { "effort \(ClaudeModel.effortTitle($0))" },
                     contextTokens.map { "\($0.formatted()) tokens in its context" }].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Model ▸ and Effort ▸ for a running session, the current one checked: they type /model or /effort in its terminal while
/// it waits for its next message (T-446).
struct RunMenus: View {
    let session: SessionItem
    @Environment(AppModel.self) private var model

    var body: some View {
        let ready = model.canChangeRun(session)
        Picker("Model", selection: Binding(get: { session.model.map { ClaudeModel.family($0).lowercased() } ?? "" },
                                          set: { model.changeRun(session.id, model: $0) })) {
            ForEach(ClaudeModel.aliases, id: \.self) { Text(ClaudeModel.family($0)).tag($0) }
        }
        .disabled(!ready)
        Picker("Effort", selection: Binding(get: { session.effort ?? "" }, set: { model.changeRun(session.id, effort: $0) })) {
            ForEach(ClaudeModel.efforts, id: \.self) { Text(ClaudeModel.effortTitle($0)).tag($0) }
        }
        .disabled(!ready)
    }
}
