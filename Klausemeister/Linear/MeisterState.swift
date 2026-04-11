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

// MARK: - Mapping (default, pre-per-team configuration)

extension LinearIssue {
    /// Resolves this issue to a canonical `MeisterState`.
    ///
    /// The mapping is two-tiered:
    /// 1. Exact name match (case-insensitive) against `MeisterState.displayName`
    ///    — catches the common names ("Backlog", "Todo", "In Progress",
    ///    "In Review", "Testing").
    /// 2. Linear state-type fallback — anything typed `backlog`/`unstarted`/
    ///    `started`/`completed` that didn't match by name falls into the
    ///    canonical stage for that type.
    ///
    /// Returns `nil` for issues whose state type is `canceled` or otherwise
    /// unrecognized — those do not belong on the kanban. Canceled issues are
    /// already filtered at the API layer; this handles stale orphaned records
    /// still in the local cache.
    ///
    /// Per-team overrides will replace this default in a later change.
    var meisterState: MeisterState? {
        let needle = status.lowercased()
        for state in MeisterState.allCases where state.displayName.lowercased() == needle {
            return state
        }
        switch statusType {
        case "backlog": return .backlog
        case "unstarted": return .todo
        case "started": return .inProgress
        case "completed": return .completed
        default: return nil
        }
    }
}

extension MeisterState {
    /// Finds the Linear workflow state that represents this canonical stage
    /// on a given team, for use when writing status updates back to Linear.
    ///
    /// Uses the mirror of `LinearIssue.meisterState`: exact name match first,
    /// then type-based fallback. When multiple Linear states share a type
    /// (e.g. KLA's `Spec`/`In Progress`/`In Review`/`Testing` are all
    /// `started`), the fallback picks the first by workflow position.
    func linearState(in teamStates: [LinearWorkflowState]) -> LinearWorkflowState? {
        let needle = displayName.lowercased()
        if let byName = teamStates.first(where: { $0.name.lowercased() == needle }) {
            return byName
        }
        let fallbackType = switch self {
        case .backlog: "backlog"
        case .todo: "unstarted"
        case .inProgress, .inReview, .testing: "started"
        case .completed: "completed"
        }
        return teamStates
            .filter { $0.type == fallbackType }
            .min(by: { $0.position < $1.position })
    }
}
