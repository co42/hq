import SwiftUI

/// Tasks (DESIGN.md §7): one outline, its header over the outline's first row so it pins as the other sections' do.
struct TasksSection: View {
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            TaskOutline(width: width)
            OutlineHeader()
                .frame(height: Metric.outlineHeader)
        }
        .frame(width: width)
    }
}
