import AppKit
import HQKit

extension UITest {
    /// The toolbar's who waits (T-655): the faces of what waits on the user, newest first, three then "+n", reviews out;
    /// a click focuses the session's terminal and reads its pings, a reminder opens the center on it; nothing when
    /// nothing waits.
    static func waitingFaces(_ model: AppModel, _ ui: Driver) async {
        model.closeModal()
        await ui.settle(0.5)
        let items = model.waitingItems
        await check("who waits holds every waiting session, ping and due important reminder, newest first, and no review",
                    items.count > Metric.waitingShown && !model.waitingReviews.isEmpty
                        && model.blockedSessions.allSatisfy { session in items.contains { $0.session?.id == session.id } }
                        && items.map(\.at) == items.map(\.at).sorted(by: >)
                        && model.notices.filter { $0.level == .important && $0.readAt == nil && ($0.dueAt ?? .distantPast) <= .now }
                            .allSatisfy { notice in items.contains { $0.pings.contains { $0.id == notice.id } } },
                    "\(items.count) items, \(model.waitingReviews.count) reviews")
        await check("the toolbar shows the first three, left to right, then +n",
                    items.prefix(Metric.waitingShown).compactMap { ui.anchor("waiting:\($0.id)")?.x } == items.prefix(Metric.waitingShown).compactMap { ui.anchor("waiting:\($0.id)")?.x }.sorted()
                        && items.prefix(Metric.waitingShown).allSatisfy { ui.anchor("waiting:\($0.id)") != nil }
                        && items.dropFirst(Metric.waitingShown).allSatisfy { ui.anchor("waiting:\($0.id)") == nil }
                        && ui.anchor("waiting-more") != nil)
        await check("it sits after New", (ui.anchor("waiting")?.x ?? 0) > (ui.anchor("new")?.x ?? .infinity))

        // A ping from a running session that doesn't wait: its face first, a bell badge; a click focuses it and reads it.
        guard let quiet = model.gridSessions.first(where: { $0.isRunning && !$0.status.needsYou && $0.tty != nil }) else {
            return await check("a running session that doesn't wait", false)
        }
        let ping = model.notify("Canary green, merge #418?", level: .important, source: quiet.id)
        await ui.until(2) { ui.anchor("waiting:session:\(quiet.id)") != nil }
        await check("a ping shows its session's face first, with a bell", model.waitingItems.first?.session?.id == quiet.id
                    && model.waitingItems.first?.glyph == .ping && ui.anchor("waiting:session:\(quiet.id)") != nil)
        let logged = model.ghosttyLog.count
        await ui.click(ui.anchor("waiting:session:\(quiet.id)"))
        await ui.until(2) { model.ghosttyLog.count > logged }
        await check("a click on it focuses its terminal and reads the ping",
                    model.ghosttyLog.dropFirst(logged).contains { $0.contains("focus") } && model.notices.first { $0.id == ping.id }?.readAt != nil
                        && model.modal == nil, model.ghosttyLog.dropFirst(logged).joined(separator: ", "))

        // A ping from a session that waits: one face, its wait's badge.
        if let waiting = model.blockedSessions.first {
            let before = model.waitingItems.count
            let merged = model.notify("Still need your answer", level: .important, source: waiting.id)
            await check("a waiting session's ping adds no face: its wait shows", model.waitingItems.count == before
                        && model.waitingItems.first { $0.session?.id == waiting.id }?.glyph == SessionGlyphKind(waiting.status))
            model.markRead(merged.id)
        }

        // A due important reminder: its tile; a click opens the center on it.
        let reminder = model.remind("Call the bank", at: .now.addingTimeInterval(-1), level: .important)
        let key = "waiting:notice:\(reminder.id.uuidString)"
        await ui.until(2) { ui.anchor(key) != nil }
        await ui.click(ui.anchor(key))
        await ui.until(2) { model.modal == .notifications }
        await check("a click on a reminder opens the center on it", model.modal == .notifications && model.noticeSelection == reminder.id.uuidString,
                    "\(String(describing: model.modal)), \(model.noticeSelection ?? "-")")
        model.closeModal()
        model.notices.removeAll { $0.id == reminder.id }

        // Nothing waits: no group.
        let sessions = model.sessions
        let notices = model.notices
        for session in model.blockedSessions {
            var item = session
            item.status = SessionStatus(state: .idle, since: .now)
            model.put(item)
        }
        for index in model.notices.indices where model.notices[index].level == .important { model.notices[index].readAt = .now }
        await ui.until(2) { ui.anchor("waiting") == nil }
        await check("nothing waits: who waits is gone, the bell stays", ui.anchor("waiting") == nil && ui.anchor("bell") != nil && !model.waitingReviews.isEmpty)
        model.sessions = sessions
        model.notices = notices
        await ui.settle(0.3)
    }
}
