import SwiftUI

/// Waiting for your review, empty: nothing waits on the user, and that's worth a moment (DESIGN.md §6).
struct AllReviewed: View {
    var body: some View {
        VStack(spacing: Space.sm) {
            KitIcon.allReviewed.image
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Ink.done)
            Text("All reviewed").kitType(.titleStrong)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, minHeight: Metric.allReviewed, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
