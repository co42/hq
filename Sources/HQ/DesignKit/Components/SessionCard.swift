import HQKit
import SwiftUI

/// One of a team's sessions under its top card, with its depth (1: a direct child) and its role.
struct TeamMember: Equatable, Identifiable {
    var session: SessionItem
    var depth: Int
    var role: RoleItem?
    var id: String { session.id }
}

/// What a session card shows (DESIGN.md §5): its session, and its team when it has one.
struct CardContent: Equatable {
    var session: SessionItem
    var role: RoleItem?
    /// Its sessions, depth first.
    var team: [TeamMember] = []
    /// Its team's rows show, inside the card.
    var open = false
    /// The selected session, when it is this card's or one of its rows'.
    var selected: String?
    /// The session a dragged item hovers: the card's own, or one of its rows'.
    var dropTarget: String?
    /// One of its sessions needs the user, who hasn't looked since.
    var blinking = false
    /// How many of its team's faces fit in its tray.
    var trayRoom = 6

    var everyone: [SessionItem] { [session] + team.map(\.session) }
}

/// A session on the grid (DESIGN.md §5): a raised card on one row: its face; its name over its role and its place; its
/// team's faces and their toggle; how long it has lasted over its state. It glows while one of its sessions needs the user
/// (red when one failed), breathing until the user looks. Open, its team's rows join the card under a rule.
struct SessionCard: View {
    let content: CardContent
    let now: Date
    /// Where its tray sits in the card: the card's AppKit view takes the clicks on its faces and its toggle.
    var tray: (CGRect) -> Void = { _ in }
    @Environment(\.forcedPartState) private var forced
    @State private var hovering = false

    /// The card's coordinate space, for where its tray sits.
    nonisolated static let space = "session-card"
    /// Drawn alone, as it drags: no glow.
    private var alone = false

    /// The card alone, as it drags (DESIGN.md §5): its surface, hairline and content, no ring, tint or glow.
    static func dragged(_ content: CardContent, now: Date) -> SessionCard {
        var plain = content
        plain.selected = nil
        plain.dropTarget = nil
        plain.blinking = false
        plain.open = false
        var card = SessionCard(plain, now: now)
        card.alone = true
        return card
    }

    /// One of a team's rows on a small card of its own, as it drags.
    static func draggedRow(_ member: TeamMember, now: Date) -> some View {
        TeamRow(member: member, now: now, selected: false, dropTarget: false)
            .surface(radius: Radius.row)
    }

    init(_ content: CardContent, now: Date, tray: @escaping (CGRect) -> Void = { _ in }) {
        self.content = content
        self.now = now
        self.tray = tray
    }

    /// In a tray at `frame` (the card's coordinates): each face shown and the toggle, where they sit.
    static func traySpots(_ content: CardContent, in frame: CGRect) -> (faces: [(id: String, rect: CGRect)], toggle: CGRect) {
        let side = Metric.faceTeam
        let y = frame.midY - side / 2
        let faces = content.open ? [] : trayFaces(content).shown.enumerated().map { index, member in
            (member.id, CGRect(x: frame.minX + CGFloat(index) * (side + Space.xs), y: y, width: side, height: side))
        }
        return (faces, CGRect(x: frame.maxX - Metric.teamToggle, y: frame.midY - Metric.teamToggle / 2, width: Metric.teamToggle, height: Metric.teamToggle))
    }

    /// A card with no team, as the gallery shows it.
    init(session: SessionItem, now: Date, selected: Bool = false, dropTarget: Bool = false, blinking: Bool = false) {
        self.init(CardContent(session: session, selected: selected ? session.id : nil, dropTarget: dropTarget ? session.id : nil,
                              blinking: blinking), now: now)
    }

    /// How many 26 pt faces fit in a team's tray on a card this wide, beside a name of at least `Metric.teamName`.
    static func trayRoom(_ width: CGFloat) -> Int {
        let fixed = Space.md * 2 + Metric.faceCard + Space.md * 3 + Metric.teamName + Metric.cardState + Metric.teamToggle
        return max(2, Int((width - fixed) / (Metric.faceTeam + Space.xs)))
    }

