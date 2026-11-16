import AppKit
import SwiftUI

/// What the sky says: nothing waits, something is new, or something needs the user.
enum SkyMood: Hashable {
    case calm, news, needsYou
}

/// A raised card (DESIGN.md §12): the surface fill, a hairline, a contact shadow and a soft far one.
/// `glow` makes it shine in a color instead (needs the user, failed, new), breathing while `breathing`;
/// `lifted` deepens the shadow under the pointer.
struct SurfaceModifier: ViewModifier {
    var radius: CGFloat = Radius.card
    var glow: Color?
    var breathing = false
    var lifted = false
    /// A tint over the surface: selection, a drop target.
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                SurfaceBody(shape: shape, glow: glow, breathing: breathing, lifted: lifted, tint: tint)
            }
            .overlay {
                shape.strokeBorder(glow.map { AnyShapeStyle($0.opacity(0.55)) } ?? AnyShapeStyle(Ink.cardHairline), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct SurfaceBody: View {
    let shape: RoundedRectangle
    let glow: Color?
    let breathing: Bool
    let lifted: Bool
    let tint: Color?

    /// The glow held once the user looked, and its peak while it breathes.
    private static let hold = 0.2
    private static let peak = 0.5

    var body: some View {
        if let glow, breathing {
            // The breath crossfades on the render server from the glow held to the glow at its peak.
            ZStack {
                base(glow).shadow(color: glow.opacity(Self.hold), radius: Metric.glowRadius)
                BreathingGlow(peak: AnyView(base(glow).shadow(color: glow.opacity(Self.peak), radius: Metric.glowRadius)))
            }
        } else if let glow {
            base(glow).shadow(color: glow.opacity(Self.hold), radius: Metric.glowRadius)
        } else {
            base(nil)
        }
    }

    private func base(_ glow: Color?) -> some View {
        ZStack {
            shape.fill(Ink.card)
                .shadow(color: Ink.shadowNear, radius: Metric.shadowNearRadius, y: Metric.shadowNearY)
                .shadow(color: lifted ? Ink.shadowLifted : Ink.shadowFar,
                        radius: lifted ? Metric.shadowLiftRadius : Metric.shadowFarRadius,
                        y: lifted ? Metric.shadowLiftY : Metric.shadowFarY)
            if let glow { shape.fill(glow.opacity(0.07)) }
            if let tint { shape.fill(tint) }
        }
        .animation(Motion.lift, value: lifted)
    }
}

/// The surface at its peak glow, drawn by SwiftUI in its own view, whose opacity Core Animation moves over the surface below.
struct BreathingGlow: NSViewRepresentable {
    let peak: AnyView

    func makeNSView(context: Context) -> BreathingView { BreathingView() }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BreathingView, context: Context) -> CGSize? { proposal.replacingUnspecifiedDimensions() }

    func updateNSView(_ view: BreathingView, context: Context) {
        view.show(AnyView(peak.environment(\.colorScheme, context.environment.colorScheme)))
    }
}

final class BreathingView: NSView {
    /// How far the glow reaches past the surface.
    static var spread: CGFloat { Metric.glowRadius * 4 }
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    nonisolated override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        host.sizingOptions = []
        addSubview(host)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Drawn, and breathing.
    var breathes: Bool { host.layer?.animation(forKey: "breathe") != nil }

    func show(_ peak: AnyView) {
        host.rootView = AnyView(peak.padding(Self.spread))
    }

    override func layout() {
        super.layout()
        host.frame = bounds.insetBy(dx: -Self.spread, dy: -Self.spread)
        if !breathes { breathe() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { breathe() }
    }

    /// From the glow held (none of this view) to its peak and back, eased as SwiftUI eases.
    private func breathe() {
        guard let layer = host.layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = Motion.blinkHalf
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "breathe")
    }
}

extension View {
    /// Sits the view on a raised card.
    func surface(radius: CGFloat = Radius.card, glow: Color? = nil, breathing: Bool = false, lifted: Bool = false, tint: Color? = nil) -> some View {
        modifier(SurfaceModifier(radius: radius, glow: glow, breathing: breathing, lifted: lifted, tint: tint))
    }

    /// A card in a list, selected as a task's card: a 2 pt accent ring and a faint accent tint while its list has the
    /// keyboard, gray without the ring otherwise (T-458).
    func listCard(selected: Bool, active: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return padding(Metric.cardPadding)
            .surface(tint: selected ? (active ? Color(nsColor: Ink.cardSelectionNS) : Ink.selectionInactive) : nil)
            .overlay { if selected && active { shape.strokeBorder(Ink.accent, lineWidth: Metric.selectionRing).allowsHitTesting(false) } }
            .contentShape(shape)
    }
}

/// A card's own toggle, as a task card's description button: the accent on a faint accent tile while on (T-458).
struct CardToggle: View {
    let icon: KitIcon
    let on: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon.image
                .fontWeight(.semibold)
                .foregroundStyle(on ? AnyShapeStyle(Ink.accent) : AnyShapeStyle(.secondary))
                .frame(width: Metric.rowAction, height: Metric.rowAction)
                .background(on ? Color(nsColor: Ink.markOnNS) : .clear, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickable()
        .help(help)
        .accessibilityLabel(on ? "Show Less" : "Show More")
    }
}

/// The soft sky over the top of the page: a mesh of three colors that fades into the canvas.
/// Its colors follow the day's state and change slowly; it never loops. The toolbar's and the
/// section bar's glass refract it. Drawn once per mood on the CPU and stretched: SwiftUI's own rendering
/// of a mesh wakes its GPU renderer, which holds a lot of memory for seconds.
struct SkyView: View {
    let mood: SkyMood
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        SkyImage(sky: SkyLayerView.Sky(mood: mood, scheme: scheme, contrast: contrast))
            .frame(height: Metric.skyHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The mesh, filling whatever frame it gets: its points are fractions of it.
    static func mesh(_ mood: SkyMood, _ scheme: ColorScheme) -> some View {
        let colors = Ink.sky(mood)
        let top = Ink.skyOpacity(scheme)
        return MeshGradient( // perf: ok drawn once per mood on the CPU (SkyLayerView)
            width: 3, height: 3, // grid: ok mesh points, not points on screen
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.6, 0.45], [1, 0.55],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                colors[0].opacity(top), colors[1].opacity(top * 0.75), colors[2].opacity(top),
                colors[1].opacity(top * 0.4), colors[2].opacity(top * 0.3), colors[0].opacity(top * 0.4),
                colors[2].opacity(0), colors[0].opacity(0), colors[1].opacity(0),
            ]
        )
    }
}

