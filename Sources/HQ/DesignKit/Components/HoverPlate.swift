import AppKit
import SwiftUI

/// A hover plate's shape: the control's own (DESIGN.md §12, Hover).
nonisolated enum PlateShape: Equatable {
    case capsule
    case circle
    /// A rounded square, its radius the plate's own: the control's plus the outset, concentric with it.
    case rounded(CGFloat)

    /// Keys, link icons, chevrons and a card's toggles.
    static var chip: PlateShape { .rounded(Radius.chip) }

    /// A face's squircle, `Metric.plateOutset` around it.
    @MainActor static func face(_ side: CGFloat) -> PlateShape { .rounded(side * FaceArt.corner + Metric.plateOutset) }

    func radius(_ size: CGSize) -> CGFloat {
        let half = min(size.width, size.height) / 2
        return switch self {
        case .capsule, .circle: half
        case .rounded(let radius): min(radius, half)
        }
    }
}

/// The plate under the pointer on a small control (DESIGN.md §12, Hover): the spot under the pointer filled in its
/// shape, `Ink.plate`, deeper while pressed. It lets every click through. An AppKit cell owns one under its controls and
/// gives it a spot per control; under a SwiftUI control (`.hoverPlate()`, `PlateButtonStyle`) it only tracks, SwiftUI draws.
final class HoverPlateView: NSView {
    struct Spot: Equatable {
        var rect: NSRect
        var shape: PlateShape

        /// The spot of `control`, a subview of the plate's superview, `outset` around it; nil while it's hidden.
        @MainActor static func around(_ control: NSView, in plate: HoverPlateView, _ shape: PlateShape, outset: CGSize = .zero) -> Spot? {
            guard !control.isHidden, control.alphaValue > 0, let superview = control.superview else { return nil }
            let rect = plate.convert(control.frame, from: superview).insetBy(dx: -outset.width, dy: -outset.height)
            return rect.isEmpty ? nil : Spot(rect: rect, shape: shape)
        }
    }

    /// Every plate in a window, for the UI test.
    static let all = NSHashTable<HoverPlateView>.weakObjects()

    var spots: [Spot] = [] { didSet { if spots != oldValue { refresh() } } }
    /// A SwiftUI control's: one spot, the whole view.
    var shape: PlateShape? { didSet { if shape != oldValue { needsLayout = true } } }
    var pressed = false { didSet { if pressed != oldValue { refresh() } } }
    /// The spot under the pointer.
    private(set) var hovered: Int?
    /// A SwiftUI control's tracker: it draws nothing (a view inside glass draws black), says when the pointer is over it,
    /// and hears back whether SwiftUI shows its plate, pressed or not.
    var onHover: ((Bool) -> Void)?
    var drawn: Bool?
    private let plate = CALayer()

