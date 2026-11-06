import SwiftUI

/// One problem under the toolbar, with its fix. Never an alert, never a toast.
struct InlineBanner: View {
    let message: String
    var detail: String?
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
            KitIcon.problem.image
                .foregroundStyle(Ink.needsYou)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metric.lineGap) {
                Text(message).kitType(.titleStrong)
                if let detail {
                    Text(detail).kitType(.secondary).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Space.sm)
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .background(Ink.bannerFill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// A row in Quick Open: an icon, the title with matched characters in the accent, and a detail.
struct QuickOpenRow<Icon: View>: View {
    let title: String
    var matched: [Int] = []
    var detail: String?
    var selected = false
    @ViewBuilder let icon: Icon
    @Environment(\.forcedPartState) private var forced

    private var isSelected: Bool { forced.map { $0 == .selected } ?? selected }

    var body: some View {
        HStack(spacing: Space.sm) {
            icon.frame(width: Metric.glyphSlot)
            highlighted
                .kitType(.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Space.sm)
            if let detail {
                Text(detail)
                    .kitType(.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Space.sm)
        .frame(height: Metric.quickOpenRow)
        .foregroundStyle(isSelected ? AnyShapeStyle(Ink.onAccent) : AnyShapeStyle(.primary))
        .environment(\.backgroundProminence, isSelected ? .increased : .standard)
        .background(SelectionFill(state: isSelected ? .selected : forced ?? .rest, radius: Radius.row))
        .contentShape(.rect)
    }

    private var highlighted: Text {
        var text = AttributedString(title)
        let marks = Set(matched)
        var index = text.startIndex
        var offset = 0
        while index < text.endIndex {
            let next = text.characters.index(after: index)
            if marks.contains(offset) {
                text[index..<next].foregroundColor = isSelected ? Ink.onAccent : Ink.accentText
                text[index..<next].inlinePresentationIntent = .stronglyEmphasized
            }
            index = next
            offset += 1
        }
        return Text(text)
    }
}
