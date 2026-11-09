import AppKit
import HQKit
import UniformTypeIdentifiers

/// What drags inside HQ: sessions (to reorder cards), tasks (by their grip, to move rows, or onto a card), and tasks,
/// files, artifacts and PRs carried from their row or a chip (onto a task or a card, to link them). The types are
/// declared in Info.plist. Other apps, Ghostty first, get the item's line (`ItemLine`, T-348).
enum DragItem {
    nonisolated static let sessionType = NSPasteboard.PasteboardType("io.github.co42.hq.session")
    nonisolated static let taskType = NSPasteboard.PasteboardType("io.github.co42.hq.task")
    nonisolated static let itemType = NSPasteboard.PasteboardType("io.github.co42.hq.item")

    /// The tasks on a drag: moved by their grip, or carried from their row or a chip.
    static func tasks(on pasteboard: NSPasteboard) -> [Int] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            if let id = item.string(forType: taskType).flatMap(Int.init) { return id }
            guard let key = item.data(forType: itemType).map({ String(decoding: $0, as: UTF8.self) }),
                  case .task(let id) = ModalRoute(itemKey: key) else { return nil }
            return id
        }
    }

    /// The items carried on a drag (never a move by the grip): their routes.
    static func routes(on pasteboard: NSPasteboard) -> [ModalRoute] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            item.data(forType: itemType).flatMap { ModalRoute(itemKey: String(decoding: $0, as: UTF8.self)) }
        }
    }

    /// A drag that ended long after its release, logged to drags.log: a card dropped on Ghostty once stalled HQ 2.7 s.
    static func logEnd(_ what: String, operation: NSDragOperation) {
        guard let up = NSApp.currentEvent, up.type == .leftMouseUp else { return }
        let late = ProcessInfo.processInfo.systemUptime - up.timestamp
        guard late > 0.5 else { return }
        AppLog.write("\(what) drag ended \(String(format: "%.1f", late)) s after its release, operation \(operation.rawValue)", to: "drags.log")
    }

    /// An item carried from a SwiftUI row or chip: its key for HQ, its line for other apps.
    static func provider(_ route: ModalRoute, line: String) -> NSItemProvider {
        NSItemProvider(object: DragPayload(key: route.selectionKey, line: line))
    }
}

/// A dragged item's data, written on demand. A class with a method, never a loader closure: under main-actor
/// isolation a closure traps when the drag reads it off the main thread (T-219).
nonisolated final class DragPayload: NSObject, NSItemProviderWriting, Sendable {
    let key: String
    let line: String

    init(key: String, line: String) {
        self.key = key
        self.line = line
    }

    static var writableTypeIdentifiersForItemProvider: [String] { [DragItem.itemType.rawValue, UTType.utf8PlainText.identifier] }

    func loadData(withTypeIdentifier typeIdentifier: String,
                  forItemProviderCompletionHandler completionHandler: @escaping @Sendable (Data?, (any Error)?) -> Void) -> Progress? {
        completionHandler(Data((typeIdentifier == DragItem.itemType.rawValue ? key : line).utf8), nil)
        return nil
    }
}

extension AppModel {
    /// An item's line: what Copy and a drag to Ghostty give (T-348, T-358).
    func line(of route: ModalRoute) -> String {
        switch route {
        case .task(let id): return ItemLine.line("Task", "T-\(id)", task(id)?.title)
        case .session(let id): return ItemLine.line("Session", id, session(id)?.name)
        case .file(let id): return ItemLine.file(id)
        case .artifact(let url): return ItemLine.line("Artifact", url.absoluteString, artifacts.first { $0.id == url }?.title)
        case .github(let url):
            if let item = githubItem(url) { return ItemLine.line(item.kind == .issue ? "Issue" : "PR", "\(item.repo)#\(item.number)", item.title) }
            if let named = ItemLine.github(url) { return ItemLine.line(named.kind, named.key, nil) }
            return ItemLine.line("Link", url, nil)
        case .web(let url): return ItemLine.line("Link", url, nil)
        case .slack(let url): return ItemLine.line("Slack", url, slackMessages[url]?.title)
        default: return title(of: route)
        }
    }

    /// Several items' lines, one per line.
    func lines(of routes: [ModalRoute]) -> String { routes.map(line(of:)).joined(separator: "\n") }

    /// Copy (T-358): the items' lines on the clipboard.
    func copy(_ routes: [ModalRoute]) {
        guard !routes.isEmpty else { return }
        Pasteboard.copy(lines(of: routes))
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
        case "web": self = .web(parts[1])
        case "slack": self = .slack(parts[1])
        case "task": guard let id = Int(parts[1]) else { return nil }; self = .task(id)
        default: return nil
        }
    }
}
