// Klausemeister/MCP/WorkflowStateResolver.swift
import Dependencies
import Foundation

/// Resolves Linear workflow-state references to team-specific state UUIDs
/// required by `LinearAPIClient.updateIssueStatus`.
///
/// Resolution uses the per-team mapping table first (which maps
/// `MeisterState` → Linear state UUID per team), falling back to
/// a case-insensitive name match against the workflow states cache.
enum WorkflowStateResolver {
    /// Look up a state UUID for a given team and case-insensitive state name.
    ///
    /// Tries mapping-table resolution first: if `stateName` matches a
    /// `MeisterState.displayName`, resolves via the mapping table to
    /// find the team-specific Linear state. Falls back to a direct
    /// name match against the workflow states cache.
    static func resolve(
        teamId: String,
        stateName: String
    ) async throws -> String? {
        @Dependency(\.stateMappingClient) var stateMappingClient
        @Dependency(\.databaseClient) var databaseClient

        // 1. Try mapping table: if stateName is a MeisterState displayName,
        //    find the mapped Linear state for this team.
        //    Catch errors locally so the name-match fallback still runs.
        let needle = stateName.lowercased()
        if let meisterState = MeisterState.allCases.first(
            where: { $0.displayName.lowercased() == needle }
        ) {
            if let mappings = try? await stateMappingClient.fetchForTeam(teamId),
               let mapped = mappings.first(where: { $0.meisterState == meisterState })
            {
                return mapped.linearStateId
            }
        }

        // 2. Fallback: direct name match against workflow states cache
        let states = try await databaseClient.fetchWorkflowStates()
        return states.first { record in
            record.teamId == teamId && record.name.lowercased() == needle
        }?.id
    }
}
