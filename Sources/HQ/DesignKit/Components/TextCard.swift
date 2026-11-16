import SwiftUI

/// Markdown on a raised card (T-470): a note's with room around its text, a task's description at its column's. Editing, it
/// stays where it is and takes an accent outline.
struct TextCard<Content: View>: View {
    enum Size { case page, compact }
    var size = Size.compact
    var editing = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(radius: Radius.card)
            .overlay {
                if editing {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Ink.accent).allowsHitTesting(false)
                }
            }
    }

    private var insets: EdgeInsets {
        switch size {
        case .page: EdgeInsets(top: Space.section, leading: Metric.noteInset, bottom: Metric.noteInset, trailing: Metric.noteInset)
        case .compact: EdgeInsets(top: Space.md, leading: Space.md, bottom: Space.md, trailing: Space.md)
        }
    }
}
