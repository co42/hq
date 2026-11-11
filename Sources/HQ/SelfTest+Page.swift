import AppKit
import HQKit

extension SelfTest {
    /// Settings › Keys lists what the Task menu binds while the outline's rows have the keyboard (B, ⇧B, A and the others
    /// that are text keys too); the cards' rows the keys walk are the rows the cards show.
    static func pageFixChecks(_ model: AppModel) async {
        let keyboard = model.outlineKeyboard
        model.closeModal()
        model.outlineKeyboard = .rows
        let listed = Set(KeysSettings.all.flatMap { $0.1.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init) })
        func taskMenu() -> [NSMenuItem] {
            guard let menu = NSApp.mainMenu?.items.first(where: { $0.title == "Task" })?.submenu else { return [] }
            // As when the user opens it: SwiftUI brings its items up to date then.
            menu.delegate?.menuNeedsUpdate?(menu)
            menu.delegate?.menuWillOpen?(menu)
            menu.update()
            menu.delegate?.menuDidClose?(menu)
            return menu.items
        }
        // The menus follow the model on SwiftUI's next update.
        for _ in 0..<40 where !taskMenu().contains(where: { $0.keyEquivalent == "b" && $0.keyEquivalentModifierMask.isEmpty }) {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let keys = taskMenu().compactMap { item -> String? in
            guard !item.keyEquivalent.isEmpty else { return nil }
            let names: [String: String] = ["\r": "Return", "\u{7f}": "⌫", "\u{8}": "⌫",
                                           String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!): "↑",
                                           String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!): "↓",
                                           String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!): "←",
                                           String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!): "→"]
            var flags = item.keyEquivalentModifierMask
            let key = item.keyEquivalent
            if key.count == 1, key.uppercased() == key, key.lowercased() != key { flags.insert(.shift) }
            let mods = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
                .filter { flags.contains($0.0) }.map(\.1).joined()
            return mods + (names[key] ?? key.uppercased())
        }
        let unlisted = keys.filter { !listed.contains($0) }
        check("Settings › Keys lists every key the Task menu binds while the rows have the keyboard (\(keys.count))",
              keys.contains("B") && unlisted.isEmpty, "bound: \(keys.joined(separator: " ")); unlisted: \(unlisted.joined(separator: ", "))")
        model.outlineKeyboard = keyboard

        // Show N More: the rows the keys walk are the rows the card shows, past the fifth too.
        let search = model.search
        model.search = ""
        let cards: [RowCard] = [.reviews, .yours, .files, .artifacts]
        let folded = cards.map { model.shown(model.cardRoutes($0), in: $0).count }
        model.expandedCards = Set(cards)
        let open = cards.map { model.shown(model.cardRoutes($0), in: $0).count }
        check("Show N More opens a card to all its rows, and the keys walk them",
              open == cards.map { model.cardRoutes($0).count } && folded.allSatisfy { $0 <= PRCards.shown }
              && model.sectionRoutes(.pullRequests).count == open[0] + open[1] && model.sectionRoutes(.files).count == open[2] + open[3],
              "folded \(folded), open \(open)")
        model.expandedCards = []
        model.search = search
    }
}
