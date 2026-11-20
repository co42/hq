import AppKit

/// Quick Open's field has the keyboard from the first ⌘K after launch, and every one after it (T-684).
extension UITest {
    static func quickOpenFocus(_ model: AppModel, _ ui: Driver) async {
        guard let app = AppDelegate.shared else { return await check("the app delegate", false) }
        app.freshQuickOpen()
        for round in ["the first", "a second"] {
            await ui.key("k", .command, code: 40)
            let panel = app.quickOpenPanel
            await check("\(round) Command-K opens Quick Open with its field taking the keyboard",
                        panel.isVisible && (panel.firstResponder as? NSTextView)?.delegate is QuickOpenField.Field,
                        String(describing: panel.firstResponder))
            panel.dismiss()
            await ui.settle(0.3)
        }
    }
}
