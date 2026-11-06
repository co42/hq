import HQKit
import SwiftUI

/// A session on the grid (DESIGN.md §5): a raised card with its face, name and place, then its state in a
/// capsule and how long it has lasted. It glows when it needs the user (red when failed) or is done unread, and the
/// glow breathes until the user looks. Hover lifts it and shows Hide.
struct SessionCard: View {
    let session: SessionItem
    let now: Date
    var selected = false
    /// A task hovers the card: dropping links it.
    var dropTarget = false
    /// It needs the user, or is done unread, and the user hasn't clicked it, opened it or looked at its terminal since.
    var blinking = false
    var hide: () -> Void = {}
    @Environment(\.forcedPartState) private var forced
    @State private var hovering = false

    private var needsYou: Bool { session.status.needsYou }
    private var failed: Bool { session.status.state == .failed }
    private var hovered: Bool { forced.map { $0 == .hover } ?? hovering }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.md) {
                SessionFace(session, size: Metric.faceCard)
                VStack(alignment: .leading, spacing: Metric.lineGap) {
                    Text(session.name)
                        .kitType(session.status.isNew ? .titleBold : .titleStrong)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(session.place)
                        .kitType(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.top, Metric.lineGap + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: .topTrailing) {
                    if hovered {
                        Button("Hide", icon: .hide, action: hide)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                            .frame(width: Metric.rowAction + Space.xs, height: Metric.rowAction + Space.xs)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .clickable()
                            .help("Hide from the overview; the session keeps running")
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .frame(minWidth: Metric.rowAction + Space.xs, alignment: .topTrailing)
            }
            Spacer(minLength: Space.sm)
            HStack(spacing: Space.sm) {
                statePill
                Spacer(minLength: 0)
                if session.isRunning {
                    Text(Elapsed.short(from: session.status.since, to: now))
                        .kitType(.meta)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(Space.md)
        .frame(height: Metric.card)
        .surface(glow: glow, breathing: blinking, lifted: hovered && !dropTarget, tint: tint)
        .overlay {
            if selected || dropTarget {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Ink.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(hovered && !dropTarget ? 1.006 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Motion.lift, value: hovered)
        .help(session.reason.map { "\(session.name): \($0)" } ?? session.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name), \(session.reason ?? stateText)")
        .accessibilityAddTraits(.isButton)
    }

    /// Needs the user (orange, red when failed) or done unread (blue): the card's glow.
    private var glow: Color? {
        guard session.isRunning, !dropTarget else { return nil }
        if failed { return Ink.failed }
        if needsYou { return Ink.needsYou }
        return session.status.isNew ? Ink.unread : nil
    }

    private var tint: Color? {
        if dropTarget { return Ink.dropFill }
        return selected ? Ink.cardSelection : nil
    }

    /// "Working", "Asks a question", "Done": what it asks is in the tooltip and its terminal.
    private var stateText: String {
        guard session.isRunning else { return "Ended" }
        return session.status.state == .waiting(.question) ? "Asks a question" : session.status.title
    }

    private var tone: (text: AnyShapeStyle, fill: AnyShapeStyle) {
        if needsYou { return failed ? (AnyShapeStyle(Ink.failedText), AnyShapeStyle(Ink.failedFill)) : (AnyShapeStyle(Ink.needsYouText), AnyShapeStyle(Ink.needsYouFill)) }
        if session.status.isNew { return (AnyShapeStyle(Ink.unreadText), AnyShapeStyle(Ink.unreadFill)) }
        if session.status.state == .working || session.status.state == .compacting { return (AnyShapeStyle(Ink.accentText), AnyShapeStyle(Ink.workingFill)) }
        return (AnyShapeStyle(.secondary), AnyShapeStyle(Ink.chipFill))
    }

    private var statePill: some View {
        HStack(spacing: Space.xs + 2) {
            SessionGlyph(kind: SessionGlyphKind(session.status))
            Text(stateText)
                .kitType(.secondary)
                .fontWeight(needsYou || session.status.isNew ? .semibold : .medium)
                .foregroundStyle(tone.text)
                .lineLimit(1)
        }
        .padding(.leading, Space.xs)
        .padding(.trailing, Space.sm + 2)
        .frame(height: Metric.statePill)
        .background(tone.fill, in: Capsule())
    }
}
