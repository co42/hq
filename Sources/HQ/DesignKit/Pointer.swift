import AppKit
import SwiftUI

// The pointing hand over everything a click acts on (DESIGN.md §12 Pointer).

extension View {
    /// The pointing hand over an icon, a face or a chip that SwiftUI draws itself.
    func clickable() -> some View { pointerStyle(.link) }

    /// The hand only when SwiftUI is the one to give it; off where AppKit tracks it.
    func clickable(_ on: Bool) -> some View { pointerStyle(on ? .link : nil) }
}

extension NSView {
    /// The pointing hand over AppKit icons, glyphs, faces and pills that act on a click: a tracking area
    /// that follows the view wherever it moves or scrolls. The view's `cursorUpdate(with:)` sets the hand.
    func trackHandCursor(_ on: Bool = true) {
        let current = trackingAreas.filter { $0.options.contains(.cursorUpdate) && $0.owner === self }
        if on, current.isEmpty {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self))
        } else if !on {
            current.forEach(removeTrackingArea)
        }
    }

    /// A press a view acts on without tracking it takes its release too: the page's tap, which unselects everything, would
    /// get it. A menu's tracking may have taken it already; a button still held waits for it, only while it's held: a
    /// release that went elsewhere ends the wait too.
    func takeRelease() {
        var held = NSEvent.pressedMouseButtons & 1 != 0
        repeat {
            let until = held ? Date(timeIntervalSinceNow: 0.05) : .now
            if window?.nextEvent(matching: .leftMouseUp, until: until, inMode: .eventTracking, dequeue: true) != nil { return }
            held = NSEvent.pressedMouseButtons & 1 != 0
        } while held
    }

    /// The pointing hand over a view AppKit makes, which HQ can't subclass (the outline's disclosure triangle): a tracking
    /// area whose owner sets the hand.
    func trackHandCursor(for owner: HandCursorOwner) {
        guard !trackingAreas.contains(where: { $0.owner === owner }) else { return }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: owner))
    }

    /// True when the view tracks the hand cursor.
    var tracksHandCursor: Bool {
        trackingAreas.contains { $0.options.contains(.cursorUpdate) && ($0.owner === self || $0.owner is HandCursorOwner) }
    }
}

/// Sets the pointing hand for the views it tracks.
final class HandCursorOwner: NSResponder {
    static let shared = HandCursorOwner()
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
}

/// The system's button look with the pointing hand: the default style under every SwiftUI root HQ shows
/// (`handCursors()`). Buttons with their own style add `clickable()`.
struct HandButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DefaultButtonStyle().makeBody(configuration: configuration).pointerStyle(.link)
    }
}

extension View {
    /// Every default-style button below gets the hand: put it on each SwiftUI root (window, sheet, hosted cell).
    func handCursors() -> some View { buttonStyle(HandButtonStyle()) }
}

extension View {
    /// The pointing hand over a toolbar item. SwiftUI's pointer style there comes late and sticks; AppKit's tracking
    /// follows the toolbar's layout, and leaving gives the arrow back.
    func toolbarClickable() -> some View {
        buttonStyle(.automatic).background(ToolbarHand())
    }
}

struct ToolbarHand: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarHandView { ToolbarHandView() }
    func updateNSView(_ view: ToolbarHandView, context: Context) {}
}

final class ToolbarHandView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Clicks go to the item; only the pointer is tracked here.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}

/// The hand over the chips of a hosted line (a task row's links), from AppKit: SwiftUI's pointer style in a row's hosted
/// view comes and goes as the line rebuilds. It asks `chip(at:)` where the chips are; clicks go through to them.
final class HandRegionView: NSView {
    private let chip: (NSPoint) -> Bool

    init(chip: @escaping (NSPoint) -> Bool) {
        self.chip = chip
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The cursor for a point in window coordinates: the hand over a chip, else the arrow.
    func cursor(at point: NSPoint) -> NSCursor { chip(convert(point, from: nil)) ? .pointingHand : .arrow }

    override func cursorUpdate(with event: NSEvent) { cursor(at: event.locationInWindow).set() }
    override func mouseMoved(with event: NSEvent) { cursor(at: event.locationInWindow).set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}

/// A borderless icon button with the pointing hand: the outline rows' hover actions. It tracks the
/// pointer only while shown, so 500 rows' hidden buttons cost nothing.
final class HandButton: NSButton {
    override var isHidden: Bool { didSet { if isHidden != oldValue { trackHandCursor(!isHidden) } } }

    /// Shown from the start, it tracks too: `isHidden` never changed for it.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        trackHandCursor(window != nil && !isHidden)
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
}
