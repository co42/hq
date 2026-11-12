import SwiftUI

/// Where a list's empty state would be while its items are on their way: a small spinner and what loads.
struct LoadingLine: View {
    let title: String

    var body: some View {
        HStack(spacing: Space.sm) {
            ProgressView().controlSize(.small)
            Text(title).kitType(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
