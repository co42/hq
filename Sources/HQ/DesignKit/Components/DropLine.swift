import AppKit

/// Where a dragged item lands between cards (DESIGN.md §5, §7): an accent line with a ring at its start, across a gap or
/// upright in one. The ring's outer edge is at `from`, the line ends at `to`.
struct DropLine: Equatable {
    var from: CGPoint
    var to: CGPoint

    init(from: CGPoint, to: CGPoint) {
        self.from = from
        self.to = to
    }

    /// Across a rect, at its middle: the outline's line.
    init(across rect: CGRect) {
        self.init(from: CGPoint(x: rect.minX, y: rect.midY), to: CGPoint(x: rect.maxX, y: rect.midY))
    }
}

/// Draws a drop line over everything in its view; nil hides it.
final class DropLineLayer: CAShapeLayer {
    private(set) var line: DropLine?

    nonisolated override init() {
        super.init()
        zPosition = 1_000_000
        lineCap = .round
        isHidden = true
    }

    nonisolated override init(layer: Any) { super.init(layer: layer) }

    nonisolated required init?(coder: NSCoder) { fatalError() }

    func show(_ line: DropLine?, in appearance: NSAppearance) {
        self.line = line
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        isHidden = line == nil
        if let line {
            lineWidth = Metric.selectionRing
            let ring = Space.sm
            let dx = line.to.x - line.from.x, dy = line.to.y - line.from.y
            let length = max(hypot(dx, dy), 1)
            let unit = CGPoint(x: dx / length, y: dy / length)
            let center = CGPoint(x: line.from.x + unit.x * ring / 2, y: line.from.y + unit.y * ring / 2)
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: center.x - ring / 2, y: center.y - ring / 2, width: ring, height: ring))
            path.move(to: CGPoint(x: line.from.x + unit.x * ring, y: line.from.y + unit.y * ring))
            path.addLine(to: line.to)
            self.path = path
            appearance.performAsCurrentDrawingAppearance {
                strokeColor = Ink.accentNS.cgColor
                fillColor = Ink.surfaceNS.cgColor
            }
        }
        CATransaction.commit()
    }
}

/// A view that shows a drop line over the views under it, past its own edges too, and takes no clicks.
final class DropLineView: NSView {
    private let drawn = DropLineLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(drawn)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    nonisolated override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The line shown, in this view's coordinates.
    var line: DropLine? { drawn.line }

    func show(_ line: DropLine?) {
        guard line != drawn.line else { return }
        drawn.show(line, in: effectiveAppearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let line = drawn.line { drawn.show(line, in: effectiveAppearance) }
    }
}
