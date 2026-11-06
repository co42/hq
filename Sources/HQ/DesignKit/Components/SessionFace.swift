import AppKit
import HQKit
import SwiftUI

// MARK: SwiftUI

/// A session's face, with its badge, tooltip and VoiceOver label. A click shows its session's menu.
struct SessionFace: View {
    /// Set once by the app: what a double-click on a session's face does.
    static var doubleClick: ((String) -> Void)?
    /// Set once by the app: a click on a session's face.
    static var click: ((String) -> Void)?

    let spec: FaceSpec
    /// The session it shows, when it shows one.
    var session: String?
    var size: CGFloat = Metric.faceCard
    var badge: FaceArt.Badge?
    var ended = false
    /// The session works: its head sways, unless Reduce Motion is on.
    var working = false
    /// "registry: retry budget, asks".
    var label: String?

    init(_ session: SessionItem, size: CGFloat = Metric.faceCard) {
        spec = session.face
        self.size = size
        badge = session.status.needsYou ? (session.status.state == .failed ? .failed : .needsYou) : nil
        ended = !session.isRunning
        working = session.isWorking
        label = "\(session.name), \(session.status.title.lowercased())" + (session.status.isNew ? ", new" : "")
        self.session = session.id
    }

    init(spec: FaceSpec, size: CGFloat, badge: FaceArt.Badge? = nil, ended: Bool = false, label: String? = nil) {
        self.spec = spec
        self.size = size
        self.badge = badge
        self.ended = ended
        self.label = label
    }

    var body: some View {
        Group {
            if working {
                TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                    face(sway: FaceArt.sway(spec, at: timeline.date))
                }
            } else {
                face(sway: nil)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                let side = FaceArt.badgeSide(size)
                Circle()
                    .fill(badge == .failed ? Ink.failed : Ink.needsYou)
                    .frame(width: side, height: side)
                    .padding(Metric.badgeRing)
                    .background(Ink.content, in: Circle())
                    .alignmentGuide(.trailing) { $0[.trailing] - Metric.badgeRing - 1 }
                    .alignmentGuide(.bottom) { $0[.bottom] - Metric.badgeRing - 1 }
                    .accessibilityHidden(true)
            }
        }
        .overlay { if let session, Self.click != nil { ClickTarget { Self.click?(session) } } }
        .pointerStyle(session == nil || Self.click == nil ? nil : .link)
        .help(session == nil ? label ?? "" : "\(label ?? "Session"): click for its menu")
        .accessibilityElement()
        .accessibilityLabel(label ?? "Session")
        .modifier(FaceActions(session: session))
    }

    private func face(sway: Double?) -> some View {
        Canvas { context, canvas in
            context.withCGContext { ctx in
                FaceArt.draw(spec, in: ctx, rect: CGRect(origin: .zero, size: canvas), ended: ended, sway: sway)
            }
        }
    }
}

/// A click AppKit handles on the press: it acts at once, where SwiftUI would wait out a row's double-click.
struct ClickTarget: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Target { Target() }

    func updateNSView(_ view: Target, context: Context) { view.action = action }

    final class Target: NSView {
        var action: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { action?() }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    }
}

/// VoiceOver presses a session's face as a click does (its menu), or focuses its session.
private struct FaceActions: ViewModifier {
    let session: String?

    func body(content: Content) -> some View {
        if let session, SessionFace.click != nil {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { SessionFace.click?(session) }
                .accessibilityAction(named: "Focus") { SessionFace.doubleClick?(session) }
        } else {
            content
        }
    }
}

/// Faces overlapping (3 at most, then "+n"), or a dashed square when nobody is on it.
struct FaceStack: View {
    let sessions: [SessionItem]
    var size: CGFloat = Metric.faceRow
    var limit = 3

    var body: some View {
        HStack(spacing: -size * 0.3) {
            if sessions.isEmpty {
                RoundedRectangle(cornerRadius: size * FaceArt.corner, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(.tertiary)
                    .frame(width: size, height: size)
                    .help("No session on it")
                    .accessibilityElement()
                    .accessibilityLabel("No session")
            } else {
                ForEach(sessions.prefix(limit)) { session in
                    SessionFace(session, size: size)
                        .padding(1)
                        .background(Ink.content, in: RoundedRectangle(cornerRadius: (size + 2) * FaceArt.corner, style: .continuous))
                }
                if sessions.count > limit {
                    Text("+\(sessions.count - limit)")
                        .kitType(.meta)
                        .foregroundStyle(.secondary)
                        .padding(.leading, size * 0.3 + 2)
                }
            }
        }
    }
}

// MARK: AppKit

/// Faces for AppKit cells (the outline's faces column): overlapping, with badges, or a dashed square.
/// A working session's head sways, unless Reduce Motion is on.
final class FaceStackView: NSView {
    struct Face {
        var spec: FaceSpec
        var badge: FaceArt.Badge?
        var label: String
        var working = false
        var ended = false
        var session: String
    }

