import AppKit

/// HQ's bell in the menu bar (DESIGN.md §11): how many things need the user, seen from any app. A click opens the center.
@MainActor
final class MenuBarBell: NSObject {
    static let shared = MenuBarBell()
    private var item: NSStatusItem?
    private var action: (() -> Void)?
    private var shown: Int?

    func show(_ action: @escaping () -> Void) {
        self.action = action
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(click)
        item.button?.imagePosition = .imageLeading
        self.item = item
        update(count: 0)
    }

    /// The bell, filled with the count beside it while something needs the user.
    func update(count: Int) {
        guard let button = item?.button, shown != count else { return }
        shown = count
        let image = (count > 0 ? KitIcon.bellFill : KitIcon.bell).nsImage?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        image?.isTemplate = true
        button.image = image
        button.title = count > 0 ? "\(count)" : ""
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        button.toolTip = count > 0 ? "\(count) need\(count == 1 ? "s" : "") you: open HQ's notifications" : "HQ: nothing needs you"
        button.setAccessibilityLabel(count > 0 ? "HQ, \(count) need you" : "HQ")
    }

    @objc private func click() { action?() }
}
