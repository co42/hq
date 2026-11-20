import SwiftUI

/// The controls on the right of a section's title (DESIGN.md §4): buttons, toggles, pop-ups and searches share
/// one height, one corner, one fill. SectionHeader applies the styles to everything it holds.
struct HeaderButtonStyle: ButtonStyle {
    var on = false
    /// On a card's title line: shorter, as tall as a state pill.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        HeaderControl(on: on, pressed: configuration.isPressed, height: compact ? Metric.statePill : nil) { configuration.label }
    }
}

/// A toggle as a header button: accent while on.
struct HeaderToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .buttonStyle(HeaderButtonStyle(on: configuration.isOn))
            .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private struct HeaderControl<Label: View>: View {
    let on: Bool
    let pressed: Bool
    /// Nil: a section header's, slimmer while it's pinned.
    let height: CGFloat?
    @ViewBuilder let label: Label
    @Environment(\.headerPinned) private var pinned
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        let height = height ?? (pinned ? Metric.pinnedControl : Metric.headerControl)
        label
            .labelStyle(.iconOnly)
            .imageScale(.medium)
            .kitType(.callout)
            .fontWeight(.medium)
            .lineLimit(1)
            .foregroundStyle(on ? AnyShapeStyle(Ink.onAccent) : hovering && enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, Space.sm + 2)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .contentShape(Capsule())
            // Glass: the section's controls float like a toolbar's; a toggle that is on is tinted with the accent.
            .glassEffect(on ? .regular.tint(Ink.accent).interactive() : .regular.interactive(), in: Capsule())
            .scaleEffect(pressed ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.hover, value: pressed)
    }
}

/// A modal header's control (DESIGN.md §8): glass, every button, menu and icon one height; `prominent` tinted with the
/// accent, `circle` for Close. ModalHeader applies it to everything it holds.
struct ModalButtonStyle: ButtonStyle {
    var prominent = false
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        ModalControl(prominent: prominent, circle: circle, pressed: configuration.isPressed) { configuration.label }
    }
}

private struct ModalControl<Label: View>: View {
    let prominent: Bool
    let circle: Bool
    let pressed: Bool
    @ViewBuilder let label: Label
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: circle ? Metric.modalButton / 2 : Radius.control)
        label
            .imageScale(.medium)
            .lineLimit(1)
            .foregroundStyle(prominent ? AnyShapeStyle(Ink.onAccent) : AnyShapeStyle(.primary))
            .padding(.horizontal, circle ? 0 : Space.sm + 2)
            .frame(minWidth: Metric.modalButton, minHeight: Metric.modalButton, maxHeight: Metric.modalButton)
            .contentShape(shape)
            .glassEffect(prominent ? .regular.tint(Ink.accent).interactive() : .regular.interactive(), in: shape)
            .scaleEffect(pressed ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.45)
            .animation(Motion.hover, value: pressed)
    }
}

/// A section's own search, as tall as its buttons: Escape clears it.
struct HeaderSearch: View {
    let prompt: String
    @Binding var text: String
    @Environment(\.headerPinned) private var pinned

    var body: some View {
        HStack(spacing: Space.xs) {
            KitIcon.search.image
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .kitType(.callout)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button("Clear", icon: .close) { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                    .help("Clear the search (Escape)")
            }
        }
        .padding(.horizontal, Space.sm + 2)
        .frame(height: pinned ? Metric.pinnedControl : Metric.headerControl)
        .frame(minWidth: Metric.listSearchMin, idealWidth: Metric.listSearch, maxWidth: Metric.listSearch)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}
