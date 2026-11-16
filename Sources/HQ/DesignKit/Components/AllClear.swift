import SwiftUI

/// A list with nothing left for the user, and that's worth a moment: Reviews (DESIGN.md §6), the notification center (§11).
struct AllClear: View {
    let title: String
    /// Another empty place than a cleared one (the Archive, T-471): its symbol, quiet, and a line under the title.
    var icon = KitIcon.allReviewed
    var line: String?

    var body: some View {
        VStack(spacing: Space.sm) {
            icon.image
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(icon == .allReviewed ? AnyShapeStyle(Ink.done) : AnyShapeStyle(.secondary))
            Text(title).kitType(.titleStrong)
            if let line { Text(line).kitType(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, minHeight: Metric.allReviewed, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
