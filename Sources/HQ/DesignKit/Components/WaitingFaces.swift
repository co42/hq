import SwiftUI

/// The toolbar's who waits (DESIGN.md §3, T-655): the faces of what waits on the user, newest first, on orange glass;
/// three, then "+2", a menu of the rest. A click acts on one; the newest breathes while the bell does.
struct WaitingFaces: View {
    let items: [WaitingItem]
    var breathing = false
    let action: (WaitingItem) -> Void

    var body: some View {
        let shown = items.prefix(Metric.waitingShown)
        let rest = items.dropFirst(Metric.waitingShown)
        HStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                Button { action(item) } label: {
                    WaitingFace(item: item)
                        .background {
                            if index == 0, breathing {
                                BreathingGlow(peak: AnyView(RoundedRectangle(cornerRadius: Metric.faceWaiting * FaceArt.corner, style: .continuous)
                                    .fill(Ink.needsYou.opacity(0.3))
                                    .shadow(color: Ink.needsYou.opacity(0.7), radius: Metric.glowRadius / 2)))
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .buttonStyle(WaitingButtonStyle())
                .help(item.help)
                .accessibilityLabel("\(item.name), \(item.what)")
                .uiTestAnchor("waiting:\(item.id)")
            }
            if !rest.isEmpty {
                Menu {
                    ForEach(Array(rest)) { item in
                        Button { action(item) } label: {
                            Label { Text(Self.menuTitle(item)) } icon: { Image(nsImage: Self.menuImage(item)) }
                        }
                    }
                } label: {
                    Text("+\(rest.count)")
                        .kitType(.titleStrong)
                        .foregroundStyle(Ink.needsYouText)
                        .padding(.horizontal, Space.xs + 2)
                        .frame(minWidth: Metric.waitingButton, minHeight: Metric.sectionBarItem)
                        .contentShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("\(rest.map(\.name).joined(separator: ", ")): a menu of the rest")
                .accessibilityLabel("\(rest.count) more waiting")
                .uiTestAnchor("waiting-more")
            }
        }
        .padding(Metric.lineGap)
        .glassEffect(.regular.tint(Ink.needsYouGlass), in: Capsule())
        .fixedSize()
    }

    /// "registry: retry budget · Asks a question", the name cut as the menu bar's Focus items are.
    static func menuTitle(_ item: WaitingItem) -> String {
        let name = item.name.count > MenuBarMenu.nameLimit ? item.name.prefix(MenuBarMenu.nameLimit - 1).trimmingCharacters(in: .whitespaces) + "…" : item.name
        let what = item.what.count > Self.whatLimit ? item.what.prefix(Self.whatLimit - 1).trimmingCharacters(in: .whitespaces) + "…" : item.what
        return "\(name) · \(what)"
    }

    static let whatLimit = 50

    static func menuImage(_ item: WaitingItem) -> NSImage {
        if let session = item.session { return FaceArt.image(session.face, size: Metric.faceMenu, ended: !session.isRunning) }
        return (item.glyph == nil ? KitIcon.reminder : KitIcon.bellFill).nsImage ?? NSImage()
    }
}

/// One face, its glyph as a badge; a reminder or a ping with no session shows its tile.
private struct WaitingFace: View {
    let item: WaitingItem

    var body: some View {
        if let session = item.session {
            SessionFace(waiting: session, glyph: item.glyph)
        } else {
            KindTile(icon: item.glyph == nil ? .reminder : .bellFill, tint: Ink.needsYou, size: Metric.faceWaiting)
        }
    }
}

/// A face's button: a plate under the pointer, deeper while pressed.
private struct WaitingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WaitingPlate(pressed: configuration.isPressed) { configuration.label }
    }
}

private struct WaitingPlate<Label: View>: View {
    let pressed: Bool
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        label
            .frame(width: Metric.waitingButton, height: Metric.sectionBarItem)
            .background(hovering || pressed ? Ink.hoverFill : .clear, in: shape)
            .contentShape(shape)
            .scaleEffect(pressed ? 0.96 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.hover, value: hovering)
            .animation(Motion.hover, value: pressed)
    }
}
