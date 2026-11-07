import AppKit
import SwiftUI

// The pointing hand over everything a click acts on (DESIGN.md §12 Pointer).

extension View {
    /// The pointing hand over an icon, a face or a chip that SwiftUI draws itself.
    func clickable() -> some View { pointerStyle(.link) }
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
    /// get it. A menu's tracking may have taken it already; a button still held waits for it.
    func takeRelease() {
        let held = NSEvent.pressedMouseButtons & 1 != 0
        _ = window?.nextEvent(matching: .leftMouseUp, until: held ? .distantFuture : .now, inMode: .eventTracking, dequeue: true)
    }

    /// True when the view tracks the hand cursor.
    var tracksHandCursor: Bool {
        trackingAreas.contains { $0.options.contains(.cursorUpdate) && $0.owner === self }
    }
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

/// A borderless icon button with the pointing hand: the outline rows' hover actions. It tracks the
/// pointer only while shown, so 500 rows' hidden buttons cost nothing.
final class HandButton: NSButton {
    override var isHidden: Bool { didSet { if isHidden != oldValue { trackHandCursor(!isHidden) } } }

    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
}
