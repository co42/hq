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

/// The window's background behind a pinned header, from the window's top to under the header, fading at its foot: what
/// scrolls under it goes, the sky stays where it is.
private struct PinBand: View {
    let line: PinLine
    let height: CGFloat

    var body: some View {
        let fade = Space.md
        ZStack(alignment: .top) {
            Ink.content
            SkyView(mood: line.mood)
        }
        .frame(width: line.width, height: line.bar + height + fade, alignment: .top)
        .clipped()
        .mask {
            VStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: fade)
            }
        }
        .offset(x: -line.inset, y: -line.bar) // grid: ok back to the window's top left
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
