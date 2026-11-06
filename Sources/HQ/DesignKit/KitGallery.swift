import HQKit
import SwiftUI

/// Every part in every state, for review from snapshots:
///   APP_KIT_GALLERY=1 HQ        the parts
///   APP_KIT_GALLERY=faces HQ    120 faces at 16, 22, 40 and 72 pt
struct KitGallery: View {
    static let mode = ProcessInfo.processInfo.environment["APP_KIT_GALLERY"]
    static let enabled = mode != nil && mode != ""
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if Self.mode == "faces" { FaceGallery() } else { parts }
        }
        .background(Ink.content)
    }

    private var parts: some View {
        let now = Date.now
        let sessions = model.sessions.isEmpty ? Self.sampleSessions(now) : model.sessions
        return VStack(alignment: .leading, spacing: Space.xxl) {
            section("Task glyphs, type icons") {
                HStack(spacing: Space.lg) {
                    ForEach(TaskStatus.allCases) { status in
                        VStack { TaskGlyph(status: status); caption(status.title) }
                    }
                }
            }
            section("Session glyphs") {
                HStack(spacing: Space.lg) {
                    ForEach(SessionGlyphKind.allCases) { kind in
                        VStack { SessionGlyph(kind: kind); caption(kind.rawValue) }
                    }
                }
            }
            section("Session cards: every state, hover, selected, drop target") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(360), spacing: Metric.cardGap), count: 3), alignment: .leading, spacing: Metric.cardGap) {
                    ForEach(sessions.prefix(9)) { session in
                        SessionCard(session: session, now: now)
                    }
                    SessionCard(session: sessions[0], now: now).environment(\.forcedPartState, .hover)
                    SessionCard(session: sessions[0], now: now, selected: true)
                    SessionCard(session: sessions[0], now: now, dropTarget: true)
                }
            }
            section("Tags, pills, chips") {
                HStack(spacing: Space.sm) {
                    AttentionTag(text: "Review: PR #418 is ready to merge", tone: .needsYou)
                    AttentionTag(text: "2 new", tone: .new)
                    Chip(text: "Registry", icon: .project)
                    Chip(text: "#perf")
                    KeyLabel(key: "T-13")
                    AttentionDot(needsYou: true, isNew: false)
                    AttentionDot(needsYou: false, isNew: true)
                }
            }
            section("Face stacks") {
                HStack(spacing: Space.xl) {
                    FaceStack(sessions: [])
                    FaceStack(sessions: Array(sessions.prefix(1)))
                    FaceStack(sessions: Array(sessions.prefix(3)))
                    FaceStack(sessions: Array(sessions.prefix(5)))
                }
            }
            section("Pull request rows") {
                if let github = model.github {
                    PRGroup(title: "Waiting for your review", items: github.items.filter(\.reviewRequested), total: 3, empty: "Nothing waits.")
                        .frame(width: 600)
                    PRGroup(title: "Yours", items: github.items.filter { $0.mine && !$0.reviewRequested }, total: 4, empty: "No PRs.")
                        .frame(width: 600)
                    PRGroup(title: "Empty", items: [], total: 0, empty: "Nothing waits for your review.")
                        .frame(width: 600)
                }
            }
            section("Outline rows: statuses, types, faces, tags, review, new, project, progress, a description") {
                if !model.tasks.isEmpty {
                    TaskOutline(width: 1200).frame(width: 1200)
                }
            }
            section("Output chips") {
                if let task = model.tasks.first(where: { !model.outputs(ofTask: $0.id).isEmpty }) {
                    FlowChips(routes: model.outputs(ofTask: task.id)).frame(width: 600, alignment: .leading)
                }
            }
            section("Banner, empty section") {
                InlineBanner(message: Problem.ghosttyAccess.message, detail: Problem.ghosttyAccess.detail, actionTitle: "Open Settings…") {}
                    .frame(width: 600)
                EmptySection(title: "No Sessions", message: "Sessions you start with the hq plugin show up here.") {
                    Button("New Session…") {}
                }
                .frame(width: 600)
            }
            section("Code") {
                CodeBlock(text: "kubectl rollout restart deploy/registry-api", copies: true).frame(width: 480)
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(title).kitType(.section)
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).kitType(.secondary).foregroundStyle(.secondary)
    }

    static func sampleSessions(_ now: Date) -> [SessionItem] {
        let states: [SessionState] = [.waiting(.question), .waiting(.plan), .waiting(.permission), .failed, .working, .done, .idle, .compacting, .ended]
        return states.enumerated().map { index, state in
            var item = SessionItem(id: "gallery-\(index)", customName: "Session \(index + 1)",
                                   status: SessionStatus(state: state, unread: state == .done, since: now.addingTimeInterval(Double(-index * 300))),
                                   cwd: "~/code/registry", repo: "registry", branch: "retry-budget", started: now)
            item.question = "Per-identity credentials or one shared identity?"
            item.tool = "Bash"
            item.toolInput = "kubectl rollout restart deploy/api"
            item.error = "API error 529"
            return item
        }
    }
}

/// 120 faces at every size used, so every part is judged small and large.
private struct FaceGallery: View {
    private let ids = (0..<120).map { String(format: "%08x-5eed-4000-8000-%012x", $0 * 2_654_435_761 % 0xFFFF_FFFF, $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ForEach([16, 22, 40, 72] as [CGFloat], id: \.self) { size in
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("\(Int(size)) pt").kitType(.section)
                    let columns = size >= 72 ? 15 : size >= 40 ? 24 : 40
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(size), spacing: size >= 40 ? Space.md : Space.sm), count: columns),
                              alignment: .leading, spacing: size >= 40 ? Space.md : Space.sm) {
                        ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                            SessionFace(spec: FaceSpec(id: id), size: size,
                                        badge: index % 17 == 3 ? .needsYou : index % 29 == 5 ? .failed : nil,
                                        ended: index % 23 == 7, label: id)
                        }
                    }
                }
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