private struct SkyImage: NSViewRepresentable {
    let sky: SkyLayerView.Sky

    func makeNSView(context: Context) -> SkyLayerView { SkyLayerView() }

    func updateNSView(_ view: SkyLayerView, context: Context) { view.show(sky) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SkyLayerView, context: Context) -> CGSize? { proposal.replacingUnspecifiedDimensions() }
}

final class SkyLayerView: NSView {
    struct Sky: Hashable {
        var mood: SkyMood
        var scheme: ColorScheme
        var contrast: ColorSchemeContrast
    }

    private var sky: Sky?
    private var shown: Sky?
    /// One drawing per mood and appearance, at one pixel per point of a wide page: smooth enough to stretch.
    private static var drawings: [Sky: CGImage] = [:]
    private static let drawn = CGSize(width: 1504, height: 420)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setAccessibilityElement(false)
        NotificationCenter.default.addObserver(self, selector: #selector(colorsChanged), name: NSColor.systemColorsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ sky: Sky) {
        guard sky != self.sky else { return }
        self.sky = sky
        needsDisplay = true
    }

    /// The accent color changed: the calm sky is in it.
    @objc private func colorsChanged() {
        Self.drawings = [:]
        shown = nil
        needsDisplay = true
    }

    override func updateLayer() {
        guard let layer, let sky, sky != shown else { return }
        layer.contentsGravity = .resize
        // A new mood fades in slowly, as the day changes; the first one shows at once.
        if shown != nil, !Motion.still {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Motion.skySeconds
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "mood")
        }
        shown = sky
        layer.contents = Self.drawing(sky, appearance: effectiveAppearance)
    }

    private static func drawing(_ sky: Sky, appearance: NSAppearance) -> CGImage? {
        if let image = drawings[sky] { return image }
        var image: CGImage?
        appearance.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: SkyView.mesh(sky.mood, sky.scheme).frame(width: drawn.width, height: drawn.height) // perf: ok into a CGContext
                .environment(\.colorScheme, sky.scheme))
            // Drawn into a bitmap: Core Graphics draws the mesh as SwiftUI does on screen, without the GPU.
            renderer.render { size, draw in
                guard let space = CGColorSpace(name: CGColorSpace.displayP3),
                      let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                draw(ctx)
                image = ctx.makeImage()
            }
        }
        if let image { drawings[sky] = image }
        return image
    }
}

