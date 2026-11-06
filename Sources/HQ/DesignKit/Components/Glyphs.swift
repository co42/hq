import AppKit
import HQKit
import SwiftUI

// Status glyphs: one drawn family, 14 pt in a 16 pt slot, 1.5 pt stroke.
// Marks inside discs are cut out, so they show the row behind them: white on
// a light row, dark on a dark row, the accent on a selected row.

/// A session's state as a glyph.
enum SessionGlyphKind: String, CaseIterable, Identifiable {
    case permission, question, plan, failed, unread, working, compacting, idle, ended

    var id: String { rawValue }

    init(_ status: SessionStatus) {
        switch status.state {
        case .waiting(.permission): self = .permission
        case .waiting(.question): self = .question
        case .waiting(.plan): self = .plan
        case .failed: self = .failed
        case .done: self = status.unread ? .unread : .idle
        case .working: self = .working
        case .compacting: self = .compacting
        case .idle: self = .idle
        case .ended: self = .ended
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .permission: "Needs you: permission"
        case .question: "Needs you: question"
        case .plan: "Needs you: plan"
        case .failed: "Failed"
        case .unread: "Done, unread"
        case .working: "Working"
        case .compacting: "Compacting"
        case .idle: "Idle"
        case .ended: "Ended"
        }
    }
}

