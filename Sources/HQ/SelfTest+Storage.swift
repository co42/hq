import Foundation
import HQKit

/// T-485: a session is stored once, whatever happens to a read; duplicates already stored go at launch.
extension SelfTest {
    static func storageChecks() {
        let url = Store.url.deletingLastPathComponent().appending(path: "selftest-duplicates.store")
        for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
        guard let storage = try? Storage(url: url) else { return check("a second store opens for the storage checks", false) }
        let now = Date.now
        let items = (0..<3).map { index in
            SessionItem(id: "5eed0485-0000-4000-8000-00000000000\(index)", customName: "Stored \(index)",
                        status: SessionStatus(state: .idle, since: now), cwd: "~/code", repo: "repo", branch: "main", started: now)
        }
        _ = storage.sessions()
        storage.save(items)

        AppLog.expected += ["couldn't read SessionRecord", "couldn't read SessionRecord"]
        Storage.failReads = true
        storage.save(items)
        storage.save(items + items)
        Storage.failReads = false
        check("a save after a failed read stores no session again", storage.rows(SessionRecord.self) == 3,
              "\(storage.rows(SessionRecord.self)) rows for 3 sessions")

        storage.save(items + items)
        check("a list that holds a session twice stores it once", storage.rows(SessionRecord.self) == 3,
              "\(storage.rows(SessionRecord.self)) rows")

        // Rows already doubled, the newer copy second: a relaunch keeps one of each, the newest.
        var newer = items[0]
        newer.status.lastActivity = now.addingTimeInterval(60)
        newer.customName = "Stored 0, newer"
        storage.container.mainContext.insert(SessionRecord(newer))
        storage.container.mainContext.insert(SessionRecord(items[1]))
        try? storage.container.mainContext.save()
        AppLog.expected.append("removed 2 duplicate SessionRecord rows at launch")
        guard let reopened = try? Storage(url: url) else { return check("the doubled store opens again", false) }
        let loaded = reopened.sessions()
        check("a relaunch removes a store's duplicate sessions, the newest kept",
              loaded.count == 3 && Set(loaded.map(\.id)).count == 3 && reopened.rows(SessionRecord.self) == 3
              && loaded.first { $0.id == newer.id }?.customName == newer.customName && AppLog.expected.isEmpty,
              "\(loaded.count) loaded, \(reopened.rows(SessionRecord.self)) rows, \(AppLog.expected)")
        reopened.save(loaded)
        check("and its next save keeps one row each", reopened.rows(SessionRecord.self) == 3)

        // The store's change history goes once old: it held 4.57 million rows on 2026-11-16.
        let before = reopened.historyCount()
        let kept = Storage.pruneHistory(reopened.container, before: .now.addingTimeInterval(-3600))
        let midway = reopened.historyCount()
        let pruned = Storage.pruneHistory(reopened.container, before: .now.addingTimeInterval(1))
        check("pruning keeps the last hour's history, then drops what's older", before > 0 && kept == nil && midway == before
              && pruned == nil && reopened.historyCount() == 0, "\(before), \(midway), \(reopened.historyCount()): \(pruned ?? "")")
        logChecks()
    }

    /// HQ's logs stay small: a line repeated is written once with its count, and a log past its cap keeps its newest half (T-512).
    private static func logChecks() {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "hq-selftest-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: file) }
        for _ in 0..<500 { AppLog.record("Working ends", at: .now, in: file) }
        AppLog.record("Another line", at: .now, in: file)
        let lines: [Substring] = ((try? String(contentsOf: file, encoding: .utf8)) ?? "").split(separator: "\n")
        check("a line repeated 500 times is written once, then its count", lines.count == 3 && lines[1].hasSuffix("(the line above 499 more times)"),
              lines.joined(separator: " | "))
        let line = Data((String(repeating: "x", count: 99) + "\n").utf8)
        for _ in 0..<1000 { AppLog.append(line, to: file, cap: 10_000) }
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? -1
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let kept: [Substring] = text.split(separator: "\n")
        check("a log past its cap keeps its newest half, whole lines, and says older ones went", size > 0 && size <= 10_000
              && text.hasPrefix("(older lines dropped") && kept.dropFirst().allSatisfy { $0.count == 99 }, "\(size) bytes")
    }
}
