import AppKit

/// What drags inside HQ: sessions (to reorder cards), tasks (to move rows, or onto a card), and files,
/// artifacts and PRs (onto a task, to link them). The types are declared in Info.plist.
enum DragItem {
    nonisolated static let sessionType = NSPasteboard.PasteboardType("io.github.co42.hq.session")
    nonisolated static let taskType = NSPasteboard.PasteboardType("io.github.co42.hq.task")
    nonisolated static let itemType = NSPasteboard.PasteboardType("io.github.co42.hq.item")

    /// A file, an artifact, a PR or a task dragged from a row or a chip: its key for HQ's outline; its link, or its title, for other apps.
    /// No loader closure: under main-actor isolation one traps when the drag reads it off the main thread.
    static func provider(_ route: ModalRoute, title: String) -> NSItemProvider {
        let provider = NSItemProvider(item: Data(route.selectionKey.utf8) as NSData, typeIdentifier: itemType.rawValue)
        switch route {
        case .github(let url): if let link = URL(string: url) { provider.registerObject(link as NSURL, visibility: .all) }
        case .artifact(let url): provider.registerObject(url as NSURL, visibility: .all)
        default: provider.registerObject(title as NSString, visibility: .all)
        }
        return provider
    }
}

extension ModalRoute {
    /// The route a selection key names: a dragged item's.
    init?(itemKey key: String) {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "file": self = .file(parts[1])
        case "artifact": guard let url = URL(string: parts[1]) else { return nil }; self = .artifact(url)
        case "github": self = .github(parts[1])
        case "task": guard let id = Int(parts[1]) else { return nil }; self = .task(id)
        default: return nil
        }
    }
}
