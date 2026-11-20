import SwiftUI

/// Where a section's header pins while its section scrolls under the toolbar (DESIGN.md §4).
struct PinLine: Equatable {
    /// The toolbar's height over the page: a pinned header sits right under it, at the scroll view's visible top.
    var bar: CGFloat
    /// The column's leading inset and the scroll view's width: the band behind a pinned header spans the window.
    var inset: CGFloat
    var width: CGFloat
    /// The space between sections: the next header pushes this one away as it arrives.
    var gap: CGFloat
    var mood: SkyMood
}

extension EnvironmentValues {
    @Entry var pinLine: PinLine?
    /// The height of the section whose header reads it.
    @Entry var pinSpan: CGFloat = 0
    /// Its header is pinned under the toolbar: it draws slimmer.
    @Entry var headerPinned = false
}

/// Some section's header is pinned: the page hides the toolbar's own edge, the band's hairline is the one line (T-644).
struct HeaderPinnedKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    /// A section whose header pins: tells the header how far it may follow.
    func pinsItsHeader() -> some View { modifier(PinnedSection()) }

    /// Pins under the toolbar while its section scrolls past, on the window's own sky and canvas.
    func pinsWhileScrolling() -> some View { modifier(PinnedHeader()) }
}

private struct PinnedSection: ViewModifier {
    @State private var span: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.pinSpan, span)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { span = $0 }
    }
}

private struct PinnedHeader: ViewModifier {
    @Environment(\.pinLine) private var line
    @Environment(\.pinSpan) private var span
    /// Above the line: its band shows. Changes only when it crosses, so scrolling redraws nothing.
    @State private var pinned = false

    func body(content: Content) -> some View {
        if let line {
            content
                .environment(\.headerPinned, pinned)
                .preference(key: HeaderPinnedKey.self, value: pinned)
                .background(alignment: .top) {
                    if pinned {
                        GeometryReader { header in PinBand(line: line, height: header.size.height) }
                            .transition(.opacity.animation(Motion.hover))
                    }
                }
                .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).minY < 0.5 } action: { pinned = $0 }
                // Per frame on the render side: the header follows the line, then leaves with its section's end.
                .visualEffect { [span] content, proxy in
                    let top = proxy.frame(in: .scrollView).minY
                    let reach = max(0, span + line.gap - proxy.size.height)
                    return content.offset(y: min(max(0, -top), reach)) // grid: ok follows the scroll
                }
                .zIndex(1)
        } else {
            content
        }
    }
}

/// The window's background behind a pinned header, from the window's top to just under the header: the toolbar and the
/// header read as one band, with one hairline at its foot (T-644). What scrolls under it goes, the sky stays where it is.
private struct PinBand: View {
    let line: PinLine
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Ink.content
            SkyView(mood: line.mood)
        }
        .frame(width: line.width, height: line.bar + height + Space.xs, alignment: .top)
        .clipped()
        .overlay(alignment: .bottom) { Ink.cardHairline.frame(height: Metric.tableRule) }
        .offset(x: -line.inset, y: -line.bar) // grid: ok back to the window's top left
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
