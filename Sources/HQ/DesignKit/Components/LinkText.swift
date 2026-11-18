import AppKit
import Synchronization
import SwiftUI

/// Rendered text whose links show the pointing hand and open on a click (T-536): SwiftUI's `Text` gives its links no hand.
/// Every markdown text HQ draws in SwiftUI goes through it.
struct LinkText: View {
    let text: AttributedString
    @State private var links = LinkRects()
    @Environment(\.openURL) private var openURL

    init(_ text: AttributedString) { self.text = text }

    var body: some View {
        if text.runs.contains(where: { $0.link != nil }) {
            Self.marked(text)
                .textRenderer(LinkRenderer(links: links))
                .overlay { LinkHands(links: links) { openURL($0) } }
        } else {
            Text(text)
        }
    }

    /// The text with each link's runs marked, so the renderer finds where they land.
    private static func marked(_ text: AttributedString) -> Text {
        text.runs[\.link].reduce(Text(verbatim: "")) { result, run in
            let part = Text(AttributedString(text[run.1]))
            return Text("\(result)\(run.0.map { part.customAttribute(LinkMark(url: $0)) } ?? part)")
        }
    }
}

/// A link's runs in a `LinkText`.
private struct LinkMark: TextAttribute {
    let url: URL
}

/// Where a `LinkText`'s links landed when it last drew, in its own top-left coordinates.
final class LinkRects: Sendable {
    private let parts = Mutex<[(rect: CGRect, url: URL)]>([])

    var all: [(rect: CGRect, url: URL)] { parts.withLock { $0 } }

    func set(_ found: [(rect: CGRect, url: URL)]) { parts.withLock { $0 = found } }
}

/// Draws the text as it is and notes where its links landed.
private struct LinkRenderer: TextRenderer {
    let links: LinkRects

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var found: [(rect: CGRect, url: URL)] = []
        for line in layout {
            for run in line {
                if let mark = run[LinkMark.self] { found.append((run.typographicBounds.rect, mark.url)) }
            }
            context.draw(line)
        }
        links.set(found)
    }
}

private struct LinkHands: NSViewRepresentable {
    let links: LinkRects
    let open: (URL) -> Void

    func makeNSView(context: Context) -> LinkHandView { LinkHandView(links: links, open: open) }

    func updateNSView(_ view: LinkHandView, context: Context) {
        view.links = links
        view.open = open
    }
}

/// Over a `LinkText`: takes the pointer and the click only over a link, the text below gets the rest.
final class LinkHandView: NSView {
    fileprivate var links: LinkRects
    fileprivate var open: (URL) -> Void

    fileprivate init(links: LinkRects, open: @escaping (URL) -> Void) {
        self.links = links
        self.open = open
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    nonisolated override var isFlipped: Bool { true }
    /// Where its links are drawn.
    var handParts: [NSRect] { links.all.map(\.rect) }

    /// The pointing hand over a link, the arrow between: from a tracking area, which follows scrolling.
    private func pointer(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        (handParts.contains { $0.contains(local) } ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    override func cursorUpdate(with event: NSEvent) { pointer(event) }
    override func mouseEntered(with event: NSEvent) { pointer(event) }
    override func mouseMoved(with event: NSEvent) { pointer(event) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return handParts.contains { $0.contains(local) } ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard let url = links.all.first(where: { $0.rect.contains(local) })?.url else { return super.mouseDown(with: event) }
        if event.clickCount == 1 { open(url) }
        takeRelease()
    }
}