    nonisolated override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        plate.cornerCurve = .continuous
        plate.opacity = 0
        // It shows where the pointer is: only its fade and its color move.
        plate.actions = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull()]
        layer?.addSublayer(plate)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
        setAccessibilityElement(false)
        Self.all.add(self)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { pointer(at: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { pointer(at: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { pointer(at: nil) }

    /// The pointer at a point of the window, or gone: the spot under it shows its plate.
    func pointer(at point: NSPoint?) {
        let local = point.map { convert($0, from: nil) }
        let index = local.flatMap { point in spots.lastIndex { $0.rect.contains(point) } }
        guard index != hovered else { return }
        hovered = index
        if let onHover { onHover(index != nil) } else { refresh() }
    }

    /// The spot shown and whether it's pressed, in window coordinates, and its fill: what the UI test reads.
    var shown: (rect: NSRect, radius: CGFloat, pressed: Bool, color: CGColor?)? {
        if onHover != nil {
            guard let drawn, window != nil, let shape else { return nil }
            return (convert(bounds, to: nil), shape.radius(bounds.size), drawn, fill(pressed: drawn))
        }
        guard plate.opacity > 0, window != nil, plate.frame.width > 0 else { return nil }
        return (convert(plate.frame, to: nil), plate.cornerRadius, pressed, plate.backgroundColor)
    }

    /// The fill a plate shows here, at rest or pressed, for the UI test to compare.
    func fill(pressed: Bool) -> CGColor? {
        var color: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance { color = (pressed ? Ink.platePressedNS : Ink.plateNS).cgColor }
        return color
    }

    /// Its spots in window coordinates, for the UI test to find the plate under an anchor.
    var windowSpots: [NSRect] { spots.map { convert($0.rect, to: nil) } }

    override func layout() {
        super.layout()
        if let shape { spots = [Spot(rect: bounds, shape: shape)] }
    }

    /// Runs a control's press with its plate deeper: the plate beside it or in a view holding it.
    static func pressing(_ control: NSView, _ press: () -> Void) {
        var view: NSView? = control
        var plate: HoverPlateView?
        for _ in 0..<3 where plate == nil {
            plate = view?.subviews.lazy.compactMap { $0 as? HoverPlateView }.first
            view = view?.superview
        }
        plate?.pressed = true
        press()
        plate?.pressed = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        guard onHover == nil else { return }
        let spot = hovered.flatMap { spots.indices.contains($0) ? spots[$0] : nil }
        CATransaction.begin()
        CATransaction.setAnimationDuration(Motion.hoverSeconds)
        if let spot {
            plate.frame = spot.rect
            plate.cornerRadius = spot.shape.radius(spot.rect.size)
            plate.backgroundColor = fill(pressed: pressed)
        }
        plate.opacity = spot == nil ? 0 : 1
        CATransaction.commit()
    }
}

/// An AppKit button whose plate deepens while it's held.
final class PlateButton: NSButton {
    override func mouseDown(with event: NSEvent) {
        HoverPlateView.pressing(self) { super.mouseDown(with: event) }
    }
}

/// A SwiftUI control's plate, drawn by SwiftUI over a tracker that tells it where the pointer is.
private struct PlateBacking: View {
    let shape: PlateShape
    let pressed: Bool
    @State private var hovering = false
    @Environment(\.forcedPartState) private var forced

    var body: some View {
        let pressed = pressed || forced == .pressed
        let shown = hovering || pressed || forced == .hover
        PlateFill(shape: shape)
            .fill(Color(nsColor: pressed ? Ink.platePressedNS : Ink.plateNS))
            .opacity(shown ? 1 : 0)
            .animation(Motion.hover, value: shown)
            .animation(Motion.hover, value: pressed)
            .background(PlateTracker(shape: shape, drawn: shown ? pressed : nil) { hovering = $0 })
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

nonisolated private struct PlateFill: Shape {
    let shape: PlateShape

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: shape.radius(rect.size), style: .continuous).path(in: rect)
    }
}

private struct PlateTracker: NSViewRepresentable {
    let shape: PlateShape
    let drawn: Bool?
    let hover: (Bool) -> Void

    func makeNSView(context: Context) -> HoverPlateView { HoverPlateView() }

    func updateNSView(_ view: HoverPlateView, context: Context) {
        view.onHover = hover
        view.shape = shape
        view.drawn = drawn
    }
}

extension View {
    /// A plate under the pointer in `shape`, `outset` outside the control so nothing moves (DESIGN.md §12, Hover).
    /// `over`: on a control that fills itself opaquely (a prominent glass button), the plate tints it from above.
    /// `shown` false: none, where a click doesn't act on it.
    func hoverPlate(_ shape: PlateShape, outset: CGSize = .zero, pressed: Bool = false, over: Bool = false, shown: Bool = true) -> some View {
        let plate = PlateBacking(shape: shape, pressed: pressed)
            .padding(.horizontal, -outset.width)
            .padding(.vertical, -outset.height)
        return background { if shown && !over { plate } }
            .overlay { if shown && over { plate } }
    }

    /// A face's plate: its squircle, `Metric.plateOutset` around it.
    func facePlate(_ side: CGFloat) -> some View {
        hoverPlate(.face(side), outset: CGSize(width: Metric.plateOutset, height: Metric.plateOutset))
    }
}

/// A plain button with a hover plate in `shape`, deeper while pressed.
struct PlateButtonStyle: ButtonStyle {
    var shape: PlateShape = .chip
    var outset: CGSize = .zero

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .hoverPlate(shape, outset: outset, pressed: configuration.isPressed)
    }
}
