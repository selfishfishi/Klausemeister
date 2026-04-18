// Klausemeister/Linear/StateMapping.swift
import Foundation

/// Domain representation of one row in `team_state_mappings`: a single
/// Linear workflow state mapped onto a `MeisterState` for a given team.
/// Mirrors `StateMappingRecord` but without the GRDB conformance so
/// the type can cross the dependency boundary (reducer state, action
/// payloads, etc.).
struct StateMapping: Equatable, Identifiable {
    /// Composite identifier used for `Identifiable`. Matches the
    /// uniqueness key we enforce in SQL (`teamId × linearStateId`).
    var id: String {
        "\(teamId):\(linearStateId)"
    }

    let teamId: String
    let linearStateId: String
    let linearStateName: String
    let meisterState: MeisterState

    nonisolated init(
        teamId: String,
        linearStateId: String,
        linearStateName: String,
        meisterState: MeisterState
    ) {
        self.teamId = teamId
        self.linearStateId = linearStateId
        self.linearStateName = linearStateName
        self.meisterState = meisterState
    }

    /// Domain projection of a `StateMappingRecord`. Returns `nil` when
    /// the raw string no longer parses to a known `MeisterState` (stale
    /// rows left behind by an enum rename would be silently skipped
    /// instead of crashing at read-time).
    nonisolated init?(from record: StateMappingRecord) {
        guard let resolved = MeisterState(rawValue: record.meisterState) else { return nil }
        self.init(
            teamId: record.teamId,
            linearStateId: record.linearStateId,
            linearStateName: record.linearStateName,
            meisterState: resolved
        )
    }
}

extension StateMappingRecord {
    nonisolated init(from mapping: StateMapping) {
        self.init(
            teamId: mapping.teamId,
            linearStateId: mapping.linearStateId,
            linearStateName: mapping.linearStateName,
            meisterState: mapping.meisterState.rawValue
        )
    }
}
