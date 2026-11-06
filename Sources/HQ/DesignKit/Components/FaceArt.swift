import AppKit
import HQKit
import SwiftUI

/// Draws a session's face (DESIGN.md §10) into a Core Graphics context with its origin at the top
/// left, from one 40 × 40 vector family. SwiftUI (`SessionFace`) and AppKit (`FaceView`) both use it.
enum FaceArt {
    /// The badge on a face: orange while the session needs the user, red when it failed.
    enum Badge {
        case needsYou, failed
    }

    /// Up to 20 pt: silhouettes. 21 to 31: features. 32 and up: every detail.
    enum Detail: Comparable {
        case silhouette, features, full

        init(size: CGFloat) {
            self = size <= 20 ? .silhouette : size < 32 ? .features : .full
        }
    }

    /// A face's parts, back to front: the head's sway, the background and the body stay.
    nonisolated enum Part: CaseIterable {
        case background, headBack, body, head

        var sways: Bool { self == .headBack || self == .head }
    }

    static let grid: CGFloat = 40
    /// The squircle's corner, 30% of the side.
    static let corner: CGFloat = 0.3

    /// One part of a `size` face, still and unclipped, with its top left at `origin` on the grid.
    static func draw(_ part: Part, of spec: FaceSpec, size: CGFloat, in ctx: CGContext, origin: CGPoint = .zero) {
        let scale = size / grid
        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: origin.x, y: origin.y)
        Painter(ctx: ctx, spec: spec, detail: Detail(size: size), scale: scale).paint(part)
        ctx.restoreGState()
    }

    /// `sway`: where a working session's head is in its sway, 0 to 1; nil draws it still.
    static func draw(_ spec: FaceSpec, in ctx: CGContext, rect: CGRect, ended: Bool = false, sway: Double? = nil) {
        let size = min(rect.width, rect.height)
        let detail = Detail(size: size)
        let scale = size / grid
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY)
        ctx.addPath(squircle(size))
        ctx.clip()
        if ended {
            // Ended: faded, in its own colors, so it stays recognizable.
            ctx.setAlpha(0.55)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        ctx.scaleBy(x: scale, y: scale)
        Painter(ctx: ctx, spec: spec, detail: detail, scale: scale, head: sway.map(headMotion) ?? .identity).paint()
        if ended { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    /// The badge's disc at the bottom right, 30% of the face (at least 7 pt), ringed with the surface.
    static func drawBadge(_ badge: Badge, in ctx: CGContext, rect: CGRect, ring: CGColor) {
        let side = badgeSide(rect.width)
        let disc = CGRect(x: rect.maxX - side + 2, y: rect.maxY - side + 2, width: side, height: side) // grid: ok drawn mark
        ctx.saveGState()
        ctx.setFillColor(ring)
        ctx.fillEllipse(in: disc.insetBy(dx: -2, dy: -2))
        ctx.setFillColor(color(badge))
        ctx.fillEllipse(in: disc)
        ctx.restoreGState()
    }

    static func badgeSide(_ size: CGFloat) -> CGFloat { max(7, (size * 0.3).rounded()) }

    /// A working head sways from the chin, 8° each way, and nods down at each end; shoulders and background stay.
    static func headMotion(_ sway: Double) -> CGAffineTransform {
        let angle = sin(sway * 2 * .pi) * 8 * .pi / 180
        let dip = (1 - cos(sway * 4 * .pi)) / 2 * 1.4
        return CGAffineTransform(translationX: 20, y: 30 + dip).rotated(by: angle).translatedBy(x: -20, y: -30)
    }

    /// Where a face is in its sway at `date`: each face starts at its own point, so faces side by side don't move together.
    static func sway(_ spec: FaceSpec, at date: Date) -> Double {
        let offset = Double((spec.background * 7 + spec.skin * 5 + spec.hair.rawValue * 3) % 17) / 17
        return (date.timeIntervalSinceReferenceDate / Motion.faceSway + offset).truncatingRemainder(dividingBy: 1)
    }

    static func color(_ badge: Badge) -> CGColor {
        (badge == .failed ? Ink.failedNS : Ink.needsYouNS).cgColor
    }

    static func squircle(_ size: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: size * corner, style: .continuous)
            .path(in: CGRect(x: 0, y: 0, width: size, height: size)).cgPath
    }

    static func cg(_ rgb: RGB, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }

    /// An image of the face, for drag images and menus.
    static func image(_ spec: FaceSpec, size: CGFloat, ended: Bool = false) -> NSImage {
        NSImage(size: CGSize(width: size, height: size), flipped: true) { rect in
            if let ctx = NSGraphicsContext.current?.cgContext { draw(spec, in: ctx, rect: rect, ended: ended) }
            return true
        }
    }
}

