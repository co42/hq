import SwiftUI

/// An icon in a block's or a card's top-right corner, under the pointer: Expand on a table or a diagram (T-490), Widen and
/// Narrow on a note's card (T-523). A small glass circle.
struct CornerButton: View {
    let title: String
    let icon: KitIcon
    let help: String
    let anchor: String
    let action: () -> Void

    var body: some View {
        Button(title, icon: icon, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .help(help)
            .ownsItsClicks()
            .uiTestAnchor(anchor)
    }
}
