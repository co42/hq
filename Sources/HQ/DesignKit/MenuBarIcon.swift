import AppKit

/// HQ's mark in the menu bar (DESIGN.md §3): the app icon's ring and dot, seen from any app. While something needs the
/// user it turns orange with the count beside it, and blinks until they open the center. A click opens its menu.
@MainActor
final class MenuBarIcon: NSObject {
    static let shared = MenuBarIcon()
    private var item: NSStatusItem?
    private var shown: (count: Int, blinks: Bool)?

    /// A click opens `menu` (T-325).
    func show(menu: NSMenu) {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        item.button?.imagePosition = .imageLeading
        item.button?.wantsLayer = true
        self.item = item
        update(count: 0, blinks: false)
    }

    func update(count: Int, blinks: Bool) {
        guard let button = item?.button, shown?.count != count || shown?.blinks != blinks else { return }
        shown = (count, blinks)
        button.image = Self.mark(color: count > 0 ? Ink.needsYouNS : nil)
        button.attributedTitle = Self.countTitle(count)
        button.toolTip = count > 0 ? "\(count) need\(count == 1 ? "s" : "") you: open HQ's notifications" : "HQ: nothing needs you"
        button.setAccessibilityLabel(count > 0 ? "HQ, \(count) need you" : "HQ")
        if count > 0 && blinks { blink(button) } else { button.layer?.removeAnimation(forKey: "blink") }
    }

    /// On the render server, as a card breathes: from bright to faint and back until the user opens the center.
    private func blink(_ button: NSView) {
        guard let layer = button.layer, layer.animation(forKey: "blink") == nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.3
        animation.duration = Motion.blinkHalf
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "blink")
    }

    /// The count beside the mark, in its orange: the menu bar's own text color reads black on a dark bar (T-309).
    static func countTitle(_ count: Int) -> NSAttributedString {
        NSAttributedString(string: count > 0 ? "\(count)" : "", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            .foregroundColor: Ink.needsYouNS,
        ])
    }

    var blinking: Bool { item?.button?.layer?.animation(forKey: "blink") != nil }

    /// The app icon's ring and dot (Icon/AppIcon.icon, a 1024 canvas whose shapes span 240 to 784), 16 pt in an 18 pt
    /// square: a template image that follows the menu bar, or drawn in `color`.
    static func mark(color: NSColor?) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let scale = (side - 2) / 544
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: 1 + (x - 240) * scale, y: 1 + (y - 240) * scale) }
            (color ?? .black).set()
            // The ring: from twelve o'clock clockwise round to nine, round ends; the dot sits in the gap.
            let ring = NSBezierPath()
            ring.appendArc(withCenter: point(512, 512), radius: 224 * scale, startAngle: -90, endAngle: 180, clockwise: false)
            ring.lineWidth = 96 * scale
            ring.lineCapStyle = .round
            ring.stroke()
            let corner = point(354 - 68, 354 - 68)
            NSBezierPath(ovalIn: NSRect(origin: corner, size: NSSize(width: 136 * scale, height: 136 * scale))).fill()
            return true
        }
        image.isTemplate = color == nil
        return image
    }
}