/// One face, painted part by part on the 40 grid, back to front.
private struct Painter {
    let ctx: CGContext
    let spec: FaceSpec
    let detail: FaceArt.Detail
    let scale: CGFloat
    /// The head's motion on the 40 grid: identity when still.
    var head = CGAffineTransform.identity

    private var skin: RGB { FacePalette.skins[spec.skin] }
    private var hair: RGB { FacePalette.hair[spec.hairColor] }
    private var ink: RGB { FacePalette.ink(on: spec.skin) }
    private var lightInk: Bool { ink == FacePalette.inkLight }
    private var hat: RGB { FacePalette.clothes[spec.headwearColor] }
    /// A detail on a hat: dark on a light hat, light on a dark one.
    private var hatDetail: RGB { hat.luminance > 0.45 ? FacePalette.clothes[0] : FacePalette.white }
    /// Strokes stay at least 1 pt wide on screen (1.25 pt for silhouettes).
    private func stroke(_ grid: CGFloat) -> CGFloat {
        max(grid, (detail == .silhouette ? 1.25 : 1) / scale)
    }

    private var hatCoversHair: Bool {
        [.beanie, .cap, .topHat, .bucket, .hood].contains(spec.headwear)
    }

    func paint() {
        for part in FaceArt.Part.allCases {
            if part.sways { moving { paint(part) } } else { paint(part) }
        }
    }

    func paint(_ part: FaceArt.Part) {
        switch part {
        case .background:
            background()
        case .headBack:
            if spec.headwear == .hood { fill(hoodBack, hat) }
            hairBack()
        case .body:
            fill(shoulders, FacePalette.clothes[spec.clothes])
            // A collar line, so light clothes on a light background still read.
            if detail == .full { strokePath(collar, FacePalette.black, width: 0.8, alpha: 0.12) }
            fill(neck, skin)
        case .head:
            fill(ears, skin)
            fill(headShape, skin)
            if detail == .full { cheeks() }
            if detail >= .features { facialHair() }
            if detail >= .features { eyesAndMouth() } else { silhouetteEyes() }
            hairTop()
            headwear()
            eyewear()
            extras()
        }
    }

    /// Draws the head's parts with its motion.
    private func moving(_ parts: () -> Void) {
        guard head != .identity else { return parts() }
        ctx.saveGState()
        ctx.concatenate(head)
        parts()
        ctx.restoreGState()
    }

    // MARK: Background

    private func background() {
        let color = FacePalette.backgrounds[spec.background]
        ctx.setFillColor(FaceArt.cg(color))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        guard detail == .full else { return }
        let light = FaceArt.cg(FacePalette.white, 0.2)
        let dark = FaceArt.cg(FacePalette.black, 0.07)
        switch spec.pattern {
        case .none: break
        case .diagonal:
            fill(path { $0.move(to: p(40, 0)); $0.addLine(to: p(40, 40)); $0.addLine(to: p(0, 40)); $0.closeSubpath() }, dark)
        case .stripes:
            fill(path { p in
                for offset in stride(from: -40.0, through: 40, by: 11) {
                    p.move(to: CGPoint(x: offset, y: 40)); p.addLine(to: CGPoint(x: offset + 40, y: 0))
                    p.addLine(to: CGPoint(x: offset + 45, y: 0)); p.addLine(to: CGPoint(x: offset + 5, y: 40)); p.closeSubpath()
                }
            }, light)
        case .rings:
            for radius in [12.0, 22, 32] {
                ctx.setStrokeColor(light)
                ctx.setLineWidth(3)
                ctx.strokeEllipse(in: CGRect(x: 40 - radius, y: -radius, width: radius * 2, height: radius * 2))
            }
        case .dots:
            fill(path { p in
                for row in 0..<5 {
                    for column in 0..<5 {
                        let x = 4 + Double(column) * 8 + (row.isMultiple(of: 2) ? 0 : 4)
                        p.addEllipse(in: CGRect(x: x - 1.1, y: 4 + Double(row) * 8 - 1.1, width: 2.2, height: 2.2))
                    }
                }
            }, light)
        }
    }

