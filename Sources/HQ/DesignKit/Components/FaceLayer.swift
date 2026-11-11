import AppKit
import HQKit
import QuartzCore
import SwiftUI

/// A layer whose changes show at once: no implicit animations.
nonisolated class StillLayer: CALayer {
    override func action(forKey event: String) -> (any CAAction)? { nil }
}

/// A shape layer whose changes show at once.
nonisolated final class StillShapeLayer: CAShapeLayer {
    override func action(forKey event: String) -> (any CAAction)? { nil }
}

/// A face as Core Animation layers, in a flipped view. Still, it's one image; working, its head's parts sway on the
/// render server, so HQ draws nothing per frame.
@MainActor final class FaceLayer: StillLayer {
    private struct Shown: Equatable {
        var spec: FaceSpec
        var size: CGFloat
        var ended: Bool
        var working: Bool
        var scale: CGFloat
    }

    private var shown: Shown?
    private var parts: [FaceArt.Part: StillLayer] = [:]
    /// Grid units drawn around the head's parts: what the sway brings in from outside the face.
    private static let margin: CGFloat = 8
    /// Steps of the sway's keyframes, over one sway.
    private static let steps = 60

    /// A drawing: a whole face (`part` nil) or one of its parts.
    private struct Drawing: Hashable {
        var spec: FaceSpec
        var part: FaceArt.Part?
        var size: CGFloat
        var ended: Bool
        var scale: CGFloat
    }

    /// Faces already drawn: rows and cards show the same few faces again and again.
    private static var drawings: [Drawing: CGImage] = [:]
    private static let drawingsKept = 400

    nonisolated override init() { super.init() }

    nonisolated override init(layer: Any) { super.init(layer: layer) }

    nonisolated required init?(coder: NSCoder) { fatalError() }

    /// Shows the face at `size`, drawn for a `scale` backing.
    func show(_ spec: FaceSpec, size: CGFloat, ended: Bool = false, working: Bool = false, scale: CGFloat) {
        let next = Shown(spec: spec, size: size, ended: ended, working: working && !ended, scale: max(scale, 1))
        guard next != shown else { return }
        shown = next
        contentsScale = next.scale
        if next.working {
            contents = nil
            mask = mask ?? StillShapeLayer()
            (mask as? CAShapeLayer)?.path = FaceArt.squircle(size)
            mask?.frame = CGRect(x: 0, y: 0, width: size, height: size)
            mask?.contentsScale = next.scale
            let unit = size / FaceArt.grid
            for part in FaceArt.Part.allCases {
                let layer = parts[part] ?? StillLayer()
                if parts[part] == nil {
                    parts[part] = layer
                    addSublayer(layer)
                }
                let inset = part.sways ? Self.margin : 0
                let side = size + inset * unit * 2
                layer.frame = CGRect(x: -inset * unit, y: -inset * unit, width: side, height: side)
                layer.contentsScale = next.scale
                layer.contents = Self.drawing(Drawing(spec: spec, part: part, size: size, ended: false, scale: next.scale), side: side) { ctx in
                    FaceArt.draw(part, of: spec, size: size, in: ctx, origin: CGPoint(x: inset, y: inset))
                }
            }
            sway()
        } else {
            for layer in parts.values { layer.removeFromSuperlayer() }
            parts = [:]
            mask = nil
            contents = Self.drawing(Drawing(spec: spec, size: size, ended: ended, scale: next.scale), side: size) { ctx in
                FaceArt.draw(spec, in: ctx, rect: CGRect(x: 0, y: 0, width: size, height: size), ended: ended)
            }
        }
    }

    var isWorking: Bool { shown?.working == true }

    /// Each of the head's parts has its sway.
    var sways: Bool {
        let swaying = parts.filter { $0.key.sways }.values
        return !swaying.isEmpty && swaying.allSatisfy { $0.animation(forKey: "sway") != nil }
    }

    /// Starts the sway again, at the point it has reached by the clock: after the layer left a window, say.
    func resume() {
        if shown?.working == true { sway() }
    }

