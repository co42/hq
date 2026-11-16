import SwiftUI

/// An Obsidian callout's kind, by its name in `> [!name]` (T-368 item 7): its symbol and color. Never orange: orange means
/// "needs you".
enum CalloutKind {
    case note, tip, warning, danger, question, quote

    init(_ name: String) {
        switch name.lowercased() {
        case "tip", "hint", "important", "success", "check", "done": self = .tip
        case "warning", "caution", "attention": self = .warning
        case "danger", "error", "bug", "failure", "fail", "missing": self = .danger
        case "question", "help", "faq": self = .question
        case "quote", "cite", "example", "abstract", "summary", "tldr", "todo": self = .quote
        default: self = .note
        }
    }

    var color: Color {
        switch self {
        case .note: Ink.accent
        case .tip: Ink.done
        case .warning: Ink.doing
        case .danger: Ink.failed
        case .question: Color(nsColor: .systemPurple)
        case .quote: Color(nsColor: .secondaryLabelColor)
        }
    }

    var icon: KitIcon {
        switch self {
        case .note: .calloutNote
        case .tip: .calloutTip
        case .warning: .calloutWarning
        case .danger: .calloutDanger
        case .question: .calloutQuestion
        case .quote: .calloutQuote
        }
    }
}

/// A callout drawn quietly: a faint box of its kind's color, its symbol and title; a foldable one (`[!note]-`, `[!note]+`)
/// opens and closes on a click on its title.
struct CalloutBox<Content: View>: View {
    let kind: CalloutKind
    let title: String
    let foldable: Bool
    @State var folded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        VStack(alignment: .leading, spacing: Space.sm) {
            let header = HStack(spacing: Space.sm) {
                kind.icon.image.foregroundStyle(kind.color)
                Text(title).kitType(.titleStrong)
                if foldable { (folded ? KitIcon.disclosure : KitIcon.disclosed).image.imageScale(.small).foregroundStyle(.secondary) }
            }
            if foldable {
                Button { folded.toggle() } label: { header.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .clickable()
                    .help(folded ? "Show it" : "Hide it")
                    .accessibilityValue(folded ? "Folded" : "Open")
            } else {
                header
            }
            if !folded { content }
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(kind.color.opacity(0.08), in: shape)
        .overlay(shape.strokeBorder(kind.color.opacity(0.25)))
    }
}