    // MARK: Body

    private var shoulders: CGPath {
        path { p in
            p.move(to: p_(4, 40))
            p.addCurve(to: p_(20, 30.4), control1: p_(4, 33.6), control2: p_(10.6, 30.4))
            p.addCurve(to: p_(36, 40), control1: p_(29.4, 30.4), control2: p_(36, 33.6))
            p.closeSubpath()
        }
    }

    private var collar: CGPath {
        path { p in
            p.move(to: p_(16.4, 31)); p.addQuadCurve(to: p_(23.6, 31), control: p_(20, 34.4))
        }
    }

    private var neck: CGPath { CGPath(rect: CGRect(x: 17, y: 25, width: 6, height: 7), transform: nil) }

    private var ears: CGPath {
        path { p in
            p.addEllipse(in: CGRect(x: 9.2, y: 18.2, width: 3.2, height: 4.6))
            p.addEllipse(in: CGRect(x: 27.6, y: 18.2, width: 3.2, height: 4.6))
        }
    }

    private var headShape: CGPath {
        switch spec.shape {
        case .round: CGPath(ellipseIn: CGRect(x: 10.5, y: 10, width: 19, height: 19), transform: nil)
        case .oval: CGPath(ellipseIn: CGRect(x: 11.3, y: 9.2, width: 17.4, height: 20.6), transform: nil)
        case .square: CGPath(roundedRect: CGRect(x: 10.8, y: 9.8, width: 18.4, height: 19.4), cornerWidth: 6, cornerHeight: 6, transform: nil)
        case .soft: CGPath(roundedRect: CGRect(x: 10.6, y: 9.6, width: 18.8, height: 19.8), cornerWidth: 8.4, cornerHeight: 9, transform: nil)
        }
    }

    private func cheeks() {
        if spec.extras.contains(.blush) {
            fill(path { p in
                p.addEllipse(in: CGRect(x: 13.2, y: 22, width: 3, height: 1.7))
                p.addEllipse(in: CGRect(x: 23.8, y: 22, width: 3, height: 1.7))
            }, FacePalette.blush, alpha: 0.55)
        }
        if spec.extras.contains(.freckles), !spec.eyesHidden {
            fill(path { p in
                for (x, y) in [(14.6, 22.2), (16.2, 23.1), (15, 23.8), (25.4, 22.2), (23.8, 23.1), (25, 23.8)] {
                    p.addEllipse(in: CGRect(x: x - 0.42, y: y - 0.42, width: 0.84, height: 0.84))
                }
            }, FacePalette.freckle, alpha: 0.75)
        }
    }

    // MARK: Hair

