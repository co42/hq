import SwiftUI

/// The line that joins a stack's kind tiles (DESIGN.md §6), from the first row's middle to the last's, centered on
/// its leading edge: it runs behind the rows, so the tiles sit on it.
struct StackRail: View {
    let rows: Int
    let rowHeight: CGFloat

    var body: some View {
        Ink.stackRail
            .frame(width: Metric.stackRail, height: CGFloat(rows - 1) * rowHeight)
            .clipShape(Capsule())
            .padding(.top, rowHeight / 2)
            .padding(.leading, -Metric.stackRail / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
