import HQKit
import SwiftUI

/// A session on the grid (DESIGN.md §5): a raised card on one row: its face; its name and how long it has lasted;
/// its place and its state in a capsule. It glows when it needs the user (red when failed), and the glow breathes
/// until the user looks. Done and unread shows only in its state. Hover lifts it.
struct SessionCard: View {
    let session: SessionItem
    let now: Date
    var selected = false
    /// A task hovers the card: dropping links it.
    var dropTarget = false
    /// It needs the user, who hasn't clicked it, opened it or looked at its terminal since.
    var blinking = false
    @Environment(\.forcedPartState) private var forced
    @State private var hovering = false

    private var needsYou: Bool { session.status.needsYou }
    private var failed: Bool { session.status.state == .failed }
    private var hovered: Bool { forced.map { $0 == .hover } ?? hovering }

    var body: some View {
        // One row: the name with how long it has lasted, then its place with its state.
        HStack(alignment: .center, spacing: Space.md) {
            SessionFace(session, size: Metric.faceCard)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                    Text(session.name)
                        .kitType(.titleStrong)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    corner
                }
                HStack(spacing: Space.sm) {
                    Text(session.place)
                        .kitType(.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    statePill.fixedSize()
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

    /// How long it has lasted.
    private var corner: some View {
        Text(session.isRunning ? Elapsed.short(from: session.status.since, to: now) : "")
            .kitType(.meta)
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
            .fixedSize()
    }

    /// Needs the user: the card glows orange, red when it failed. Done unread shows only in its state, lightly.
    private var glow: Color? {
        guard session.isRunning, !dropTarget else { return nil }
        if failed { return Ink.failed }
        return needsYou ? Ink.needsYou : nil
    }

    private var tint: Color? {
        if dropTarget { return Ink.dropFill }
        return selected ? Ink.cardSelection : nil
    }

    private var stateText: String { session.stateWords }

    private var tone: (text: AnyShapeStyle, fill: AnyShapeStyle) {
        if needsYou { return failed ? (AnyShapeStyle(Ink.failedText), AnyShapeStyle(Ink.failedFill)) : (AnyShapeStyle(Ink.needsYouText), AnyShapeStyle(Ink.needsYouFill)) }
        if session.status.isNew { return (AnyShapeStyle(Ink.accentText), AnyShapeStyle(Ink.chipFill)) }
        if session.status.state == .working || session.status.state == .compacting { return (AnyShapeStyle(Ink.accentText), AnyShapeStyle(Ink.workingFill)) }
        return (AnyShapeStyle(.secondary), AnyShapeStyle(Ink.chipFill))
    }

    private var statePill: some View {
        HStack(spacing: Space.xs + 2) {
            SessionGlyph(kind: SessionGlyphKind(session.status))
            Text(stateText)
                .kitType(.secondary)
                .fontWeight(needsYou ? .semibold : .medium)
                .foregroundStyle(tone.text)
                .lineLimit(1)
        }
        .padding(.leading, Space.xs)
        .padding(.trailing, Space.sm + 2)
        .frame(height: Metric.statePill)
        .background(tone.fill, in: Capsule())
    }
}

extension SessionItem {
    /// "Working", "Asks a question", "Done", as its card says: what it asks is in the tooltip and its terminal.
    var stateWords: String {
        guard isRunning else { return "Ended" }
        return status.state == .waiting(.question) ? "Asks a question" : status.title
    }
}
