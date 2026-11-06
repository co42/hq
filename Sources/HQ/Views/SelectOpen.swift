import SwiftUI

/// A click selects, a double-click opens: every item in the app but text, which a double-click edits.
struct SelectOpen: ViewModifier {
    let key: String
    /// The page section the item is in: a click there gives it the page's selection, and the keyboard.
    let section: PageSection?
    let open: () -> Void
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let selected = model.selectedItem == key
        content
            .background(selected ? Ink.rowSelection : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                select()
                open()
            }
            .simultaneousGesture(TapGesture().onEnded { select() })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { open() }
    }

    private func select() {
        model.selectedItem = key
        guard let section, model.modal == nil else { return }
        model.selectSection(section)
        // The outline keeps the keyboard for a chip under its row.
        if section != .tasks { model.sectionFocus = section }
    }
}

extension View {
    /// Click selects, double-click opens. On the page, the item's section takes the selection.
    func selectOpen(_ key: String, in section: PageSection? = nil, open: @escaping () -> Void) -> some View {
        modifier(SelectOpen(key: key, section: section, open: open))
    }
}

extension ModalRoute {
    static let chipPrefix = "chip:"

    /// A link chip under a task's row: its own key, so the same file's row in Files and Artifacts stays unselected.
    func chipKey(task: Int) -> String { "\(Self.chipPrefix)T-\(task):\(selectionKey)" }

    /// The route as a selection key.
    var selectionKey: String {
        switch self {
        case .task(let id): "task:\(id)"
        case .session(let id): "session:\(id)"
        case .file(let id): "file:\(id)"
        case .artifact(let url): "artifact:\(url.absoluteString)"
        case .github(let url): "github:\(url)"
        case .start: "start"
        case .hiddenAndClosed: "hidden"
        }
    }
}
