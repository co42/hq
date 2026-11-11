import AppKit

/// The main window's place and size as HQ quit, one per screen setup (T-373): restored at launch while it's on a screen.
@MainActor
enum WindowFrame {
    /// A screen setup: the frames of its screens.
    static func key(screens: [NSRect]) -> String {
        "window.frame." + screens.map { NSStringFromRect($0) }.joined(separator: "|")
    }

    static var currentKey: String { key(screens: NSScreen.screens.map(\.frame)) }

    static func save(_ window: NSWindow, in defaults: UserDefaults = Prefs.defaults) {
        guard !window.styleMask.contains(.fullScreen), window.frame.width > 0 else { return }
        defaults.set(NSStringFromRect(window.frame), forKey: currentKey)
    }

    /// The frame saved for this screen setup, when its title bar still shows on one of `screens`.
    static func saved(in defaults: UserDefaults = Prefs.defaults, screens: [NSRect] = NSScreen.screens.map(\.visibleFrame)) -> NSRect? {
        guard let text = defaults.string(forKey: currentKey) else { return nil }
        let frame = NSRectFromString(text)
        let titleBar = NSRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
        guard frame.width >= Metric.windowMin.width, frame.height >= Metric.windowMin.height,
              screens.contains(where: { $0.intersection(titleBar).width >= 120 }) else {
            AppLog.write("saved window frame \(text) is off every screen: default placement", to: "window.log")
            return nil
        }
        return frame
    }

    /// Puts the window where it was; false leaves today's placement.
    @discardableResult
    static func restore(_ window: NSWindow, from defaults: UserDefaults = Prefs.defaults) -> Bool {
        guard let frame = saved(in: defaults) else { return false }
        window.setFrame(frame, display: false)
        return true
    }
}
