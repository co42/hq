import SwiftUI

/// The states every part draws. The gallery forces one, so each shows in a snapshot.
enum PartState: String, CaseIterable, Identifiable {
    case rest, hover, pressed, selected, selectedUnfocused, selectedInactive, focused, disabled, dragging

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selectedUnfocused: "selected, list unfocused"
        case .selectedInactive: "selected, window inactive"
        default: rawValue
        }
    }

    var isSelected: Bool { self == .selected || self == .selectedUnfocused || self == .selectedInactive }
}

extension EnvironmentValues {
    @Entry var forcedPartState: PartState?
}

/// Selection drawn by a part itself (the board isn't a List), matching a List's.
struct SelectionFill: View {
    let state: PartState
    var radius: CGFloat = Radius.card

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch state {
        case .selected: shape.fill(Ink.accent)
        case .selectedUnfocused, .selectedInactive: shape.fill(Ink.selectionInactive)
        case .hover, .pressed: shape.fill(Ink.hoverFill)
        default: shape.fill(.clear)
        }
    }
}
