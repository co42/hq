import HQKit
import SwiftUI

/// Everything that blocks a task, in its window under the project and tags (2026-11-24, T-760): when it's Blocked, the
/// reason in red, edited in place, and × to unblock; a chip per task it's blocked by, × takes it off; Block… and Blocked By….
/// A done task has none: Done clears Blocked.
struct TaskBlockers: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @State private var reason = ""
    @State private var picking: HoldPicker.Kind?
    @FocusState private var typing: Bool

    var body: some View {
        if let task = model.task(id), task.status != .done {
            VStack(alignment: .leading, spacing: Space.sm) {
                if task.blocked { reasonLine(task) }
                if !task.blockedBy.isEmpty {
                    FlowLayout(spacing: Space.sm) {
                        ForEach(task.blockedBy, id: \.self) { other in chip(other) }
                    }
                }
                HStack(spacing: Space.md) {
                    if !task.blocked { action("Block…", .block, help: "It can't be done now, with a reason or not (B on its card)") }
                    action("Blocked By…", .blockedBy, help: "A task it can't go on without")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .popover(item: $picking, arrowEdge: .bottom) { kind in HoldPicker(task: id, kind: kind) { picking = nil }.environment(model) }
            .onChange(of: model.reasonFocus) { takeFocus() }
            .onInWindow { takeFocus() }
            .uiTestAnchor("blocked-row")
        }
    }

    /// The mark, the reason as a field in red (empty: the placeholder says there's none), × to unblock.
    private func reasonLine(_ task: TaskItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            KitIcon.blocked.image.foregroundStyle(Ink.blockedText)
            TextField("Blocked, no reason given", text: $reason, axis: .vertical) // lint: ok a reason wraps; it is not markdown
                .textFieldStyle(.plain)
                .foregroundStyle(Ink.blockedText)
                .lineLimit(1...4)
                .focused($typing)
                .onSubmit { save() }
                .onExitCommand {
                    reason = task.blockedReason ?? ""
                    typing = false
                }
                .onChange(of: typing) { if !typing { save() } }
                .onAppear { reason = task.blockedReason ?? "" }
                .onChange(of: task.blockedReason) { if !typing { reason = task.blockedReason ?? "" } }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Why it can't be done now: click to change it")
                .accessibilityLabel("Blocked reason")
                .uiTestAnchor("blocked-reason")
            Button("Unblock", icon: .close) { model.unblock(id) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .frame(width: Metric.rowAction, height: Metric.rowAction)
                .hoverPlate(.chip)
                .help("Unblock: it can be done again (B on its card)")
                .uiTestAnchor("blocked-unblock")
        }
        .kitType(.callout)
    }

    @ViewBuilder
    private func chip(_ other: Int) -> some View {
        let blocker = model.task(other)
        BlockerChip(key: blocker?.key ?? "T-\(other)", title: blocker.map { $0.title.isEmpty ? "New task" : $0.title } ?? "deleted",
                    done: blocker.map { $0.status == .done } ?? true,
                    open: { if blocker != nil { model.open(.task(other), push: true) } },
                    remove: { model.removeLink(id, .blockedBy, other) })
            .uiTestAnchor("blocker:\(other)")
    }

    private func action(_ title: String, _ kind: HoldPicker.Kind, help: String) -> some View {
        Button(title) { picking = kind }
            .buttonStyle(.plain)
            .kitType(.callout)
            .foregroundStyle(.secondary)
            .hoverPlate(.chip)
            .help(help)
            .uiTestAnchor("blocked-add:\(title)")
    }

    private func save() {
        model.setBlockedReason(id, reason)
        reason = model.task(id)?.blockedReason ?? ""
    }

    /// Edit Reason… from the window's ⋯ or the menu bar.
    private func takeFocus() {
        guard model.reasonFocus == id else { return }
        model.reasonFocus = nil
        typing = true
    }
}
