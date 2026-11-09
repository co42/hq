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


/// A labeled group in the modal: a quiet label, then its content.
struct ModalGroup<Content: View>: View {
    let title: String
    /// A group that folds as a page section does: a click on its title hides or shows it.
    var open: Binding<Bool>?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let open {
                Button { withAnimation(Motion.lift) { open.wrappedValue.toggle() } } label: {
                    HStack(spacing: Space.xs) {
                        label
                        KitIcon.disclosure.image
                            .imageScale(.small)
                            .fontWeight(.bold)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .help(open.wrappedValue ? "Hide \(title)" : "Show \(title)")
                .accessibilityValue(open.wrappedValue ? "Shown" : "Folded")
            } else {
                label
            }
            if open?.wrappedValue != false { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var label: some View {
        Text(title)
            .kitType(.groupLabel)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rows in a quiet box: subtasks, outputs, details. With `rows`, inset so a `rowHighlight` nests in its corners.
struct ModalBox<Content: View>: View {
    var rows = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(rows ? Space.xs + 2 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
    }
}

/// A row's hover and selection in a card, as the outline draws them: `Radius.row`, concentric with the card's corners
/// when the row sits `Space.xs + 2` in. The accent selection while its list has the keyboard, the quiet one otherwise.
struct RowHighlight: ViewModifier {
    let selected: Bool
    let hovering: Bool
    let active: Bool

    func body(content: Content) -> some View {
        content.background(fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }

    private var fill: Color {
        if selected { return active ? Ink.rowSelection : Ink.selectionInactive }
        return hovering ? Ink.hoverFill : .clear
    }
}

extension View {
    func rowHighlight(selected: Bool, hovering: Bool = false, active: Bool = true) -> some View {
        modifier(RowHighlight(selected: selected, hovering: hovering, active: active))
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
    /// The last text copied; test runs keep it here and leave the user's pasteboard alone.
    static var copied: String?

    static func copy(_ text: String) {
        copied = text
        guard !Store.isOverridden else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The text on the pasteboard; a test run reads what it copied.
    static var text: String? { Store.isOverridden ? copied : NSPasteboard.general.string(forType: .string) }
}
