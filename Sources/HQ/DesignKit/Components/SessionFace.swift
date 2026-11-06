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
        FaceImage(spec: spec, ended: ended, working: working)
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

}

/// The face itself, on Core Animation layers.
private struct FaceImage: NSViewRepresentable {
    let spec: FaceSpec
    let ended: Bool
    let working: Bool

    func makeNSView(context: Context) -> FaceView { FaceView() }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: FaceView, context: Context) -> CGSize? { proposal.replacingUnspecifiedDimensions() }

    func updateNSView(_ view: FaceView, context: Context) { view.show(spec, ended: ended, working: working) }
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
    struct Face: Equatable {
        var spec: FaceSpec
        var badge: FaceArt.Badge?
        var label: String
        var working = false
        var ended = false
        var session: String
    }

    var faces: [Face] = [] {
        didSet {
            toolTip = faces.isEmpty ? "No session on this task" : faces.map(\.label).joined(separator: "\n")
            guard faces != oldValue else { return }
            needsDisplay = true
            setAccessibilityLabel(faces.isEmpty ? "No session" : faces.map(\.label).joined(separator: "; "))
            updateTiles()
        }
    }
    /// The faces shown, each on its tile, the later ones over the earlier.
    private var tiles: [FaceTile] = []
    var faceLayers: [FaceLayer] { tiles.map(\.face) }
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
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTiles()
        if window != nil { for tile in tiles { tile.face.resume() } }
    }

    override func layout() {
        super.layout()
        updateTiles()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateTiles()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTiles()
    }

    /// One tile per face shown, placed and colored for the view's appearance.
    private func updateTiles() {
        guard let layer else { return }
        let shown = Array(faces.prefix(limit))
        while tiles.count > shown.count { tiles.removeLast().removeFromSuperlayer() }
        while tiles.count < shown.count {
            let tile = FaceTile()
            layer.addSublayer(tile)
            tiles.append(tile)
        }
        guard !shown.isEmpty else { return }
        var ring: CGColor = .clear
        var colors: [FaceArt.Badge: CGColor] = [:]
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ring = Ink.contentNS.cgColor
            colors = [.needsYou: FaceArt.color(.needsYou), .failed: FaceArt.color(.failed)]
        }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let y = (bounds.height - size) / 2
        for (index, face) in shown.enumerated() {
            tiles[index].show(face, at: CGPoint(x: CGFloat(index) * size * 0.7, y: y), size: size, ringed: index > 0, content: ring,
                              badge: face.badge.flatMap { colors[$0] }, scale: scale)
        }
    }

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
        // The faces are layers (`FaceTile`); what's left is the "+n".
        let step = size * 0.7
        if faces.count > limit, showsMore {
            let text = NSAttributedString(string: "+\(faces.count - limit)", attributes: [
                .font: KitType.meta.nsFont, .foregroundColor: NSColor.secondaryLabelColor,
            ])
            let x = CGFloat(limit - 1) * step + size + 2
            text.draw(at: CGPoint(x: x, y: (bounds.height - text.size().height) / 2))
        }
    }
}