/// A row's kind as a small tile: a white glyph on the kind's color (a PR's state, a file, an artifact).
struct KindTile: View {
    let icon: KitIcon
    let tint: Color

    var body: some View {
        icon.image
            .font(.system(size: Metric.kindTile * 0.5, weight: .bold))
            .foregroundStyle(Ink.onTile)
            .frame(width: Metric.kindTile, height: Metric.kindTile)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: Radius.kindTile, style: .continuous))
    }
}

/// A section's symbol on a small tinted tile, as Reminders and Things mark their lists.
struct SectionTile: View {
    let icon: KitIcon
    let tint: Color

    var body: some View {
        icon.image
            .font(.system(size: Metric.sectionTile * 0.5, weight: .semibold))
            .foregroundStyle(Ink.onTile)
            .frame(width: Metric.sectionTile, height: Metric.sectionTile)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One shape behind the outline's rows: a raised card, a done task's flat card, or a block's tray.
struct CardShape: Equatable {
    /// `newTask`: the card a new task is typed in, its edge dashed until it is one (2026-11-10).
    enum Kind: Equatable { case card, flat, tray, newTask }
    /// A Blocked card's red edge; a selected card's accent ring, as a session card's; the card a dragged task would drop
    /// onto (2026-11-10).
    enum Ring: Equatable { case blocked, selected, drop }

    var rect: CGRect
    var radius: CGFloat
    var kind: Kind = .card
    var ring: Ring?
    /// What its layers are kept by: a card that moves keeps its own and slides, no other card takes them.
    var key = ""
    /// Unrelated to the selected tasks: faded (2026-11-10).
    var dimmed = false
}

/// Raised cards in AppKit, as Core Animation layers (DESIGN.md §12): the surface, its hairline, a contact and a far
/// shadow, the same as `surface()`; and the outline's trays and flat cards. The GPU draws them, so a view that scrolls
/// over them redraws nothing (T-337).
final class CardsView: NSView {
    private var cards: [String: (body: CALayer, far: CALayer)] = [:]
    private(set) var shapes: [CardShape] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    nonisolated override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// One raised card per rect, in this view's coordinates.
    func show(_ rects: [CGRect]) {
        show(rects.map { CardShape(rect: $0, radius: Radius.card) })
    }

    /// The shapes, each on the layers it had: `animated`, they slide and fade with the rows around them; new ones fade in.
    func show(_ shapes: [CardShape], animated: Bool = false) {
        let keyed = shapes.enumerated().map { index, shape in shape.key.isEmpty ? "#\(index)" : shape.key }
        guard shapes != self.shapes || Set(keyed) != Set(cards.keys) else { return }
        self.shapes = shapes
        CATransaction.begin()
        if animated, !Motion.still {
            CATransaction.setAnimationDuration(Motion.rowsSeconds)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        for (index, (key, shape)) in zip(keyed, shapes).enumerated() {
            let fresh = cards[key] == nil
            let card = cards[key] ?? (body: CALayer(), far: CALayer())
            if fresh {
                cards[key] = card
                layer?.addSublayer(card.far)
                layer?.addSublayer(card.body)
            }
            let path = CGPath(roundedRect: CGRect(origin: .zero, size: shape.rect.size), cornerWidth: shape.radius, cornerHeight: shape.radius, transform: nil)
            CATransaction.begin()
            // A new card starts where it lands; only its fade shows.
            if fresh { CATransaction.setDisableActions(true) }
            for (offset, part) in [card.far, card.body].enumerated() {
                part.zPosition = CGFloat(index * 2 + offset)
                part.frame = shape.rect
                part.shadowPath = path
                part.cornerRadius = shape.radius
                part.cornerCurve = .continuous
                if fresh, animated { part.opacity = 0 }
            }
            card.far.shadowRadius = Metric.shadowFarRadius
            card.far.shadowOffset = CGSize(width: 0, height: Metric.shadowFarY)
            card.body.shadowRadius = Metric.shadowNearRadius
            card.body.shadowOffset = CGSize(width: 0, height: Metric.shadowNearY)
            card.body.borderWidth = shape.ring == .selected || shape.ring == .drop ? Metric.selectionRing : shape.ring == .blocked ? 1.5 : shape.kind == .newTask ? 0 : 1
            dash(card.body, shape, key)
            CATransaction.commit()
            let opacity: Float = shape.dimmed ? Float(Motion.dimmedOpacity) : 1
            if card.body.opacity != opacity || fresh {
                // Dimming fades on its own, also when the rows don't move.
                CATransaction.begin()
                // A card that just came in without the rows moving shows at once.
                CATransaction.setDisableActions((fresh && !animated) || Motion.still)
                if !animated { CATransaction.setAnimationDuration(Motion.appearSeconds) }
                card.body.opacity = opacity
                card.far.opacity = opacity
                CATransaction.commit()
            }
        }
        for (key, card) in cards where !keyed.contains(key) {
            dashes[key]?.removeFromSuperlayer()
            dashes[key] = nil
            card.body.removeFromSuperlayer()
            card.far.removeFromSuperlayer()
            cards[key] = nil
        }
        CATransaction.commit()
        paint()
    }

    /// The dashed edges of new-task cards, by key.
    private var dashes: [String: CAShapeLayer] = [:]

    /// A new-task card's dashed edge, inside its body; gone once it has a ring or is another kind.
    private func dash(_ body: CALayer, _ shape: CardShape, _ key: String) {
        guard shape.kind == .newTask, shape.ring == nil else {
            dashes[key]?.removeFromSuperlayer()
            dashes[key] = nil
            return
        }
        let line = dashes[key] ?? CAShapeLayer()
        if dashes[key] == nil {
            dashes[key] = line
            body.addSublayer(line)
        }
        line.frame = CGRect(origin: .zero, size: shape.rect.size)
        line.path = CGPath(roundedRect: line.frame.insetBy(dx: 0.5, dy: 0.5), cornerWidth: shape.radius, cornerHeight: shape.radius, transform: nil)
        line.lineWidth = 1
        line.lineDashPattern = Metric.newCardDash.map { NSNumber(value: Double($0)) }
        line.fillColor = nil
    }

    /// Where a dragged task would land between cards: an accent line with a ring at its start, over the cards
    /// (2026-11-10: the cards hold still under a drag). Nil hides it.
    private(set) var dropLine: CGRect?
    private lazy var dropLayer: DropLineLayer = {
        let line = DropLineLayer()
        layer?.addSublayer(line)
        return line
    }()

    func showDropLine(_ rect: CGRect?) {
        guard rect != dropLine else { return }
        dropLine = rect
        dropLayer.show(rect.map(DropLine.init(across:)), in: effectiveAppearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    /// The colors in this view's appearance.
    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (index, shape) in shapes.enumerated() {
                guard let card = cards[shape.key.isEmpty ? "#\(index)" : shape.key] else { continue }
                let raised = shape.kind == .card
                card.far.shadowColor = Ink.shadowFarNS.cgColor
                card.far.shadowOpacity = raised ? 1 : 0
                card.body.backgroundColor = (shape.ring == .drop ? Ink.dropCardNS : shape.kind == .tray ? Ink.trayNS : shape.kind == .flat ? Ink.doneCardNS : shape.kind == .newTask && shape.ring == nil ? .clear : Ink.surfaceNS).cgColor
                dashes[shape.key.isEmpty ? "#\(index)" : shape.key]?.strokeColor = Ink.newCardLineNS.cgColor
                card.body.borderColor = (shape.ring == .selected || shape.ring == .drop ? Ink.accentNS : shape.ring == .blocked ? Ink.blockedRingNS : Ink.cardHairlineNS).cgColor
                card.body.shadowColor = Ink.shadowNearNS.cgColor
                card.body.shadowOpacity = raised ? 1 : 0
            }
        }
        CATransaction.commit()
    }
}
