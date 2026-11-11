import AppKit
import HQKit
import SwiftUI

/// Block… takes an optional reason; Blocked By… and After… a task, by key or words, the story's own tasks first.
struct HoldPicker: View {
    enum Kind: Identifiable {
        case block, blockedBy, after
        var id: Self { self }
    }

    let task: Int
    let kind: Kind
    let done: () -> Void
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(heading).kitType(.groupLabel).foregroundStyle(.secondary)
            if kind == .block {
                TextField("Why (optional)", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .uiTestAnchor("hold-reason")
                    .onSubmit(block)
                HStack {
                    Text("It holds until you or a session unblocks it.").kitType(.meta).foregroundStyle(.secondary)
                    Spacer(minLength: Space.sm)
                    Button("Block", action: block).keyboardShortcut(.defaultAction)
                }
            } else {
                let matches = Array(Self.matches(model, task: task, kind: kind, query: query).prefix(LinkPicker.shown))
                TextField("Search a task, or type its key", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onChange(of: query) { index = 0 }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(matches.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .uiTestAnchor("hold-picker")
                    .onSubmit { if matches.indices.contains(index) { link(matches[index]) } }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element) { position, id in
                            Button { link(id) } label: {
                                HStack(spacing: Space.sm) {
                                    if let other = model.task(id) { TaskGlyph(status: other.status).frame(width: Metric.glyphSlot) }
                                    Text(model.task(id).map { "\($0.key) \($0.title)" } ?? "T-\(id)").kitType(.title).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, Space.sm)
                                .frame(height: Metric.boxRow)
                                .background(position == index ? Ink.rowSelection : Color.clear,
                                            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .clickable()
                            .onHover { if $0 { index = position } }
                            .uiTestAnchor("hold-match:T-\(id)")
                        }
                        if matches.isEmpty {
                            Text(query.isEmpty ? "No task to offer." : "No task matches “\(query)”.")
                                .kitType(.callout).foregroundStyle(.secondary).padding(Space.xs)
                        }
                    }
                }
                .frame(height: Metric.linkPicker)
                Text(kind == .after ? "Nothing moves: the arrow shows when one of the two is selected." : "It lets go on its own once that task is done.")
                    .kitType(.meta).foregroundStyle(.secondary)
            }
        }
        .padding(Space.md)
        .frame(width: Metric.sheetWidth)
        .onAppear { focused = true }
    }

    private var heading: String {
        let key = "T-\(task)"
        switch kind {
        case .block: return "Block \(key)"
        case .blockedBy: return "\(key) is blocked by…"
        case .after: return "\(key) comes after…"
        }
    }

    /// The tasks it can link to: by key or words when typed, else its story's open tasks, the one above first for After.
    static func matches(_ model: AppModel, task: Int, kind: Kind, query: String) -> [Int] {
        let link: TaskFlow.Link = kind == .after ? .after : .blockedBy
        let flow = model.taskFlow
        let tree = model.taskTree
        let text = query.trimmingCharacters(in: .whitespaces)
        let allowed = { (id: Int) in flow.refusal(task, link, id) == nil }
        if !text.isEmpty {
            var ids: [Int] = []
            if let key = TaskItem.key(text), model.task(key) != nil, text.uppercased().hasPrefix("T-") || Int(text) != nil { ids.append(key) }
            ids += model.tasks.filter { $0.status != .done }.sorted { $0.modified > $1.modified }
                .filter { "\($0.key) \($0.title)".localizedStandardContains(text) }.map(\.id)
            var seen = Set<Int>()
            return ids.filter { allowed($0) && seen.insert($0).inserted }
        }
        let story = tree.subtree(of: tree.root(of: task)).filter { id in id != task && model.task(id)?.status != .done && allowed(id) }
        guard kind == .after, let parent = tree.parent(of: task) else { return story }
        let siblings = tree.children(of: parent)
        guard let at = siblings.firstIndex(of: task), at > 0, story.contains(siblings[at - 1]) else { return story }
        return [siblings[at - 1]] + story.filter { $0 != siblings[at - 1] }
    }

    private func block() {
        model.block(task, reason: query)
        done()
    }

    private func link(_ other: Int) {
        model.addLink(task, kind == .after ? .after : .blockedBy, other)
        done()
    }
}

/// A top-level task's progress on its big card: its subtasks by state in a bar, then how many are done, doing and blocked;
/// ready, the rest, needs no mark (2026-11-11).
struct StorySummary: View {
    let id: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        let tally = model.taskFlow.tally(of: id)
        HStack(spacing: Space.md) {
            StoryBar(tally: tally).frame(width: Metric.storyBar, height: Metric.storyBarHeight)
            Text("\(Text("\(tally.done)").bold().foregroundStyle(.primary)) of \(Text("\(tally.total)").bold().foregroundStyle(.primary)) done")
                .foregroundStyle(.secondary)
                .font(KitType.callout.font)
                .monospacedDigit()
            if tally.doing > 0 { count(tally.doing, "doing", Ink.doing) }
            if tally.blocked > 0 { count(tally.blocked, "blocked", Ink.blocked) }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func count(_ number: Int, _ word: String, _ color: Color) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(color).frame(width: Space.sm, height: Space.sm)
            Text("\(number) \(word)")
        }
        .font(KitType.meta.font)
        .foregroundStyle(.secondary)
    }
}

/// A story's subtasks by state, as one bar: done, doing, blocked, then the rest.
struct StoryBar: View {
    let tally: TaskFlow.Tally

    var body: some View {
        GeometryReader { geometry in
            let total = max(CGFloat(tally.total), 1)
            HStack(spacing: 0) {
                Rectangle().fill(Ink.done).frame(width: geometry.size.width * CGFloat(tally.done) / total)
                Rectangle().fill(Ink.doing).frame(width: geometry.size.width * CGFloat(tally.doing) / total)
                Rectangle().fill(Ink.blocked).frame(width: geometry.size.width * CGFloat(tally.blocked) / total)
                Spacer(minLength: 0)
            }
        }
        .background(Ink.labelFill)
        .clipShape(Capsule())
    }
}

/// One choice of the drop menu: what it does when picked.
final class DropChoice: NSObject {
    let run: () -> Void

    init(_ run: @escaping () -> Void) {
        self.run = run
    }
}

extension ModalRoute {
    /// The task it opens, if it opens one.
    var taskID: Int? { if case .task(let id) = self { id } else { nil } }
}
