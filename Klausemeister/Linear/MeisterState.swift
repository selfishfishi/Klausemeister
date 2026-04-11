import Foundation

/// Canonical workflow stages used throughout Klausemeister.
///
/// These 6 stages are fixed in the app, independent of any individual
/// Linear team's workflow. Each Linear team's statuses (which are
/// customizable per team) will be mapped onto these stages — many-to-one,
/// so a single `MeisterState` can be backed by multiple Linear statuses
/// on the same team (e.g. `.todo` may cover both "Todo" and "Definition").
///
/// This type establishes the vocabulary only. The mapping, its persistence,
/// and its use by the kanban board are introduced in follow-up changes.
enum MeisterState: String, CaseIterable, Hashable, Identifiable {
    case backlog
    case todo
    case inProgress
    case inReview
    case testing
    case completed

    var id: String {
        rawValue
    }

    /// Human-readable title shown in UI (kanban columns, filters, menus).
    var displayName: String {
        switch self {
        case .backlog: "Backlog"
        case .todo: "Todo"
        case .inProgress: "In Progress"
        case .inReview: "In Review"
        case .testing: "Testing"
        case .completed: "Completed"
        }
    }
}
