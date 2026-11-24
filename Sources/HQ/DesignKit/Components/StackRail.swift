import SwiftUI

/// The line that joins a stack's kind tiles (DESIGN.md §6), from the first row's middle to the last's, centered on
/// its leading edge: it runs behind the rows, so the tiles sit on it. A stack cut short runs on to its bottom edge (T-767).
struct StackRail: View {
    let rows: Int
    let rowHeight: CGFloat
    var continues = false

    var body: some View {
        Ink.stackRail
            .frame(width: Metric.stackRail, height: (CGFloat(rows) - (continues ? 0.5 : 1)) * rowHeight)
            .clipShape(Capsule())
            .padding(.top, rowHeight / 2)
            .padding(.leading, -Metric.stackRail / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