struct SessionGlyph: View {
    let kind: SessionGlyphKind
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.forcedPartState) private var forced

    private var onSelection: Bool { forced.map { $0 == .selected } ?? (prominence == .increased) }

    var body: some View {
        GlyphSlot {
            switch kind {
            case .permission: Disc(fill: fill(Ink.needsYou), mark: .exclamation)
            case .question: Disc(fill: fill(Ink.needsYou), mark: .question)
            case .plan: Disc(fill: fill(Ink.needsYou), mark: .lines)
            case .failed: Disc(fill: fill(Ink.failed), mark: .cross)
            case .unread:
                Circle().fill(fill(Ink.unread)).frame(width: Metric.unreadDot, height: Metric.unreadDot)
            case .working:
                ZStack {
                    Ring(style: fill(Ink.accentText).opacity(0.3))
                    Ring(style: fill(Ink.accentText), trim: 0.75)
                }
            case .compacting: Ring(style: fill(Ink.accentText), dashed: true)
            case .idle: Ring(style: onSelection ? AnyShapeStyle(Ink.onAccent) : AnyShapeStyle(Ink.quiet))
            case .ended: Ring(style: onSelection ? AnyShapeStyle(Ink.onAccent) : AnyShapeStyle(Ink.quieter), dashed: true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(kind.accessibilityLabel)
    }

    private func fill(_ color: Color) -> AnyShapeStyle {
        onSelection ? AnyShapeStyle(Ink.onAccent) : AnyShapeStyle(color)
    }
}

/// A task's status as a glyph.
struct TaskGlyph: View {
    let status: TaskStatus
    @Environment(\.backgroundProminence) private var prominence
    @Environment(\.forcedPartState) private var forced

    private var onSelection: Bool { forced.map { $0 == .selected } ?? (prominence == .increased) }

    var body: some View {
        GlyphSlot {
            switch status {
            case .todo: Ring(style: style(AnyShapeStyle(Ink.quiet)))
            case .doing:
                ZStack {
                    Ring(style: style(AnyShapeStyle(Ink.doing)))
                    Pie(share: 0.5).fill(style(AnyShapeStyle(Ink.doing)))
                }
            case .review:
                ZStack {
                    Ring(style: style(AnyShapeStyle(Ink.needsYou)))
                    Pie(share: 0.75).fill(style(AnyShapeStyle(Ink.needsYou)))
                }
            case .done: Disc(fill: style(AnyShapeStyle(Ink.done)), mark: .check)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(status.title)
    }

    private func style(_ color: AnyShapeStyle) -> AnyShapeStyle {
        onSelection ? AnyShapeStyle(Ink.onAccent) : color
    }
}

/// The 16 pt slot that centers a 14 pt glyph.
private struct GlyphSlot<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: Metric.glyph, height: Metric.glyph)
            .frame(width: Metric.glyphSlot, height: Metric.glyphSlot)
    }
}

private struct Ring<S: ShapeStyle>: View {
    let style: S
    var trim: CGFloat = 1
    var dashed = false

    var body: some View {
        let inset = Metric.glyphStroke / 2
        // Ten dashes that close evenly around the ring.
        let segment = .pi * (Metric.glyph - Metric.glyphStroke) / 10
        Circle()
            .inset(by: inset)
            .trim(from: 0, to: trim)
            .stroke(style, style: StrokeStyle(lineWidth: Metric.glyphStroke, lineCap: dashed ? .butt : .round,
                                              dash: dashed ? [segment * 0.55, segment * 0.45] : []))
            .rotationEffect(.degrees(-90))
    }
}

private struct Disc<S: ShapeStyle>: View {
    let fill: S
    let mark: GlyphMark.Kind

    var body: some View {
        ZStack {
            Circle().fill(fill)
            GlyphMark(kind: mark)
                .stroke(.black, style: StrokeStyle(lineWidth: Metric.glyphStroke, lineCap: .round, lineJoin: .round))
                .blendMode(.destinationOut)
            if let dot = mark.dot {
                Circle()
                    .fill(.black)
                    .frame(width: Metric.glyphStroke * 1.3, height: Metric.glyphStroke * 1.3) // grid: ok drawn mark
                    .position(x: dot.x * GlyphMark.scale, y: dot.y * GlyphMark.scale) // grid: ok drawn mark
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }
}

/// Marks drawn on a 14 × 14 box.
nonisolated private struct GlyphMark: Shape {
    /// The box the marks are drawn on, and its scale at the current zoom.
    static let box: CGFloat = 14
    static var scale: CGFloat { Metric.glyph / box }

    enum Kind {
        case exclamation, question, lines, cross, check

        var dot: CGPoint? {
            switch self {
            case .exclamation, .question: CGPoint(x: 7, y: 10.4)
            default: nil
            }
        }
    }

    let kind: Kind

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch kind {
        case .exclamation:
            p.move(to: CGPoint(x: 7, y: 3.6))
            p.addLine(to: CGPoint(x: 7, y: 7.9))
        case .question:
            p.move(to: CGPoint(x: 5.3, y: 5.3))
            p.addArc(center: CGPoint(x: 7, y: 5.3), radius: 1.7, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addQuadCurve(to: CGPoint(x: 7, y: 7.3), control: CGPoint(x: 8.7, y: 6.4))
            p.addLine(to: CGPoint(x: 7, y: 8.0))
        case .lines:
            for (y, end) in [(4.5, 9.75), (7.0, 9.75), (9.5, 7.75)] {
                p.move(to: CGPoint(x: 4.25, y: y))
                p.addLine(to: CGPoint(x: end, y: y))
            }
        case .cross:
            p.move(to: CGPoint(x: 4.9, y: 4.9))
            p.addLine(to: CGPoint(x: 9.1, y: 9.1))
            p.move(to: CGPoint(x: 9.1, y: 4.9))
            p.addLine(to: CGPoint(x: 4.9, y: 9.1))
        case .check:
            p.move(to: CGPoint(x: 4.3, y: 7.3))
            p.addLine(to: CGPoint(x: 6.2, y: 9.1))
            p.addLine(to: CGPoint(x: 9.8, y: 5.0))
        }
        let scale = rect.width / Self.box
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale))
    }
}

/// Progress inside the ring, clockwise from the top: half for doing, three quarters for review.
nonisolated private struct Pie: Shape {
    let share: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2 - Metric.glyphStroke * 2.25
        var p = Path()
        p.move(to: center)
        p.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * share), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// The task glyph for AppKit rows: the same family, drawn with Core Graphics.
class TaskGlyphView: NSView {
    var status = TaskStatus.todo { didSet { needsDisplay = true; setAccessibilityLabel(status.title) } }
    /// White on a selected row.
    var onSelection = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: Metric.glyphSlot, height: Metric.glyphSlot) }

    /// A short spring around its center when the user changes the status: the change is felt, as Things' checkbox.
    func pop() {
        wantsLayer = true
        guard let layer else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        func scaled(_ scale: CGFloat) -> NSValue {
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, scale, scale, 1)
            return NSValue(caTransform3D: CATransform3DTranslate(transform, -center.x, -center.y, 0))
        }
        let pop = CAKeyframeAnimation(keyPath: "transform")
        pop.values = [scaled(0.55), scaled(1.22), scaled(0.94), scaled(1)]
        pop.keyTimes = [0, 0.45, 0.75, 1]
        pop.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        pop.duration = Motion.popSeconds
        layer.add(pop, forKey: "pop")
    }

    /// A status's glyph as an image, for menus.
    static func image(_ status: TaskStatus) -> NSImage {
        let side = Metric.glyphSlot
        return NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            let view = TaskGlyphView(frame: rect)
            view.status = status
            view.draw(rect)
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let side = Metric.glyph
        let rect = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let stroke = Metric.glyphStroke
        func color(_ ns: NSColor) -> CGColor { (onSelection ? NSColor.alternateSelectedControlTextColor : ns).cgColor }
        let ring = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
        func pie(_ share: CGFloat, _ ns: NSColor) {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = side / 2 - stroke * 2.25
            ctx.move(to: center)
            ctx.addArc(center: center, radius: radius, startAngle: -.pi / 2, endAngle: -.pi / 2 + 2 * .pi * share, clockwise: false)
            ctx.closePath()
            ctx.setFillColor(color(ns))
            ctx.fillPath()
        }
        ctx.setLineWidth(stroke)
        switch status {
        case .todo:
            ctx.setStrokeColor(color(.secondaryLabelColor))
            ctx.strokeEllipse(in: ring)
        case .doing:
            ctx.setStrokeColor(color(Ink.doingNS))
            ctx.strokeEllipse(in: ring)
            pie(0.5, Ink.doingNS)
        case .review:
            ctx.setStrokeColor(color(Ink.needsYouNS))
            ctx.strokeEllipse(in: ring)
            pie(0.75, Ink.needsYouNS)
        case .done:
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.setFillColor(color(Ink.doneNS))
            ctx.fillEllipse(in: rect)
            ctx.setBlendMode(.clear)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            // The check of GlyphMark, at the glyph's zoom.
            let scale = side / 14
            ctx.move(to: CGPoint(x: rect.minX + 4.3 * scale, y: rect.minY + 7.3 * scale))
            ctx.addLine(to: CGPoint(x: rect.minX + 6.2 * scale, y: rect.minY + 9.1 * scale))
            ctx.addLine(to: CGPoint(x: rect.minX + 9.8 * scale, y: rect.minY + 5.0 * scale))
            ctx.strokePath()
            ctx.endTransparencyLayer()
        }
    }
}
