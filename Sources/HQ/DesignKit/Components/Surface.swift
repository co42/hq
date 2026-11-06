import SwiftUI

/// What the sky says: nothing waits, something is new, or something needs the user.
enum SkyMood: Equatable {
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
            base(glow)
                .phaseAnimator([Self.hold, Self.peak]) { content, level in
                    content.shadow(color: glow.opacity(level), radius: Metric.glowRadius)
                } animation: { _ in
                    .easeInOut(duration: Motion.blinkHalf)
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

extension View {
    /// Sits the view on a raised card.
    func surface(radius: CGFloat = Radius.card, glow: Color? = nil, breathing: Bool = false, lifted: Bool = false, tint: Color? = nil) -> some View {
        modifier(SurfaceModifier(radius: radius, glow: glow, breathing: breathing, lifted: lifted, tint: tint))
    }
}

/// The soft sky over the top of the page: a mesh of three colors that fades into the canvas.
/// Its colors follow the day's state and change slowly; it never loops. The toolbar's and the
/// section bar's glass refract it.
struct SkyView: View {
    let mood: SkyMood
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = Ink.sky(mood)
        let top = Ink.skyOpacity(scheme)
        MeshGradient(
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
        .frame(height: Metric.skyHeight)
        .animation(Motion.sky, value: mood)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
