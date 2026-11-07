import SwiftUI

/// A list with nothing left for the user, and that's worth a moment: Reviews (DESIGN.md §6), the notification center (§11).
struct AllClear: View {
    let title: String

    var body: some View {
        VStack(spacing: Space.sm) {
            KitIcon.allReviewed.image
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Ink.done)
            Text(title).kitType(.titleStrong)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, minHeight: Metric.allReviewed, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
