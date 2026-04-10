// Klausemeister/MCP/WorkflowStateResolver.swift
import Dependencies
import Foundation

/// Resolves a Linear workflow-state name (e.g. `"Todo"`, `"In Progress"`, `"Done"`)
/// to the team-specific state UUID required by `LinearAPIClient.updateIssueStatus`.
///
/// Linear workflow states are per-team — each team has its own copies of the
/// standard states with distinct UUIDs. The local cache in
/// `DatabaseClient.fetchWorkflowStates()` holds every team's states; this resolver
/// looks up the right one for a given `(teamId, name)` pair.
///
/// Implemented as a static function on a namespace enum and tested directly
/// via `withDependencies`.
enum WorkflowStateResolver {
    /// Look up a state UUID for a given team and case-insensitive state name.
    ///
    /// - Parameters:
    ///   - teamId: Linear team UUID (from `ImportedIssueRecord.teamId`).
    ///   - stateName: Human-readable state name as the master Claude Code knows it.
    /// - Returns: The state UUID, or `nil` if no matching state exists for the team.
    /// - Throws: Whatever `databaseClient.fetchWorkflowStates` throws.
    static func resolve(
        teamId: String,
        stateName: String
    ) async throws -> String? {
        @Dependency(\.databaseClient) var databaseClient
        let states = try await databaseClient.fetchWorkflowStates()
        let needle = stateName.lowercased()
        return states.first { record in
            record.teamId == teamId && record.name.lowercased() == needle
        }?.id
    }
}
