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

    /// Cell foreground/border opacity multiplier. `done` is lightly muted
    /// (0.75) — the strikethrough and checkmark badges carry the "done"
    /// signal, so we keep the card legible rather than ghosting it out.
    var displayIntensity: Double {
        switch self {
        case .done: 0.75
        default: 1.0
        }
    }
}
