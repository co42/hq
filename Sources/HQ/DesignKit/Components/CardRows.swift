import AppKit
import SwiftUI

/// A card's rows (DESIGN.md §6): up to `limit` they stand in the card; past it they scroll inside it, `limit` rows tall,
/// under a thin overlay scroll bar, their edges fading where rows go on.
struct CardRows<Content: View>: View {
    let count: Int
    let limit: Int
    let rowHeight: CGFloat
    /// The rows' inset from the card's sides: the scroll bar sits in it, clear of the rows' right columns.
    let inset: CGFloat
    /// Names its scroll for the UI test.
    var name = ""
    @ViewBuilder var content: Content
    @State private var fades = Fades()

    struct Fades: Equatable {
        var top = false
        var bottom = false
    }

    var body: some View {
        if count > limit {
            ScrollView {
                content
                    .padding(.horizontal, inset)
                    .background(OverlayScroller())
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: CGFloat(limit) * rowHeight)
            .onScrollGeometryChange(for: Fades.self) { geometry in
                Fades(top: geometry.visibleRect.minY > 1, bottom: geometry.visibleRect.maxY < geometry.contentSize.height - 1)
            } action: { _, now in fades = now }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [fades.top ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Metric.listFade)
                    Color.black
                    LinearGradient(colors: [.black, fades.bottom ? .clear : .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: Metric.listFade)
                }
            }
            .uiTestAnchor("card-scroll:\(name)")
        } else {
            content.padding(.horizontal, inset)
        }
    }
}

/// Gives the scroll view around it the thin overlay scroll bar whatever the user's setting: a bar shown always would
/// take its width from the rows and break their columns' line with the card beside.
private struct OverlayScroller: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {}

    final class Probe: NSView {
        private var watch: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            if window == nil, let watch {
                NotificationCenter.default.removeObserver(watch)
                self.watch = nil
            }
            guard window != nil, watch == nil else { return }
            // The scroll view takes the system's style when the setting changes: the overlay comes back after it.
            watch = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil,
                                                           queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { DispatchQueue.main.async { self?.apply() } }
            }
        }

        private func apply() {
            guard let scroll = enclosingScrollView, scroll.scrollerStyle != .overlay else { return }
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
        }
    }
}
