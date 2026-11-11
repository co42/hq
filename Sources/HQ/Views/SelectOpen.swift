import SwiftUI

/// A click selects, a double-click opens: every item in the app but text, which a double-click edits.
struct SelectOpen: ViewModifier {
    let key: String
    /// The page section the item is in: a click there gives it the page's selection, and the keyboard.
    let section: PageSection?
    let open: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.inModal) private var inModal

    func body(content: Content) -> some View {
        let selected = (inModal ? model.modalSelection : model.selectedItem) == key
        content
            .background(selected ? Ink.rowSelection : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { // lint: ok SelectOpen itself
                select()
                open()
            }
            .simultaneousGesture(TapGesture().onEnded { select() })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { open() }
    }

    private func select() {
        model.select(key, in: section, inModal: inModal)
    }
}

extension AppModel {
    /// A click on an item: in the modal, the modal's own selection, so the page keeps its own; on the page, the page's,
    /// its section taking the selection and the keyboard.
    func select(_ key: String, in section: PageSection?, inModal: Bool) {
        guard !inModal else {
            modalSelection = key
            return
        }
        selectedItem = key
        guard let section, modal == nil else { return }
        selectSection(section)
        // The outline keeps the keyboard for a chip under its row.
        if section != .tasks { sectionFocus = section }
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

    /// The PR, file or artifact a selection key names, a chip's under a task too.
    init?(selectionKey key: String) {
        var key = Substring(key)
        if key.hasPrefix(Self.chipPrefix), let task = key.dropFirst(Self.chipPrefix.count).firstIndex(of: ":") {
            key = key[key.index(after: task)...]
        }
        if key.hasPrefix("github:") { self = .github(String(key.dropFirst(7))) }
        else if key.hasPrefix("web:") { self = .web(String(key.dropFirst(4))) }
        else if key.hasPrefix("slack:") { self = .slack(String(key.dropFirst(6))) }
        else if key.hasPrefix("file:") { self = .file(String(key.dropFirst(5))) }
        else if key.hasPrefix("artifact:"), let url = URL(string: String(key.dropFirst(9))) { self = .artifact(url) }
        else { return nil }
    }

    /// The route as a selection key.
    var selectionKey: String {
        switch self {
        case .task(let id): "task:\(id)"
        case .session(let id): "session:\(id)"
        case .file(let id): "file:\(id)"
        case .artifact(let url): "artifact:\(url.absoluteString)"
        case .github(let url): "github:\(url)"
        case .web(let url): "web:\(url)"
        case .slack(let url): "slack:\(url)"
        case .newTask(let list): "newTask:\(list.rawValue)"
        case .newReminder: "newReminder"
        case .newFile: "newFile"
        case .importArtifact: "importArtifact"
        case .start: "start"
        case .closedSessions: "closed"
        case .roles: "roles"
        case .notifications: "notifications"
        }
    }
}
