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
    nonisolated var displayName: String {
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

// MARK: - Default Mapping Heuristic

extension MeisterState {
    /// Computes the default MeisterState for a Linear workflow state using
    /// the two-tier heuristic: name match first, then type fallback.
    ///
    /// Used for auto-seeding the per-team mapping table and as a fallback
    /// when no explicit mapping exists.
    nonisolated static func defaultMapping(for linearState: LinearWorkflowState) -> MeisterState? {
        defaultMapping(name: linearState.name, statusType: linearState.type)
    }

    /// Core heuristic shared between seeding and the `LinearIssue.meisterState`
    /// computed property.
    nonisolated static func defaultMapping(name: String, statusType: String) -> MeisterState? {
        let needle = name.lowercased()
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

extension LinearIssue {
    /// Resolves this issue to a canonical `MeisterState` using the default
    /// heuristic. Prefer the per-team mapping table when available.
    var meisterState: MeisterState? {
        MeisterState.defaultMapping(name: status, statusType: statusType)
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
    nonisolated func linearState(in teamStates: [LinearWorkflowState]) -> LinearWorkflowState? {
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
