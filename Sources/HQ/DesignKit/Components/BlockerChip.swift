import SwiftUI

/// A task another is blocked by, as its card's red capsule (DESIGN.md §7): the mark, its key and title, a click opens it;
/// × takes the link off. Done, it holds nothing: quiet, on a label's fill.
struct BlockerChip: View {
    let key: String
    let title: String
    var done = false
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Button(action: open) {
                HStack(spacing: Space.xs) {
                    KitIcon.blocked.image.imageScale(.small).fontWeight(.semibold)
                    Text(key).monospacedDigit()
                    Text(title).fontWeight(.regular).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .help("Open \(key) \(title)")
            Button("Remove", icon: .close, action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .imageScale(.small)
                .hoverPlate(.chip)
                .help(done ? "Take this link off: \(key) is done" : "Not blocked by \(key)")
        }
        .kitType(.secondary)
        .fontWeight(.medium)
        .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(Ink.blockedText))
        .padding(.leading, Space.sm)
        .padding(.trailing, Space.xs)
        .frame(height: Metric.chipHeight)
        .background(done ? Ink.labelFill : Ink.blockedChip, in: Capsule())
    }
}
