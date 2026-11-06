import AppKit
import HQKit
import SwiftUI

/// A section's header on the page: its title in Title 3, a count, and buttons on the trailing edge.
/// With `open`, a click on the title folds the section to its header, and its buttons go with it.
struct SectionHeader<Trailing: View>: View {
    let title: String
    var count: String?
    var open: Binding<Bool>?
    /// Its keyboard shortcut, for the tooltip.
    var key: String?
    /// Its symbol and the tile's tint.
    var tile: (icon: KitIcon, tint: Color)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Space.sm) {
            if let open {
                Button { withAnimation(Motion.lift) { open.wrappedValue.toggle() } } label: {
                    titleLine(open: open.wrappedValue).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help((open.wrappedValue ? "Hide \(title)" : "Show \(title)") + (key.map { " (\($0))" } ?? ""))
                .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
                .accessibilityValue(open.wrappedValue ? "Shown" : "Folded")
                .accessibilityAddTraits(.isHeader)
                // The title keeps its width: the buttons give way first.
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            } else {
                titleLine(open: nil)
            }
            Spacer(minLength: Space.sm)
            if open?.wrappedValue != false {
                // The section's controls: one glass group, like a toolbar of its own.
                GlassEffectContainer(spacing: Space.sm) {
                    HStack(spacing: Space.sm) { trailing }
                        .buttonStyle(HeaderButtonStyle())
                        .toggleStyle(HeaderToggleStyle())
                        .menuStyle(.button)
                        .menuIndicator(.hidden)
                }
            }
        }
        .frame(minHeight: Metric.sectionBar)
    }

    private func titleLine(open: Bool?) -> some View {
        HStack(alignment: .center, spacing: Space.sm + 2) {
            if let tile {
                SectionTile(icon: tile.icon, tint: tile.tint)
                    .saturation(open == false ? 0.2 : 1)
            }
            Text(title)
                .kitType(.sectionTitle)
                .foregroundStyle(open == false ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text(count)
                    .kitType(.meta)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Space.sm - 1)
                    .frame(height: Metric.chipHeight)
                    .background(Ink.chipFill, in: Capsule())
                    .contentTransition(.numericText())
            }
            if let open {
                KitIcon.disclosure.image
                    .imageScale(.small)
                    .fontWeight(.bold)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: Metric.glyphSlot)
            }
        }
    }
}

/// A section header's action as its icon, with a count when it has one; its name goes in the tooltip and to VoiceOver.
struct HeaderIcon: View {
    let icon: KitIcon
    var count: Int?

    var body: some View {
        HStack(spacing: Space.xs) {
            icon.image.frame(width: Metric.glyphSlot)
            if let count, count > 0 { Text("\(count)").monospacedDigit() }
        }
    }
}

/// A word on a quiet capsule: tags, projects.
struct Chip: View {
    let text: String
    var icon: KitIcon?

    var body: some View {
        HStack(spacing: Space.xs) {
            if let icon { icon.image.imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(icon == .project ? "Project \(text)" : icon == .tag ? "Tag \(text)" : text)
        .kitType(.secondary)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.xs + 2)
        .frame(height: Metric.chipHeight)
        .background(Ink.chipFill, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }
}

/// An orange tag (needs the user: "Review: PR #418 is ready") or a blue one ("2 new").
struct AttentionTag: View {
    enum Tone { case needsYou, new }
    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .kitType(.secondary)
            .fontWeight(.semibold)
            .lineLimit(1)
            .foregroundStyle(tone == .needsYou ? Ink.needsYouText : Ink.unreadText)
            .padding(.horizontal, Space.xs + 2)
            .frame(height: Metric.chipHeight)
            .background(tone == .needsYou ? Ink.needsYouFill : Ink.unreadFill,
                        in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
    }
}

/// A task key like T-12: monospaced, tertiary.
struct KeyLabel: View {
    let key: String

    var body: some View {
        Text(key)
            .kitType(.key)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }
}

/// A PR's or an issue's state: its symbol in GitHub's colors.
struct GitHubStateIcon: View {
    let item: GitHubItem

    var body: some View {
        KitIcon.github(item).image
            .foregroundStyle(Self.color(item))
            .frame(width: Metric.glyphSlot, height: Metric.glyphSlot)
            .accessibilityLabel(Self.label(item))
    }

    /// Its kind tile: the state's symbol on the state's color.
    static func tile(_ item: GitHubItem) -> some View {
        KindTile(icon: KitIcon.github(item), tint: tint(item)).accessibilityLabel(label(item))
    }

    static func tint(_ item: GitHubItem) -> Color {
        switch item.state {
        case .open: Ink.done
        case .draft: Ink.draftTile
        case .merged: Ink.merged
        case .closed: Ink.failed
        }
    }

    static func color(_ item: GitHubItem) -> AnyShapeStyle {
        switch item.state {
        case .open: AnyShapeStyle(Ink.done)
        case .draft: AnyShapeStyle(.secondary)
        case .merged: AnyShapeStyle(Ink.merged)
        case .closed: AnyShapeStyle(Ink.failed)
        }
    }

    static func label(_ item: GitHubItem) -> String {
        let kind = item.kind == .issue ? "Issue" : "Pull request"
        switch item.state {
        case .open: return "\(kind), open"
        case .draft: return "\(kind), draft"
        case .merged: return "\(kind), merged"
        case .closed: return "\(kind), closed"
        }
    }
}

/// A dot before a row: orange when it needs the user, blue when it's new.
struct AttentionDot: View {
    let needsYou: Bool
    let isNew: Bool

    var body: some View {
        Circle()
            .fill(needsYou ? AnyShapeStyle(Ink.needsYou) : isNew ? AnyShapeStyle(Ink.unread) : AnyShapeStyle(.clear))
            .frame(width: Metric.attentionDot, height: Metric.attentionDot)
            .accessibilityElement()
            .accessibilityLabel(needsYou ? "Needs you" : isNew ? "New" : "")
            .accessibilityHidden(!needsYou && !isNew)
    }
}

/// A labeled group in the modal: a quiet label, then its content.
struct ModalGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .kitType(.groupLabel)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rows in a quiet box: subtasks, outputs, details.
struct ModalBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
    }
}

/// Monospaced text on a quiet block: tool input, commands, code in markdown. With `copies`,
/// a Copy button sits in its top trailing corner.
struct CodeBlock: View {
    let text: String
    var copies = false

    var body: some View {
        Text(text)
            .kitType(.code)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.sm)
            .padding(.trailing, copies ? Space.xxl : 0)
            .background(Ink.chipFill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if copies {
                    Button("Copy", icon: .copy) { Pasteboard.copy(text) }
                        .clickable()
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .clickable()
                        .imageScale(.small)
                        .padding(Space.xs)
                        .help("Copy this code")
                }
            }
    }
}

/// A value with a copy button, for paths, branches and ids.
struct CopyableValue: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Space.sm) {
            Text(label)
                .kitType(.callout)
                .foregroundStyle(.secondary)
                .frame(width: Metric.propertyLabel + Space.lg, alignment: .leading)
            Text(value)
                .kitType(.key)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(value)
            Spacer(minLength: Space.sm)
            Button("Copy \(label)", icon: .copy) { Pasteboard.copy(value) }
                .clickable()
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .clickable()
                .imageScale(.small)
                .help("Copy the \(label.lowercased())")
        }
        .padding(.horizontal, Space.md)
        .frame(minHeight: Metric.boxRow)
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