    private func hairBack() {
        guard spec.headwear != .hood else { return }
        switch spec.hair {
        case .long:
            fill(path { p in
                p.move(to: p_(9.2, 31)); p.addLine(to: p_(9.2, 19))
                p.addQuadCurve(to: p_(20, 8.2), control: p_(9.2, 8.2))
                p.addQuadCurve(to: p_(30.8, 19), control: p_(30.8, 8.2))
                p.addLine(to: p_(30.8, 31)); p.addQuadCurve(to: p_(9.2, 31), control: p_(20, 33.4)); p.closeSubpath()
            }, hair)
        case .bob:
            fill(path { p in
                p.move(to: p_(9.4, 25.6)); p.addLine(to: p_(9.4, 18.6))
                p.addQuadCurve(to: p_(20, 8.4), control: p_(9.4, 8.4))
                p.addQuadCurve(to: p_(30.6, 18.6), control: p_(30.6, 8.4))
                p.addLine(to: p_(30.6, 25.6)); p.addQuadCurve(to: p_(27.4, 26.6), control: p_(29.4, 26.8))
                p.addLine(to: p_(12.6, 26.6)); p.addQuadCurve(to: p_(9.4, 25.6), control: p_(10.6, 26.8)); p.closeSubpath()
            }, hair)
        case .afro:
            guard !hatCoversHair else { return }
            fill(path { p in
                for (x, y, r) in [(20.0, 13.6, 10.8), (11.4, 17.8, 5.2), (28.6, 17.8, 5.2), (13.2, 9.6, 5), (26.8, 9.6, 5), (20, 6.4, 5.4)] {
                    p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
            }, hair)
        default:
            break
        }
    }

    private func hairTop() {
        guard !hatCoversHair else { return }
        let cap = path { p in
            p.move(to: p_(10.4, 18.6))
            p.addQuadCurve(to: p_(20, 8.4), control: p_(10, 8.4))
            p.addQuadCurve(to: p_(29.6, 18.6), control: p_(30, 8.4))
            p.addQuadCurve(to: p_(20, 13.2), control: p_(27.4, 13.2))
            p.addQuadCurve(to: p_(10.4, 18.6), control: p_(12.6, 13.2)); p.closeSubpath()
        }
        switch spec.hair {
        case .bald:
            break
        case .short, .long:
            fill(cap, hair)
        case .bob:
            fill(path { p in
                p.move(to: p_(10.2, 19.4))
                p.addQuadCurve(to: p_(20, 8.4), control: p_(9.8, 8.4))
                p.addQuadCurve(to: p_(29.8, 19.4), control: p_(30.2, 8.4))
                p.addQuadCurve(to: p_(27.2, 14.4), control: p_(29, 15.2))
                p.addLine(to: p_(12.8, 14.4))
                p.addQuadCurve(to: p_(10.2, 19.4), control: p_(11, 15.2)); p.closeSubpath()
            }, hair)
        case .swoop:
            fill(path { p in
                p.move(to: p_(10.4, 18.2))
                p.addQuadCurve(to: p_(20.4, 8.2), control: p_(9.8, 8.2))
                p.addQuadCurve(to: p_(29.8, 17.4), control: p_(29.4, 8.2))
                p.addQuadCurve(to: p_(17, 14.4), control: p_(25, 11.6))
                p.addQuadCurve(to: p_(10.4, 18.2), control: p_(12.6, 15.4)); p.closeSubpath()
            }, hair)
        case .curly:
            fill(path { p in
                for (x, y, r) in [(12.2, 15.6, 3.1), (14.2, 11.6, 3.3), (18, 9.4, 3.4), (22, 9.4, 3.4), (25.8, 11.6, 3.3), (27.8, 15.6, 3.1)] {
                    p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
            }, hair)
        case .bun:
            fill(cap, hair)
            fill(CGPath(ellipseIn: CGRect(x: 16.6, y: 3.2, width: 6.8, height: 6.8), transform: nil), hair)
        case .afro:
            fill(path { p in
                p.move(to: p_(10.8, 17.4)); p.addQuadCurve(to: p_(29.2, 17.4), control: p_(20, 9.6))
                p.addQuadCurve(to: p_(10.8, 17.4), control: p_(20, 12.4)); p.closeSubpath()
            }, hair)
        case .mohawk:
            fill(path { p in
                p.move(to: p_(17.8, 14)); p.addLine(to: p_(17.8, 6.2))
                p.addQuadCurve(to: p_(22.2, 6.2), control: p_(20, 1.4))
                p.addLine(to: p_(22.2, 14)); p.closeSubpath()
            }, hair)
        case .spikes:
            fill(path { p in
                p.move(to: p_(10.6, 17))
                for (x, y) in [(11.6, 9.2), (14.6, 12), (16.2, 6.4), (18.8, 10.6), (20.4, 5.2), (22.4, 10.4), (24.8, 6.4), (26.4, 11.4), (28.6, 9.2), (29.4, 17)] {
                    p.addLine(to: p_(x, y))
                }
                p.addQuadCurve(to: p_(10.6, 17), control: p_(20, 11.6)); p.closeSubpath()
            }, hair)
        }
    }

    // MARK: Face

    private func facialHair() {
        switch spec.facialHair {
        case .none: break
        case .mustache:
            fill(path { p in
                p.move(to: p_(16.6, 23.6)); p.addQuadCurve(to: p_(20, 22.6), control: p_(18.2, 21.6))
                p.addQuadCurve(to: p_(23.4, 23.6), control: p_(21.8, 21.6))
                p.addQuadCurve(to: p_(20, 23.8), control: p_(21.8, 24.4))
                p.addQuadCurve(to: p_(16.6, 23.6), control: p_(18.2, 24.4)); p.closeSubpath()
            }, hair)
        case .beard, .stubble:
            let beard = path { p in
                p.move(to: p_(10.6, 19.4)); p.addQuadCurve(to: p_(20, 29.8), control: p_(10.6, 29.6))
                p.addQuadCurve(to: p_(29.4, 19.4), control: p_(29.4, 29.6))
                p.addQuadCurve(to: p_(25.8, 24.8), control: p_(28.2, 23.8))
                p.addQuadCurve(to: p_(20, 23), control: p_(23.4, 23))
                p.addQuadCurve(to: p_(14.2, 24.8), control: p_(16.6, 23))
                p.addQuadCurve(to: p_(10.6, 19.4), control: p_(11.8, 23.8)); p.closeSubpath()
            }
            fill(beard, hair, alpha: spec.facialHair == .stubble ? 0.38 : 1)
        case .goatee:
            fill(path { p in
                p.move(to: p_(18, 26.6)); p.addQuadCurve(to: p_(22, 26.6), control: p_(20, 30))
                p.addQuadCurve(to: p_(18, 26.6), control: p_(20, 27.4)); p.closeSubpath()
            }, hair)
        }
    }

    /// Two dots, so a 16 pt face still looks back.
    private func silhouetteEyes() {
        guard !spec.eyesHidden else { return }
        let radius: CGFloat = 1.7
        fill(path { p in
            for x in [16.3, 23.7] { p.addEllipse(in: CGRect(x: x - radius, y: 19.8 - radius, width: radius * 2, height: radius * 2)) }
        }, lightInk ? FacePalette.inkLight : ink)
    }

    private func eyesAndMouth() {
        let width = stroke(1.3)
        if !spec.eyesHidden {
            let left = CGPoint(x: 16.3, y: 19.8)
            let right = CGPoint(x: 23.7, y: 19.8)
            let shift: CGFloat = spec.eyes == .glance ? 0.8 : 0
            func dot(_ center: CGPoint, _ radius: CGFloat) {
                let c = CGPoint(x: center.x + shift, y: center.y)
                if lightInk {
                    // On the deepest skins: a light eye with a dark pupil.
                    fill(CGPath(ellipseIn: CGRect(x: c.x - radius - 0.5, y: c.y - radius - 0.5, width: (radius + 0.5) * 2, height: (radius + 0.5) * 2), transform: nil), ink)
                    fill(CGPath(ellipseIn: CGRect(x: c.x - radius * 0.62, y: c.y - radius * 0.62, width: radius * 1.24, height: radius * 1.24), transform: nil), FacePalette.inkDark)
                } else {
                    fill(CGPath(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2), transform: nil), ink)
                }
                if detail == .full, spec.eyes == .wide {
                    fill(CGPath(ellipseIn: CGRect(x: c.x + 0.2, y: c.y - 0.9, width: 0.7, height: 0.7), transform: nil), FacePalette.white)
                }
            }
            func arc(_ center: CGPoint) {
                strokePath(path { p in
                    p.move(to: CGPoint(x: center.x - 1.4, y: center.y + 0.6))
                    p.addQuadCurve(to: CGPoint(x: center.x + 1.4, y: center.y + 0.6), control: CGPoint(x: center.x, y: center.y - 1.2))
                }, ink, width: width)
            }
            let radius: CGFloat = detail == .features ? 1.45 : 1.3
            switch spec.eyes {
            case .dots, .glance: dot(left, radius); dot(right, radius)
            case .wide: dot(left, radius + 0.4); dot(right, radius + 0.4)
            case .happy: arc(left); arc(right)
            case .wink: dot(left, radius); arc(right)
            case .sleepy:
                for center in [left, right] {
                    strokePath(path { p in
                        p.move(to: CGPoint(x: center.x - 1.4, y: center.y + 0.2)); p.addLine(to: CGPoint(x: center.x + 1.4, y: center.y + 0.2))
                    }, ink, width: width)
                }
            }
        }
        // A beard hides the lips: the mouth shows as a light line on it.
        let bearded = spec.facialHair == .beard
        let lips = bearded ? FacePalette.inkLight : ink
        switch spec.mouth {
        case .smile, .tongue:
            strokePath(path { p in p.move(to: p_(17.4, 24.2)); p.addQuadCurve(to: p_(22.6, 24.2), control: p_(20, 26.6)) }, lips, width: width)
            if spec.mouth == .tongue, detail == .full {
                fill(path { p in p.move(to: p_(19.2, 25.2)); p.addQuadCurve(to: p_(21.2, 25.2), control: p_(20.2, 27.6)); p.closeSubpath() }, FacePalette.tongue)
            }
        case .grin:
            fill(path { p in
                p.move(to: p_(16.9, 23.6)); p.addLine(to: p_(23.1, 23.6))
                p.addQuadCurve(to: p_(16.9, 23.6), control: p_(20, 28.6)); p.closeSubpath()
            }, bearded || lightInk ? FacePalette.inkLight : FacePalette.mouth)
            if detail == .full, !bearded, !lightInk {
                fill(CGPath(rect: CGRect(x: 17.6, y: 23.6, width: 4.8, height: 0.9), transform: nil), FacePalette.white)
            }
        case .flat:
            strokePath(path { p in p.move(to: p_(18, 24.6)); p.addLine(to: p_(22, 24.6)) }, lips, width: width)
        case .open:
            fill(CGPath(ellipseIn: CGRect(x: 18.8, y: 23.6, width: 2.4, height: 2.8), transform: nil), bearded || lightInk ? FacePalette.inkLight : FacePalette.mouth)
        case .smirk:
            strokePath(path { p in p.move(to: p_(17.8, 24.8)); p.addQuadCurve(to: p_(22.6, 23.6), control: p_(20.8, 25.8)) }, lips, width: width)
        }
    }

    // MARK: Headwear

    private func headwear() {
        switch spec.headwear {
        case .none: break
        case .beanie:
            fill(path { p in
                p.move(to: p_(10, 16.4)); p.addQuadCurve(to: p_(20, 6.6), control: p_(10, 6.6))
                p.addQuadCurve(to: p_(30, 16.4), control: p_(30, 6.6)); p.closeSubpath()
            }, hat)
            fill(CGPath(roundedRect: CGRect(x: 9.4, y: 14.2, width: 21.2, height: 3.6), cornerWidth: 1.4, cornerHeight: 1.4, transform: nil), hatDetail)
            fill(CGPath(ellipseIn: CGRect(x: 18, y: 3.4, width: 4, height: 4), transform: nil), hatDetail)
        case .cap:
            fill(path { p in
                p.move(to: p_(10.4, 16)); p.addQuadCurve(to: p_(20, 7.2), control: p_(10.4, 7.2))
                p.addQuadCurve(to: p_(29.6, 16), control: p_(29.6, 7.2)); p.closeSubpath()
            }, hat)
            fill(path { p in
                p.move(to: p_(18.6, 14.4)); p.addLine(to: p_(32.6, 14.4))
                p.addQuadCurve(to: p_(30.4, 17), control: p_(33.2, 17)); p.addLine(to: p_(18.6, 17)); p.closeSubpath()
            }, hat)
            if detail == .full { fill(CGPath(ellipseIn: CGRect(x: 19.2, y: 6.6, width: 1.6, height: 1.6), transform: nil), hatDetail) }
        case .topHat:
            fill(CGPath(roundedRect: CGRect(x: 13.6, y: 2.6, width: 12.8, height: 11.4), cornerWidth: 1, cornerHeight: 1, transform: nil), hat)
            fill(CGPath(roundedRect: CGRect(x: 9, y: 13, width: 22, height: 3), cornerWidth: 1.4, cornerHeight: 1.4, transform: nil), hat)
            fill(CGPath(rect: CGRect(x: 13.6, y: 10, width: 12.8, height: 2.2), transform: nil), hatDetail)
        case .beret:
            fill(path { p in
                p.move(to: p_(8.8, 13.4)); p.addQuadCurve(to: p_(22, 6.8), control: p_(11.8, 6))
                p.addQuadCurve(to: p_(31.4, 12.6), control: p_(30.6, 7.6))
                p.addQuadCurve(to: p_(8.8, 13.4), control: p_(21, 17.2)); p.closeSubpath()
            }, hat)
            fill(CGPath(roundedRect: CGRect(x: 19.4, y: 4.4, width: 1.6, height: 2.8), cornerWidth: 0.6, cornerHeight: 0.6, transform: nil), hat)
        case .party:
            fill(path { p in p.move(to: p_(20, 1.4)); p.addLine(to: p_(26.4, 14.6)); p.addLine(to: p_(13.6, 14.6)); p.closeSubpath() }, hat)
            if detail >= .features {
                fill(path { p in
                    p.move(to: p_(16.4, 9.2)); p.addLine(to: p_(23.6, 9.2)); p.addLine(to: p_(24.4, 10.8)); p.addLine(to: p_(15.6, 10.8)); p.closeSubpath()
                    p.move(to: p_(18.2, 5.4)); p.addLine(to: p_(21.8, 5.4)); p.addLine(to: p_(22.5, 6.8)); p.addLine(to: p_(17.5, 6.8)); p.closeSubpath()
                }, hatDetail)
            }
            fill(CGPath(ellipseIn: CGRect(x: 18.4, y: 0, width: 3.2, height: 3.2), transform: nil), FacePalette.gold)
        case .headband:
            fill(path { p in
                p.move(to: p_(10.3, 13.6)); p.addQuadCurve(to: p_(29.7, 13.6), control: p_(20, 9.2))
                p.addLine(to: p_(29.8, 16.4)); p.addQuadCurve(to: p_(10.2, 16.4), control: p_(20, 12)); p.closeSubpath()
            }, hat)
        case .crown:
            fill(path { p in
                p.move(to: p_(11.6, 14.6))
                for (x, y) in [(12.4, 6.6), (16.2, 10.6), (20, 4.4), (23.8, 10.6), (27.6, 6.6), (28.4, 14.6)] { p.addLine(to: p_(x, y)) }
                p.closeSubpath()
            }, FacePalette.gold)
            if detail >= .features { fill(CGPath(ellipseIn: CGRect(x: 19, y: 10.6, width: 2, height: 2), transform: nil), FacePalette.backgrounds[(spec.background + 6) % 12]) }
        case .bucket:
            fill(path { p in
                p.move(to: p_(12.4, 14)); p.addQuadCurve(to: p_(20, 7), control: p_(12.6, 7))
                p.addQuadCurve(to: p_(27.6, 14), control: p_(27.4, 7)); p.closeSubpath()
            }, hat)
            fill(path { p in
                p.move(to: p_(8.4, 16)); p.addQuadCurve(to: p_(12.4, 12.8), control: p_(9.4, 12.8))
                p.addLine(to: p_(27.6, 12.8)); p.addQuadCurve(to: p_(31.6, 16), control: p_(30.6, 12.8))
                p.addQuadCurve(to: p_(8.4, 16), control: p_(20, 17.8)); p.closeSubpath()
            }, hat)
            if detail == .full { strokePath(path { p in p.move(to: p_(12.6, 12.6)); p.addLine(to: p_(27.4, 12.6)) }, hatDetail, width: 0.7, alpha: 0.5) }
        case .hood:
            fill(path { p in
                p.move(to: p_(10.4, 18)); p.addQuadCurve(to: p_(20, 9.4), control: p_(10.8, 9.4))
                p.addQuadCurve(to: p_(29.6, 18), control: p_(29.2, 9.4))
                p.addQuadCurve(to: p_(20, 13.2), control: p_(26.4, 13.2))
                p.addQuadCurve(to: p_(10.4, 18), control: p_(13.6, 13.2)); p.closeSubpath()
            }, hat)
        }
    }

    private var hoodBack: CGPath {
        path { p in
            p.move(to: p_(7.2, 33)); p.addLine(to: p_(7.2, 21))
            p.addQuadCurve(to: p_(20, 6.4), control: p_(7.2, 6.4))
            p.addQuadCurve(to: p_(32.8, 21), control: p_(32.8, 6.4))
            p.addLine(to: p_(32.8, 33)); p.closeSubpath()
        }
    }

    // MARK: Eyewear and extras

    private func eyewear() {
        let frame = FacePalette.inkDark
        let width = stroke(1.2)
        switch spec.eyewear {
        case .none: break
        case .round:
            guard detail >= .features else { return }
            strokePath(path { p in
                p.addEllipse(in: CGRect(x: 13.4, y: 17, width: 5.6, height: 5.6))
                p.addEllipse(in: CGRect(x: 21, y: 17, width: 5.6, height: 5.6))
                p.move(to: p_(19, 19.4)); p.addLine(to: p_(21, 19.4))
            }, frame, width: width)
        case .square:
            guard detail >= .features else { return }
            strokePath(path { p in
                p.addRoundedRect(in: CGRect(x: 13.2, y: 17.6, width: 5.8, height: 4.4), cornerWidth: 1, cornerHeight: 1)
                p.addRoundedRect(in: CGRect(x: 21, y: 17.6, width: 5.8, height: 4.4), cornerWidth: 1, cornerHeight: 1)
                p.move(to: p_(19, 19.2)); p.addLine(to: p_(21, 19.2))
            }, frame, width: width)
        case .shades:
            fill(path { p in
                for x in [12.8, 20.8] {
                    p.move(to: CGPoint(x: x, y: 17.8)); p.addLine(to: CGPoint(x: x + 6.4, y: 17.8)); p.addLine(to: CGPoint(x: x + 6.4, y: 20))
                    p.addQuadCurve(to: CGPoint(x: x, y: 20), control: CGPoint(x: x + 3.2, y: 23.6)); p.closeSubpath()
                }
                p.addRect(CGRect(x: 19, y: 18, width: 2, height: 1.2))
            }, FacePalette.lens)
        case .visor:
            fill(CGPath(roundedRect: CGRect(x: 11.8, y: 17.2, width: 16.4, height: 5), cornerWidth: 2.2, cornerHeight: 2.2, transform: nil), FacePalette.visor)
            if detail == .full { strokePath(path { p in p.move(to: p_(14, 18.8)); p.addLine(to: p_(19, 18.8)) }, FacePalette.white, width: 0.8, alpha: 0.7) }
        case .monocle:
            guard detail >= .features else { return }
            strokePath(CGPath(ellipseIn: CGRect(x: 20.8, y: 16.8, width: 5.8, height: 5.8), transform: nil), FacePalette.gold, width: width)
            if detail == .full { strokePath(path { p in p.move(to: p_(26.2, 21.4)); p.addQuadCurve(to: p_(26.4, 30), control: p_(28, 26)) }, FacePalette.gold, width: 0.6) }
        }
    }

    private func extras() {
        if spec.extras.contains(.headphones) {
            let color = FacePalette.clothes[spec.headwearColor]
            strokePath(path { p in p.move(to: p_(8.8, 20)); p.addQuadCurve(to: p_(31.2, 20), control: p_(20, -1.6)) }, color, width: stroke(1.8))
            fill(path { p in
                p.addRoundedRect(in: CGRect(x: 7.2, y: 17.4, width: 4, height: 6.6), cornerWidth: 1.6, cornerHeight: 1.6)
                p.addRoundedRect(in: CGRect(x: 28.8, y: 17.4, width: 4, height: 6.6), cornerWidth: 1.6, cornerHeight: 1.6)
            }, color)
        }
        if spec.extras.contains(.earrings), detail >= .features, !spec.extras.contains(.headphones), spec.headwear != .hood {
            fill(path { p in
                p.addEllipse(in: CGRect(x: 9.6, y: 23, width: 2.2, height: 2.2))
                p.addEllipse(in: CGRect(x: 28.2, y: 23, width: 2.2, height: 2.2))
            }, FacePalette.gold)
        }
    }

    // MARK: Drawing

    private func fill(_ shape: CGPath, _ color: RGB, alpha: CGFloat = 1) {
        fill(shape, FaceArt.cg(color, alpha))
    }

    private func fill(_ shape: CGPath, _ color: CGColor) {
        ctx.addPath(shape)
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    private func strokePath(_ shape: CGPath, _ color: RGB, width: CGFloat, alpha: CGFloat = 1) {
        ctx.addPath(shape)
        ctx.setStrokeColor(FaceArt.cg(color, alpha))
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }

    private func path(_ build: (CGMutablePath) -> Void) -> CGPath {
        let path = CGMutablePath()
        build(path)
        return path
    }

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private func p_(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
}