    var faces: [Face] = [] {
        didSet {
            needsDisplay = true
            toolTip = faces.isEmpty ? "No session on this task" : faces.map(\.label).joined(separator: "\n")
            setAccessibilityLabel(faces.isEmpty ? "No session" : faces.map(\.label).joined(separator: "; "))
            animate()
        }
    }
    private var link: CADisplayLink?
    var size = Metric.faceRow
    var limit = 3
    /// "+n" after the faces past the limit; off where the column holds `limit` faces only.
    var showsMore = true
    /// A click acts on the faces: the pointing hand over them, and clicks go on to the superview.
    var clickable = false { didSet { if clickable && !tracksHandCursor { trackHandCursor() } } }
    var dimmed = false
    /// VoiceOver's press, as a click: a face's menu, or a new session where there's none.
    var press: (() -> Void)?
    /// VoiceOver's other actions: each face's menu, Start Session….
    var faceActions: [(name: String, run: () -> Void)] = []

    override func accessibilityRole() -> NSAccessibility.Role? { press == nil ? .image : .button }
    override func accessibilityPerformPress() -> Bool { press?(); return press != nil }
    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        faceActions.isEmpty ? nil : faceActions.map { action in NSAccessibilityCustomAction(name: action.name) { action.run(); return true } }
    }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        animate()
    }

    /// Redraws at 30 fps while a shown face works.
    private func animate() {
        let moving = window != nil && faces.prefix(limit).contains { $0.working }
        if moving, link == nil {
            let link = displayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            self.link = link
        } else if !moving, let link {
            link.invalidate()
            self.link = nil
        }
    }

    @objc private func tick() { needsDisplay = true }

    override func cursorUpdate(with event: NSEvent) {
        if clickable { NSCursor.pointingHand.set() } else { super.cursorUpdate(with: event) }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { clickable }

    /// The session whose face is under `point` (this view's coordinates); the one drawn on top wins.
    func session(at point: NSPoint) -> String? {
        let step = size * 0.7
        let y = (bounds.height - size) / 2
        for (index, face) in faces.prefix(limit).enumerated().reversed()
        where NSRect(x: CGFloat(index) * step, y: y, width: size, height: size).contains(point) {
            return face.session
        }
        return nil
    }

    /// The width the faces and their "+n" take.
    var contentWidth: CGFloat { Self.width(faces.count, size: size, limit: limit, more: showsMore) }

    /// The width of `count` faces, overlapping, and their "+n"; one face's when there are none.
    static func width(_ count: Int, size: CGFloat = Metric.faceRow, limit: Int = 3, more: Bool = true) -> CGFloat {
        guard count > 1 else { return size }
        let shown = CGFloat(min(count, limit) - 1) * size * 0.7 + size
        guard count > limit, more else { return shown }
        return shown + 2 + ceil(NSAttributedString(string: "+\(count - limit)", attributes: [.font: KitType.meta.nsFont]).size().width)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let y = (bounds.height - size) / 2
        if faces.isEmpty {
            let rect = CGRect(x: 0.5, y: y + 0.5, width: size - 1, height: size - 1)
            let path = RoundedRectangle(cornerRadius: size * FaceArt.corner, style: .continuous).path(in: rect).cgPath
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.tertiaryLabelColor.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [2, 2])
            ctx.strokePath()
            return
        }
        let step = size * 0.7
        let ring = Ink.contentNS.cgColor
        for (index, face) in faces.prefix(limit).enumerated() {
            let rect = CGRect(x: CGFloat(index) * step, y: y, width: size, height: size)
            if index > 0 {
                ctx.addPath(RoundedRectangle(cornerRadius: (size + 2) * FaceArt.corner, style: .continuous).path(in: rect.insetBy(dx: -1, dy: -1)).cgPath)
                ctx.setFillColor(ring)
                ctx.fillPath()
            }
            FaceArt.draw(face.spec, in: ctx, rect: rect, ended: face.ended, sway: link != nil && face.working ? FaceArt.sway(face.spec, at: .now) : nil)
            if let badge = face.badge { FaceArt.drawBadge(badge, in: ctx, rect: rect, ring: ring) }
        }
        if faces.count > limit, showsMore {
            let text = NSAttributedString(string: "+\(faces.count - limit)", attributes: [
                .font: KitType.meta.nsFont, .foregroundColor: NSColor.secondaryLabelColor,
            ])
            let x = CGFloat(limit - 1) * step + size + 2
            text.draw(at: CGPoint(x: x, y: (bounds.height - text.size().height) / 2))
        }
    }
}
