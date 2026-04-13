import Dependencies
import Foundation
import GRDB

/// Per-team mapping of Linear workflow states to MeisterState stages.
///
/// Each Linear team can have its workflow states mapped to the 6 fixed
/// `MeisterState` stages. The mapping is seeded automatically during sync
/// using the name-match + type-fallback heuristic, and users can override
/// it via the mapping editor.
struct StateMappingClient {
    var fetchAll: @Sendable () async throws -> [StateMappingRecord]
    var fetchForTeam: @Sendable (_ teamId: String) async throws -> [StateMappingRecord]
    var saveMappingTable: @Sendable (
        _ mappings: StateMappingTable,
        _ workflowStatesByTeam: WorkflowStatesByTeam
    ) async throws -> Void
    var seedMappings: @Sendable (_ records: [StateMappingRecord]) async throws -> Void
}

// MARK: - Seeding Logic

extension StateMappingClient {
    /// Computes seed records for workflow states that don't yet have a mapping.
    /// Pure function — no side effects, fully testable.
    nonisolated static func computeSeedRecords(
        freshStates: [LinearWorkflowState],
        existingMappings: [StateMappingRecord]
    ) -> [StateMappingRecord] {
        let existingKeys = Set(existingMappings.map { "\($0.teamId):\($0.linearStateId)" })
        return freshStates.compactMap { workflowState in
            let key = "\(workflowState.teamId):\(workflowState.id)"
            guard !existingKeys.contains(key) else { return nil }
            guard let meisterState = MeisterState.defaultMapping(for: workflowState) else { return nil }
            return StateMappingRecord(
                teamId: workflowState.teamId,
                linearStateId: workflowState.id,
                linearStateName: workflowState.name,
                meisterState: meisterState.rawValue
            )
        }
    }
}

// MARK: - StateMappingTable Helpers

/// Nested dictionary for O(1) forward lookups: teamId → linearStateId → MeisterState.
typealias StateMappingTable = [String: [String: MeisterState]]

extension StateMappingTable {
    /// Builds the lookup table from flat records.
    nonisolated static func from(_ records: [StateMappingRecord]) -> StateMappingTable {
        var table: StateMappingTable = [:]
        for record in records {
            guard let state = MeisterState(rawValue: record.meisterState) else { continue }
            table[record.teamId, default: [:]][record.linearStateId] = state
        }
        return table
    }
}

// MARK: - Live & Test Values

extension StateMappingClient: DependencyKey {
    nonisolated static let liveValue: StateMappingClient = {
        @Dependency(\.databaseClient) var databaseClient
        let dbQueue = databaseClient.getDbQueue()

        return StateMappingClient(
            fetchAll: {
                try await dbQueue.read { db in
                    try StateMappingRecord.fetchAll(db)
                }
            },
            fetchForTeam: { teamId in
                try await dbQueue.read { db in
                    try StateMappingRecord.fetchAll(
                        db,
                        sql: "SELECT * FROM team_state_mappings WHERE teamId = ?",
                        arguments: [teamId]
                    )
                }
            },
            saveMappingTable: { mappings, workflowStatesByTeam in
                var records: [StateMappingRecord] = []
                for (teamId, stateMap) in mappings {
                    for (linearStateId, meisterState) in stateMap {
                        let name = workflowStatesByTeam[teamId]?
                            .first { $0.id == linearStateId }?.name ?? ""
                        records.append(StateMappingRecord(
                            teamId: teamId,
                            linearStateId: linearStateId,
                            linearStateName: name,
                            meisterState: meisterState.rawValue
                        ))
                    }
                }
                let finalRecords = records
                try await dbQueue.write { db in
                    // Delete existing mappings for affected teams, then insert fresh
                    for teamId in mappings.keys {
                        try db.execute(
                            sql: "DELETE FROM team_state_mappings WHERE teamId = ?",
                            arguments: [teamId]
                        )
                    }
                    for record in finalRecords {
                        try record.insert(db)
                    }
                }
            },
            seedMappings: { records in
                try await dbQueue.write { db in
                    for record in records {
                        try record.insert(db, onConflict: .ignore)
                    }
                }
            }
        )
    }()

    nonisolated static let testValue = StateMappingClient(
        fetchAll: unimplemented("StateMappingClient.fetchAll"),
        fetchForTeam: unimplemented("StateMappingClient.fetchForTeam"),
        saveMappingTable: unimplemented("StateMappingClient.saveMappingTable"),
        seedMappings: unimplemented("StateMappingClient.seedMappings")
    )
}

extension DependencyValues {
    var stateMappingClient: StateMappingClient {
        get { self[StateMappingClient.self] }
        set { self[StateMappingClient.self] = newValue }
    }
}
