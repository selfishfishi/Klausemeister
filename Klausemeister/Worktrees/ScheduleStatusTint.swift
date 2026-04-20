import SwiftUI

/// Per-status accent colors for `ScheduleItem`s rendered in the gantt overlay.
///
/// Mirrors `MeisterState.tint` so the gantt cells share visual vocabulary with
/// the kanban board and swimlanes — `inProgress` is the same green, `queued`
/// echoes the kanban `todo` gold, etc. Lives in the view layer so the
/// `ScheduleItemStatus` enum stays pure Foundation.
extension ScheduleItemStatus {
    /// Primary accent color for this status. Drawn from the Everforest palette
    /// to stay consistent with `MeisterStateTint`.
    var tint: Color {
        switch self {
        case .planned: Color(hex: 0x7FBBB3) // teal — dormant
        case .queued: Color(hex: 0xDBBC7F) // gold — waiting in inbox
        case .inProgress: Color(hex: 0xA7C080) // green — actively running
        case .done: Color(hex: 0x83C092) // mint — finished
        }
    }

    /// Cell foreground/border opacity multiplier. `done` recedes (0.55) so the
    /// eye is drawn to in-flight and pending work; everything else renders at
    /// full strength.
    var displayIntensity: Double {
        switch self {
        case .done: 0.55
        default: 1.0
        }
    }
}
