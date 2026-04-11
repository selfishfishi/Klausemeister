import SwiftUI

/// Per-stage accent colors drawn from the Everforest palette.
///
/// Lives in the view layer so `MeisterState.swift` can stay pure Foundation
/// at the domain layer (no SwiftUI dependency in the enum itself). The kanban
/// views read this to tint column headers, count badges, accent lines,
/// card borders, and card left bars — giving each stage a distinct visual
/// identity across the board.
extension MeisterState {
    /// Primary accent color for this stage. Matches the Everforest 16-color
    /// palette so the board stays visually consistent with the terminal.
    var tint: Color {
        switch self {
        case .backlog: Color(hex: 0x7FBBB3) // teal
        case .todo: Color(hex: 0xDBBC7F) // gold
        case .inProgress: Color(hex: 0xA7C080) // green
        case .inReview: Color(hex: 0xD699B6) // pink
        case .testing: Color(hex: 0xE69875) // orange
        case .completed: Color(hex: 0x83C092) // mint
        }
    }
}
