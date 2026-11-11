import SwiftUI

/// A session's role: a label chip, the masks in the role's color (DESIGN.md §7). Its line in the tooltip.
struct RoleChip: View {
    let role: RoleItem

    var body: some View {
        LabelChip(text: role.name, color: role.color, icon: .role)
            .help(role.line.isEmpty ? "Role: \(role.name)" : "Role: \(role.name). \(role.line)")
            .accessibilityLabel("Role: \(role.name)")
    }
}
