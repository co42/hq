import AppKit
import HQKit
import SwiftUI

/// Tasks and the Backlog (DESIGN.md §7): one outline. Its headers, filters and quick-add lines are rows of it.
struct TasksSection: View {
    let width: CGFloat
    @Environment(AppModel.self) private var model

    var body: some View {
        TaskOutline(width: width)
            .frame(width: width)
    }
}
