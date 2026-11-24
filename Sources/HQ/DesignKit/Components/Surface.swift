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
    /// A faint light from its leading side while state light is on (Settings › Appearance): a working session.
    var wash: Color?
    /// Never frosted: a bar that floats over rows.
    var solid = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                SurfaceBody(shape: shape, glow: glow, breathing: breathing, lifted: lifted, tint: tint, wash: wash, solid: solid)
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
    let wash: Color?
    let solid: Bool

    /// The glow held once the user looked, and its peak while it breathes.
    private static let hold = 0.2
    private static let peak = 0.5

    var body: some View {
        let light = Look.shared.stateLight ? Look.shared.stateStrength : nil
        if let glow, breathing {
            // The breath crossfades on the render server from the glow held to the glow at its peak.
            ZStack {
                halo(base(glow, light), glow, Self.hold, light)
                BreathingGlow(peak: AnyView(halo(base(glow, light), glow, Self.peak, light)))
            }
        } else if let glow {
            halo(base(glow, light), glow, Self.hold, light)
        } else {
            base(nil, light)
        }
    }

    /// The glow around the card; with state light, stronger and fallen a little below it, as light on the page.
    private func halo(_ card: some View, _ glow: Color, _ strength: Double, _ light: Double?) -> some View {
        card.shadow(color: glow.opacity(min(1, strength * (light.map { 1.4 * $0 } ?? 1))),
                    radius: light == nil ? Metric.glowRadius : Metric.glowRadius * 1.4,
                    y: light == nil ? 0 : Metric.glowFall)
    }

    private func base(_ glow: Color?, _ light: Double?) -> some View {
        let look = Look.shared
        let opacity = solid ? 1 : look.cardOpacity
        return ZStack {
            shadows(look.lit, frosted: opacity < 1)
            if opacity < 1 { shape.fill(Ink.card.opacity(opacity)) }
            if let lit = look.lit {
                // The light falls down its fill, and catches its top edge just inside the hairline.
                shape.fill(LinearGradient(colors: [Ink.fallTop.opacity(min(1, lit)), Ink.fallBottom.opacity(min(1, lit))], startPoint: .top, endPoint: .bottom))
                shape.inset(by: 1).strokeBorder(LinearGradient(stops: [
                    .init(color: Ink.rim.opacity(min(1, 0.8 * lit)), location: 0),
                    .init(color: Ink.rim.opacity(0), location: 0.3),
                ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            if let glow {
                if let light { shape.fill(Self.lit(glow, light, reach: 0.8)) } else { shape.fill(glow.opacity(0.07)) }
            } else if let wash, look.workingLight {
                // The working light: as the light of a card that needs the user, without its glow.
                shape.fill(Self.lit(wash, look.workingStrength, reach: 0.8))
            }
            if let tint { shape.fill(tint) }
        }
        .animation(Motion.lift, value: lifted)
    }

    /// The card's fill with its contact and far shadows; frosted, the shadows only, cut out under the card so the sky
    /// shows through it clean.
    @ViewBuilder private func shadows(_ lit: Double?, frosted: Bool) -> some View {
        let far = lifted ? Ink.shadowLifted : lit.map { Ink.shadowLit.opacity(min(1, $0)) } ?? Ink.shadowFar
        let radius = lifted ? Metric.shadowLiftRadius : lit == nil ? Metric.shadowFarRadius : Metric.shadowLitRadius
        let y = lifted ? Metric.shadowLiftY : lit == nil ? Metric.shadowFarY : Metric.shadowLitY
        let casting = shape.fill(Ink.card)
            .shadow(color: Ink.shadowNear, radius: Metric.shadowNearRadius, y: Metric.shadowNearY)
            .shadow(color: far, radius: radius, y: y)
            .animation(Motion.lift, value: lifted)
        if frosted {
            ZStack {
                casting
                shape.fill(.black).blendMode(.destinationOut)
            }
            .compositingGroup()
        } else {
            casting
        }
    }

    /// Light from the card's leading side, where its face is, fading across it.
    private static func lit(_ color: Color, _ strength: Double, reach: Double) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: color.opacity(min(1, 0.22 * strength)), location: 0),
            .init(color: color.opacity(min(1, 0.07 * strength)), location: reach * 0.55),
            .init(color: color.opacity(0), location: reach),
        ], startPoint: .leading, endPoint: .trailing)
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
    func surface(radius: CGFloat = Radius.card, glow: Color? = nil, breathing: Bool = false, lifted: Bool = false, tint: Color? = nil, wash: Color? = nil, solid: Bool = false) -> some View {
        modifier(SurfaceModifier(radius: radius, glow: glow, breathing: breathing, lifted: lifted, tint: tint, wash: wash, solid: solid))
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
        .buttonStyle(PlateButtonStyle(shape: .chip))
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
    /// The band at the top of the page, or the glow at the window's foot (Settings › Appearance).
    var part: SkyPart = .top
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let look = Look.shared
        if look.sky == .topAndBottom || look.sky == .top && part == .top {
            // Strength in steps of a twentieth: one drawing per step, not per slider position.
            let strength = (look.skyStrength * 20).rounded() / 20
            SkyImage(sky: SkyLayerView.Sky(mood: mood, scheme: scheme, contrast: contrast, part: part, strength: strength))
                .frame(height: part == .top ? Metric.skyHeight : Metric.groundHeight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The mesh, filling whatever frame it gets: its points are fractions of it.
    static func mesh(_ sky: SkyLayerView.Sky) -> some View {
        let colors = Ink.sky(sky.mood)
        let top = Ink.skyOpacity(sky.scheme) * sky.strength
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.6, 0.45], [1, 0.55],
            [0, 1], [0.5, 1], [1, 1],
        ]
        // The glow at the foot mirrors the top, fainter, its colors the other way round.
        let tints: [Color] = switch sky.part {
        case .top: [
            colors[0].opacity(top), colors[1].opacity(top * 0.75), colors[2].opacity(top),
            colors[1].opacity(top * 0.4), colors[2].opacity(top * 0.3), colors[0].opacity(top * 0.4),
            colors[2].opacity(0), colors[0].opacity(0), colors[1].opacity(0),
        ]
        case .ground: [
            colors[1].opacity(0), colors[0].opacity(0), colors[2].opacity(0),
            colors[2].opacity(top * 0.2), colors[1].opacity(top * 0.12), colors[0].opacity(top * 0.2),
            colors[2].opacity(top * 0.6), colors[1].opacity(top * 0.35), colors[0].opacity(top * 0.55),
        ]
        }
        return MeshGradient(width: 3, height: 3, points: points, colors: tints) // perf: ok drawn once per mood on the CPU (SkyLayerView) // grid: ok mesh points, not points on screen
    }
}

/// The ground under the page's and a sheet's cards: the gray canvas, the sky on it.
struct CanvasView: View {
    let mood: SkyMood
    /// How strong the sky is here: a sheet's is fainter.
    var sky: Double = 1
    /// Only the sky at the top: a pinned header's band.
    var band = false

    var body: some View {
        ZStack(alignment: .top) {
            Ink.content
            SkyView(mood: mood).opacity(sky)
            if !band {
                SkyView(mood: mood, part: .ground)
                    .opacity(sky)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

/// Where a sky sits: the band at the top of the page, or the glow at the window's foot.
enum SkyPart: Hashable {
    case top, ground
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
        var part: SkyPart = .top
        var strength: Double = 1
    }

    private var sky: Sky?
    /// What it shows now: the UI test reads it.
    private(set) var shown: Sky?
    /// One drawing per mood and appearance, at one pixel per point of a wide page: smooth enough to stretch.
    private static var drawings: [Sky: CGImage] = [:]
    private static let drawn = CGSize(width: 1504, height: 420)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Redrawn when its sky changes (show, a new accent), stretched when it resizes.
        layerContentsRedrawPolicy = .onSetNeedsDisplay
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
            let renderer = ImageRenderer(content: SkyView.mesh(sky).frame(width: drawn.width, height: drawn.height) // perf: ok into a CGContext
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
        // A slider's drag draws a step each: keep a few drawings, not every strength tried.
        if drawings.count >= 12 { drawings = [:] }
        if let image { drawings[sky] = image }
        return image
    }
}

/// A row's kind as a small tile: a white glyph on the kind's color (a PR's state, a file, an artifact).
struct KindTile: View {
    let icon: KitIcon
    let tint: Color
    var size = Metric.kindTile

    var body: some View {
        icon.image
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(Ink.onTile)
            .frame(width: size, height: size)
            .tileFill(tint, radius: Radius.kindTile)
    }
}

extension View {
    /// A tile's fill: its tint as a gradient; with richer marks (Settings › Appearance), a gloss along its top edge and a
    /// soft shadow of its color.
    func tileFill(_ tint: Color, radius: CGFloat) -> some View { modifier(TileFill(tint: tint, radius: radius)) }
}

extension NSColor {
    /// The top of a mark lit from above (richer marks): this color, lighter.
    var markTop: NSColor { blended(withFraction: 0.3, of: .white) ?? self }
}

extension Color {
    /// A mark in this color: flat; with richer marks (Settings › Appearance), lit from above.
    var markFill: AnyShapeStyle {
        Look.shared.richMarks
            ? AnyShapeStyle(LinearGradient(colors: [mix(with: .white, by: 0.3), self], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(self)
    }
}

private struct TileFill: ViewModifier {
    let tint: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if Look.shared.richMarks {
            content
                .background(LinearGradient(colors: [tint.mix(with: .white, by: 0.25), tint, tint.mix(with: .black, by: 0.12)],
                                           startPoint: .top, endPoint: .bottom), in: shape)
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [Ink.onTile.opacity(0.5), Ink.onTile.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1)
                }
                .shadow(color: tint.opacity(0.35), radius: Metric.shadowNearRadius * 2, y: Metric.shadowNearY)
        } else {
            content.background(tint.gradient, in: shape)
        }
    }
}

/// A section's symbol on a small tinted tile, as Reminders and Things mark their lists.
struct SectionTile: View {
    let icon: KitIcon
    let tint: Color
    var size = Metric.sectionTile

    var body: some View {
        icon.image
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(Ink.onTile)
            .frame(width: size, height: size)
            .tileFill(tint, radius: Radius.tile * size / Metric.sectionTile)
            .accessibilityHidden(true)
    }
}

/// One shape behind the outline's rows: a raised card, a done task's flat card, or a block's tray.
struct CardShape: Equatable {
    enum Kind: Equatable { case card, flat, tray }
    /// A Blocked card's red edge; a selected card's accent ring, as a session card's, thinner and lighter among several
    /// when the focus is elsewhere (`kept`, 2026-11-20, T-708); the card a dragged task would drop onto (2026-11-10).
    enum Ring: Equatable { case blocked, selected, kept, drop }

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
    /// One card's layers: its far shadow, its body (fill, hairline, contact shadow), and the light on it while lit.
    private final class Card {
        let far = CALayer()
        let body = CALayer()
        /// Frosted: the far shadow cut out under the card, so the sky shows through it clean.
        let cut = CAShapeLayer()
        /// Lit: the light down its fill, and its rim along the top edge.
        let fall = CAGradientLayer()
        let rim = CAShapeLayer()
        let rimFade = CAGradientLayer()

        init() {
            cut.fillRule = .evenOdd
            rim.fillColor = nil
            rim.lineWidth = 1
            rimFade.colors = [NSColor.black.cgColor, NSColor.clear.cgColor]
            rimFade.locations = [0, 0.3]
            rim.mask = rimFade
            body.addSublayer(fall)
            body.addSublayer(rim)
        }

        /// Its light's and its cut's shapes, for a card of this size.
        func shape(_ size: CGSize, radius: CGFloat) {
            let bounds = CGRect(origin: .zero, size: size)
            fall.frame = bounds
            fall.cornerRadius = radius
            fall.cornerCurve = .continuous
            rim.frame = bounds
            rim.path = CGPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerWidth: radius - 1.5, cornerHeight: radius - 1.5, transform: nil)
            rimFade.frame = bounds
            let reach = Metric.shadowLitRadius * 3
            cut.frame = bounds.insetBy(dx: -reach, dy: -reach)
            let path = CGMutablePath()
            path.addRect(CGRect(origin: .zero, size: cut.frame.size))
            path.addRoundedRect(in: bounds.offsetBy(dx: reach, dy: reach), cornerWidth: radius, cornerHeight: radius)
            cut.path = path
        }
    }

    private var cards: [String: Card] = [:]
    private(set) var shapes: [CardShape] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        setAccessibilityElement(false)
        NotificationCenter.default.addObserver(self, selector: #selector(lookChanged), name: Look.changed, object: nil)
    }

    @objc private func lookChanged() { paint() }

    /// Each raised card's fill alpha and whether its rim shows: the UI test reads them.
    var raised: [(alpha: CGFloat, rim: Bool)] {
        shapes.enumerated().filter { $0.element.kind == .card }.compactMap { index, shape in
            cards[shape.key.isEmpty ? "#\(index)" : shape.key].map { ($0.body.backgroundColor?.alpha ?? 0, !$0.rim.isHidden) }
        }
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
            let card = cards[key] ?? Card()
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
            card.shape(shape.rect.size, radius: shape.radius)
            card.body.shadowRadius = Metric.shadowNearRadius
            card.body.shadowOffset = CGSize(width: 0, height: Metric.shadowNearY)
            card.body.borderWidth = shape.ring == .selected || shape.ring == .drop ? Metric.selectionRing : shape.ring == .kept ? Metric.keptRing : shape.ring == .blocked ? 1.5 : 1
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
            card.body.removeFromSuperlayer()
            card.far.removeFromSuperlayer()
            cards[key] = nil
        }
        CATransaction.commit()
        paint()
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

    /// A color, resolved in the current appearance, its alpha scaled.
    private static func scaled(_ color: NSColor, _ factor: Double) -> CGColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color.cgColor }
        return rgb.withAlphaComponent(min(1, rgb.alphaComponent * factor)).cgColor
    }

    /// The colors in this view's appearance.
    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let look = Look.shared
        let lit = look.lit
        let opacity = look.cardOpacity
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for (index, shape) in shapes.enumerated() {
                guard let card = cards[shape.key.isEmpty ? "#\(index)" : shape.key] else { continue }
                let raised = shape.kind == .card
                let frosted = raised && opacity < 1 && shape.ring != .drop
                card.far.shadowColor = (lit == nil ? Ink.shadowFarNS : Ink.shadowLitNS).cgColor
                card.far.shadowOpacity = raised ? Float(min(1, lit ?? 1)) : 0
                card.far.shadowRadius = lit == nil ? Metric.shadowFarRadius : Metric.shadowLitRadius
                card.far.shadowOffset = CGSize(width: 0, height: lit == nil ? Metric.shadowFarY : Metric.shadowLitY)
                card.far.mask = frosted ? card.cut : nil
                let fill = shape.ring == .drop ? Ink.dropCardNS : shape.kind == .tray ? (opacity < 1 ? Ink.trayFrostedNS : Ink.trayNS)
                    : shape.kind == .flat ? Ink.doneCardNS : Ink.surfaceNS
                card.body.backgroundColor = frosted ? Self.scaled(fill, opacity) : fill.cgColor
                card.body.borderColor = (shape.ring == .selected || shape.ring == .drop ? Ink.accentNS : shape.ring == .kept ? Ink.keptRingNS : shape.ring == .blocked ? Ink.blockedRingNS : Ink.cardHairlineNS).cgColor
                card.body.shadowColor = Ink.shadowNearNS.cgColor
                // A see-through card would show its contact shadow under it.
                card.body.shadowOpacity = raised && !frosted ? 1 : 0
                let light = raised ? lit : nil
                card.fall.isHidden = light == nil
                card.rim.isHidden = light == nil
                if let light {
                    card.fall.colors = [Self.scaled(Ink.fallTopNS, light),
                                        Self.scaled(Ink.fallBottomNS, light)]
                    card.rim.strokeColor = Self.scaled(Ink.rimNS, 0.8 * light)
                }
            }
        }
        CATransaction.commit()
    }
}
