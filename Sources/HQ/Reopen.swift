import Foundation
import HQKit

/// Sessions that were open when HQ quit and whose Claude was gone at the next launch (T-505): Claude quit, its tab closed,
/// a reboot. Closed Sessions offers to reopen them all, each in its place; the offer goes once used, dismissed, when none
/// of them is left closed, or after 24 h.
nonisolated struct ReopenOffer: Codable, Equatable, Sendable {
    var ids: [String]
    var at: Date
}

extension AppModel {
    /// How long the offer stays.
    static let reopenKept: TimeInterval = 24 * 3600
    /// How long Reopen All waits for a session to run before the ones under it open, in its window.
    static var reopenWait: Duration { Store.isOverridden ? .milliseconds(300) : .seconds(10) }

    /// At launch: the sessions it closed join an offer made in the last 24 h, or start one.
    func offerReopen(_ gone: [SessionItem.ID]) {
        var offer = Self.storedReopenOffer().flatMap { $0.at > .now.addingTimeInterval(-Self.reopenKept) ? $0 : nil }
        if !gone.isEmpty {
            offer = ReopenOffer(ids: (offer?.ids ?? []) + gone.filter { !(offer?.ids ?? []).contains($0) }, at: .now)
            AppLog.write("\(gone.count) open when HQ quit are gone: \(gone.map { String($0.prefix(8)) }.joined(separator: ", "))", to: "sessions.log")
        }
        setReopenOffer(offer)
    }

    /// The offer's sessions still closed, top cards first; empty when there is nothing to offer.
    var reopenable: [SessionItem] {
        guard let reopenOffer, reopenOffer.at > now.addingTimeInterval(-Self.reopenKept) else { return [] }
        let tree = sessionTree
        return reopenOffer.ids.compactMap(session).filter { $0.closedAt != nil && !$0.isRunning }
            .sorted { tree.ancestors(of: $0.id).count < tree.ancestors(of: $1.id).count }
    }

    func dismissReopen() { setReopenOffer(nil) }

    /// Each resumed in its place: top cards first, then, once they run (or after a while), the sessions under them, so a
    /// team opens in its leader's Ghostty window.
    func reopenAll() {
        let items = reopenable
        guard !items.isEmpty else { return }
        setReopenOffer(nil)
        let tree = sessionTree
        let levels = Dictionary(grouping: items) { tree.ancestors(of: $0.id).count }
        Task { [weak self] in
            for depth in levels.keys.sorted() {
                guard let self, let level = levels[depth] else { return }
                for item in level { self.resume(item.id) }
                guard depth < levels.keys.max() ?? 0 else { break }
                let started = Date.now
                while level.contains(where: { self.session($0.id)?.isRunning != true }), Date.now.timeIntervalSince(started) < Self.reopenWait.seconds {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
    }

    private func setReopenOffer(_ offer: ReopenOffer?) {
        if reopenOffer != offer { reopenOffer = offer }
        if let offer, let data = try? JSONEncoder().encode(offer) {
            Prefs.defaults.set(data, forKey: "sessions.reopen")
        } else {
            Prefs.defaults.removeObject(forKey: "sessions.reopen")
        }
    }

    private static func storedReopenOffer() -> ReopenOffer? {
        Prefs.defaults.data(forKey: "sessions.reopen").flatMap { try? JSONDecoder().decode(ReopenOffer.self, from: $0) }
    }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