    /// An open card's height: its row, the rule, a row per session.
    static func openHeight(rows: Int) -> CGFloat {
        Metric.card + rowsTop + Metric.teamRow * CGFloat(rows) + Space.xs + Metric.lineGap
    }

    /// The first row's top, under the card's row.
    static var rowsTop: CGFloat { Space.xs }

    /// A row's face, in its row: in from the card by its depth.
    static func rowFace(depth: Int) -> CGRect {
        CGRect(x: Space.md + indent(depth), y: (Metric.teamRow - Metric.faceTeamRow) / 2, width: Metric.faceTeamRow, height: Metric.faceTeamRow)
    }

    /// How far a row sits in: a level each, deeper ones as the third.
    static func indent(_ depth: Int) -> CGFloat { Metric.teamIndent * CGFloat(min(max(depth, 1), 3) - 1) }

    private var session: SessionItem { content.session }
    private var closed: Bool { !session.isRunning }
    private var hovered: Bool { forced.map { $0 == .hover } ?? hovering }
    private var selected: Bool { content.selected == session.id }
    private var dropTarget: Bool { content.dropTarget == session.id }

    var body: some View {
        VStack(spacing: 0) {
            top
            if content.open { rows }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .surface(glow: glow, breathing: content.blinking, lifted: content.open || (hovered && !dropTarget), tint: tint)
        .overlay {
            if selected || dropTarget {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Ink.accent, lineWidth: Metric.selectionRing)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Motion.lift, value: hovered)
        .coordinateSpace(.named(Self.space))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spoken(content))
        .accessibilityAddTraits(.isButton)
    }

    /// "registry: ready for more customers, idle, 5 sessions, 1 asks a question".
    static func spoken(_ content: CardContent) -> String {
        let session = content.session
        var parts = [session.name, (session.reason ?? session.stateWords).lowercased()]
        guard !content.team.isEmpty else { return parts.joined(separator: ", ") + (session.status.isNew ? ", new" : "") }
        parts.append("\(content.team.count) session\(content.team.count == 1 ? "" : "s")")
        let asking = content.team.map(\.session).filter { $0.isRunning && $0.status.needsYou }
        for words in Set(asking.map(\.stateWords)).sorted() {
            let count = asking.filter { $0.stateWords == words }.count
            parts.append("\(count) " + (count == 1 ? words.lowercased() : plural(words)))
        }
        return parts.joined(separator: ", ")
    }

    private static func plural(_ words: String) -> String {
        switch words {
        case "Asks a question": "ask a question"
        case "Wants permission": "want permission"
        case "Plan ready": "have a plan ready"
        default: words.lowercased()
        }
    }

    // MARK: The card's row

