import SwiftUI

/// The toolbar's bell (DESIGN.md §3, §11): a plain bell when nothing waits; the update count as a quiet badge; the
/// count of what needs the user as a prominent one on a filled orange bell, breathing until they open the center.
struct NotificationBell: View {
    let needs: Int
    let updates: Int
    var breathing = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Notifications", icon: needs > 0 ? .bellFill : .bell)
                .labelStyle(.iconOnly)
                .foregroundStyle(needs > 0 ? AnyShapeStyle(Ink.needsYou) : AnyShapeStyle(.primary))
                .background {
                    if needs > 0, breathing {
                        BreathingGlow(peak: AnyView(Circle().fill(Ink.needsYou.opacity(0.3))
                            .shadow(color: Ink.needsYou.opacity(0.7), radius: Metric.glowRadius)))
                            .allowsHitTesting(false)
                    }
                }
        }
        .badge(needs > 0 ? needs : updates)
        .badgeProminence(needs > 0 ? .increased : .decreased)
        .accessibilityLabel(needs > 0 ? "Notifications, \(needs) need you, \(updates) updates" : updates > 0 ? "Notifications, \(updates) updates" : "Notifications")
    }
}