    /// The head's parts sway from the chin; each face starts at its own point of the sway, as `FaceArt.sway` says.
    private func sway() {
        guard let shown else { return }
        let unit = shown.size / FaceArt.grid
        let center = CGPoint(x: FaceArt.grid / 2, y: FaceArt.grid / 2)
        let values = (0...Self.steps).map { step in
            // The head's motion on the grid, about the layer's center instead of the grid's corner.
            let motion = FaceArt.headMotion(Double(step) / Double(Self.steps))
            let moved = center.applying(motion)
            let transform = CGAffineTransform(a: motion.a, b: motion.b, c: motion.c, d: motion.d,
                                              tx: (moved.x - center.x) * unit, ty: (moved.y - center.y) * unit)
            return NSValue(caTransform3D: CATransform3DMakeAffineTransform(transform))
        }
        for (part, layer) in parts where part.sways {
            let animation = CAKeyframeAnimation(keyPath: "transform")
            animation.values = values
            animation.duration = Motion.faceSway
            animation.repeatCount = .infinity
            animation.preferredFrameRateRange = Motion.faceFrameRate
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - FaceArt.sway(shown.spec, at: .now) * Motion.faceSway
            layer.add(animation, forKey: "sway")
        }
    }

    /// A `side` square drawn on a top-left origin grid, at `scale` pixels per point.
    private static func drawing(_ drawing: Drawing, side: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        if let image = drawings[drawing] { return image }
        guard let image = image(side: side, scale: drawing.scale, draw: draw) else { return nil }
        if drawings.count >= drawingsKept { drawings.removeAll(keepingCapacity: true) }
        drawings[drawing] = image
        return image
    }

    private static func image(side: CGFloat, scale: CGFloat, draw: (CGContext) -> Void) -> CGImage? {
        let pixels = Int((side * scale).rounded(.up))
        guard pixels > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(pixels))
        ctx.scaleBy(x: scale, y: -scale)
        draw(ctx)
        return ctx.makeImage()
    }
}

/// A face in a row of faces (`FaceStackView`): the ring that parts it from the face before, the face, and its badge.
@MainActor final class FaceTile: StillLayer {
    let face = FaceLayer()
    private let ring = StillShapeLayer()
    private let badgeRing = StillShapeLayer()
    private let badge = StillShapeLayer()
    private struct Shown: Equatable {
        var face: FaceStackView.Face
        var origin: CGPoint
        var size: CGFloat
        var ringed: Bool
        var content: CGColor
        var badge: CGColor?
        var scale: CGFloat
    }

    /// What it shows: a row laid out again with nothing new leaves its layers alone.
    private var shown: Shown?

    nonisolated override init() { super.init() }

    nonisolated override init(layer: Any) { super.init(layer: layer) }

    nonisolated required init?(coder: NSCoder) { fatalError() }

    /// `content`: the surface's color, for the rings; `badge`: the badge's color, when it has one.
    func show(_ shown: FaceStackView.Face, at origin: CGPoint, size: CGFloat, ringed: Bool, content: CGColor, badge color: CGColor?, scale: CGFloat) {
        let next = Shown(face: shown, origin: origin, size: size, ringed: ringed, content: content, badge: color, scale: scale)
        guard next != self.shown else { return }
        self.shown = next
        if sublayers == nil { for layer in [ring, face, badgeRing, badge] { addSublayer(layer) } }
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        frame = CGRect(origin: origin, size: rect.size)
        ring.isHidden = !ringed
        ring.path = RoundedRectangle(cornerRadius: (size + 2) * FaceArt.corner, style: .continuous).path(in: rect.insetBy(dx: -1, dy: -1)).cgPath
        ring.fillColor = content
        face.frame = rect
        face.show(shown.spec, size: size, ended: shown.ended, working: shown.working, scale: scale)
        badgeRing.isHidden = color == nil
        badge.isHidden = color == nil
        let side = FaceArt.badgeSide(size)
        let disc = CGRect(x: rect.maxX - side + 2, y: rect.maxY - side + 2, width: side, height: side) // grid: ok drawn mark
        badgeRing.path = CGPath(ellipseIn: disc.insetBy(dx: -2, dy: -2), transform: nil)
        badgeRing.fillColor = content
        badge.path = CGPath(ellipseIn: disc, transform: nil)
        badge.fillColor = color
        for layer in [ring, badgeRing, badge] {
            layer.frame = rect
            layer.contentsScale = scale
        }
    }
}

/// One face for SwiftUI (`SessionFace`): a flipped view around a `FaceLayer`. Clicks go through it.
final class FaceView: NSView {
    let face = FaceLayer()
    private var spec: FaceSpec?
    private var ended = false
    private var working = false

    nonisolated override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(face)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ spec: FaceSpec, ended: Bool, working: Bool) {
        self.spec = spec
        self.ended = ended
        self.working = working
        update()
    }

    override func layout() {
        super.layout()
        update()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        update()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { face.resume() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func update() {
        guard let spec, bounds.width > 0 else { return }
        face.frame = bounds
        face.show(spec, size: min(bounds.width, bounds.height), ended: ended, working: working,
                  scale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }
}