    private var top: some View {
        HStack(spacing: Space.md) {
            SessionFace(session, size: Metric.faceCard, badged: false)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(session.name)
                    .kitType(.titleStrong)
                    .fontWeight(closed ? .medium : nil)
                    .foregroundStyle(closed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: Space.sm) {
                    if let role = content.role { RoleChip(role: role).opacity(closed ? 0.6 : 1).fixedSize() }
                    FactChip(text: session.place, truncation: .middle)
                    ModelChip(session: session)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !content.team.isEmpty { trayView }
            VStack(alignment: .trailing, spacing: Space.xs) {
                Text(Elapsed.short(from: session.status.since, to: now))
                    .kitType(.meta)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                SessionStatePill(session: session)
            }
            .fixedSize()
        }
        .padding(.horizontal, Space.md)
        .frame(height: Metric.card)
        .help(help)
    }

    private var help: String {
        if closed && !content.team.isEmpty { return "\(session.name). Closed; it stays while its sessions run." }
        let name = session.reason.map { "\(session.name): \($0)" } ?? session.name
        return session.isRunning ? [name, session.modelHelp].compactMap(\.self).joined(separator: "\n") : name
    }

    // MARK: The team's tray

    private var trayView: some View {
        HStack(spacing: Space.xs) {
            if content.open {
                Text("\(content.team.count) session\(content.team.count == 1 ? "" : "s")")
                    .kitType(.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else {
                let faces = Self.trayFaces(content)
                HStack(spacing: Space.xs) {
                    ForEach(faces.shown) { member in
                        SessionFace(team: member.session)
                    }
                    if faces.more > 0 {
                        Text("+\(faces.more)")
                            .kitType(.meta)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Space.xs + 2)
                            .frame(minWidth: Metric.faceTeam, minHeight: Metric.chipHeight + Space.xs)
                            .background(Ink.chipFill, in: Capsule())
                    }
                }
                .help(trayTip)
            }
            TeamToggle(id: session.id, open: content.open, count: content.team.count)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { tray($0) }
    }

    /// The faces that fit, in their order; one that needs the user is never behind "+N".
    static func trayFaces(_ content: CardContent) -> (shown: [TeamMember], more: Int) {
        let team = content.team
        let room = max(content.trayRoom, 2)
        guard team.count > room else { return (team, 0) }
        var keep = Set(team.filter { $0.session.isRunning && $0.session.status.needsYou }.prefix(room - 1).map(\.id))
        for member in team where keep.count < room - 1 { keep.insert(member.id) }
        let shown = team.filter { keep.contains($0.id) }
        return (shown, team.count - shown.count)
    }

    /// Every session of the team, with its role and state.
    private var trayTip: String {
        content.team.map { member in
            "\(member.session.name)\(member.role.map { " · \($0.name)" } ?? ""): \(member.session.stateWords)"
        }.joined(separator: "\n")
    }

    // MARK: The team's rows

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(content.team) { member in
                TeamRow(member: member, now: now, selected: content.selected == member.id, dropTarget: content.dropTarget == member.id)
            }
        }
        .padding(.top, Self.rowsTop)
        .padding(.bottom, Space.xs + Metric.lineGap)
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.rowRule).frame(height: 1).padding(.horizontal, Space.xs + 2)
        }
        .padding(.horizontal, Space.xs + 2)
    }

    // MARK: Glow

    /// One of its sessions needs the user: the card glows orange, red when one failed.
    private var glow: Color? {
        guard !dropTarget, !alone else { return nil }
        let running = content.everyone.filter(\.isRunning)
        if running.contains(where: { $0.status.state == .failed }) { return Ink.failed }
        return running.contains(where: \.status.needsYou) ? Ink.needsYou : nil
    }

    private var tint: Color? {
        if dropTarget { return Ink.dropFill }
        return selected ? Ink.cardSelection : nil
    }
}

/// A team's toggle (DESIGN.md §5): › at rest, ⌄ with an accent tint while its rows show. Its card takes the click.
private struct TeamToggle: View {
    let id: String
    let open: Bool
    let count: Int
    @State private var hovering = false

    var body: some View {
        KitIcon.disclosure.image
            .imageScale(.small)
            .fontWeight(.semibold)
            .rotationEffect(.degrees(open ? 90 : 0))
            .foregroundStyle(open ? AnyShapeStyle(Ink.accentText) : hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(width: Metric.teamToggle, height: Metric.teamToggle)
            .background(open ? AnyShapeStyle(Ink.workingFill) : hovering ? AnyShapeStyle(Ink.hoverFill) : AnyShapeStyle(Ink.chipFill), in: Circle())
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(Motion.lift, value: open)
            .help("\(open ? "Hide" : "Show") its \(count) session\(count == 1 ? "" : "s") (⌘\(open ? "↑" : "↓"))")
            .uiTestAnchor("team-toggle:\(id)")
    }
}

/// One of an open team's sessions (DESIGN.md §5): its face, name, role, place, time and state; deeper levels in, with an elbow.
private struct TeamRow: View {
    let member: TeamMember
    let now: Date
    let selected: Bool
    let dropTarget: Bool
    @State private var hovering = false

    private var session: SessionItem { member.session }

    var body: some View {
        HStack(spacing: Space.sm) {
            SessionFace(session, size: Metric.faceTeamRow, badged: false)
            Text(session.name)
                .kitType(.title)
                .fontWeight(.medium)
                .foregroundStyle(session.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .layoutPriority(1)
            if let role = member.role { RoleChip(role: role).fixedSize() }
            // The name comes first; its place keeps enough to read beside a long one.
            FactChip(text: session.place, truncation: .middle)
                .frame(minWidth: Metric.teamName / 2, maxWidth: .infinity, alignment: .leading)
            ModelChip(session: session)
            Text(Elapsed.short(from: session.status.since, to: now))
                .kitType(.meta)
                .foregroundStyle(.secondary)
                .fixedSize()
            SessionStatePill(session: session)
        }
        .padding(.leading, SessionCard.indent(member.depth))
        .padding(.horizontal, Space.xs + 2)
        .frame(height: Metric.teamRow)
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            if selected || dropTarget {
                shape.fill(dropTarget ? Ink.dropFill : Ink.cardSelection).overlay(shape.strokeBorder(Ink.accent, lineWidth: Metric.badgeRing * 0.75))
            } else if hovering {
                shape.fill(Ink.hoverFill)
            }
        }
        .overlay(alignment: .topLeading) { if member.depth > 1 { Elbow(depth: member.depth) } }
        .onHover { hovering = $0 }
        .help(session.reason.map { "\(session.name): \($0)" } ?? session.name)
    }
}

/// The line from a row's parent down and into it.
private struct Elbow: View {
    let depth: Int

    var body: some View {
        let x = Space.xs + 2 + SessionCard.indent(depth - 1) + Metric.faceTeamRow / 2 - 1
        let middle = Metric.teamRow / 2
        let turn = Space.xs + 2
        Path { path in
            path.move(to: CGPoint(x: x, y: -Space.xs))
            path.addLine(to: CGPoint(x: x, y: middle - turn))
            path.addQuadCurve(to: CGPoint(x: x + turn, y: middle), control: CGPoint(x: x, y: middle))
            path.addLine(to: CGPoint(x: x + Metric.faceTeamRow / 2 - 1, y: middle))
        }
        .stroke(Ink.boxFrame, style: StrokeStyle(lineWidth: Metric.badgeRing * 0.75, lineCap: .round))
        .allowsHitTesting(false)
    }
}

/// A session's state in a capsule, its glyph then its words: orange (red when failed) and semibold when it needs the user.
struct SessionStatePill: View {
    let session: SessionItem

    private var needsYou: Bool { session.isRunning && session.status.needsYou }
    private var failed: Bool { session.status.state == .failed }

    private var tone: (text: AnyShapeStyle, fill: AnyShapeStyle) {
        if needsYou { return failed ? (AnyShapeStyle(Ink.failedText), AnyShapeStyle(Ink.failedFill)) : (AnyShapeStyle(Ink.needsYouText), AnyShapeStyle(Ink.needsYouFill)) }
        if session.status.isNew { return (AnyShapeStyle(Ink.accentText), AnyShapeStyle(Ink.chipFill)) }
        if session.status.state == .working || session.status.state == .compacting { return (AnyShapeStyle(Ink.accentText), AnyShapeStyle(Ink.workingFill)) }
        return (AnyShapeStyle(.secondary), AnyShapeStyle(Ink.chipFill))
    }

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            SessionGlyph(kind: session.isRunning ? SessionGlyphKind(session.status) : .ended)
            Text(session.stateWords)
                .kitType(.secondary)
                .fontWeight(needsYou ? .semibold : .medium)
                .foregroundStyle(tone.text)
                .lineLimit(1)
        }
        .padding(.leading, Space.xs)
        .padding(.trailing, Space.sm + 2)
        .frame(height: Metric.statePill)
        .background(tone.fill, in: Capsule())
        .fixedSize()
    }
}

extension SessionItem {
    /// "Working", "Asks a question", "Done", as its card says: what it asks is in the tooltip and its terminal.
    var stateWords: String {
        guard isRunning else { return "Ended" }
        return status.state == .waiting(.question) ? "Asks a question" : status.title
    }
}

/// A running session's model, effort and context on a pill, "Opus VH · 442k", the whole of it on hover (T-446, T-475).
struct ModelChip: View {
    let session: SessionItem

    var body: some View {
        if session.isRunning, let line = session.modelLine {
            FactChip(text: line)
                .fixedSize()
                .help(session.modelHelp ?? line)
                .accessibilityLabel(session.modelHelp ?? line)
        }
    }
}
