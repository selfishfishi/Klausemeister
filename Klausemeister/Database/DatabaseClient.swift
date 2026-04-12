// Klausemeister/Database/DatabaseClient.swift
import Dependencies
import Foundation
import GRDB

struct DatabaseClient {
    var getDbQueue: @Sendable () -> DatabaseQueue
    var fetchImportedIssues: @Sendable () async throws -> [ImportedIssueRecord]
    var saveImportedIssue: @Sendable (ImportedIssueRecord) async throws -> Void
    var deleteImportedIssue: @Sendable (_ linearId: String) async throws -> Void
    var updateIssueStatus: @Sendable (_ linearId: String, _ status: String, _ statusId: String, _ statusType: String) async throws -> Void
    var updateIssueFromLinear: @Sendable (ImportedIssueRecord) async throws -> Void
    var batchSaveImportedIssues: @Sendable ([ImportedIssueRecord]) async throws -> Void
    var fetchUnqueuedImportedIssues: @Sendable () async throws -> [ImportedIssueRecord]
    var fetchImportedIssue: @Sendable (_ linearId: String) async throws -> ImportedIssueRecord?
    var fetchImportedIssueByIdentifier: @Sendable (_ identifier: String) async throws -> ImportedIssueRecord?
    var markOrphanedIssues: @Sendable (_ linearIds: [String], _ isOrphaned: Bool) async throws -> Void
    var fetchWorkflowStates: @Sendable () async throws -> [LinearWorkflowStateRecord]
    var saveWorkflowStates: @Sendable (_ records: [LinearWorkflowStateRecord]) async throws -> Void
    var fetchTeams: @Sendable () async throws -> [LinearTeamRecord]
    var saveTeams: @Sendable (_ records: [LinearTeamRecord]) async throws -> Void
    var deleteAllTeams: @Sendable () async throws -> Void
    var deleteIssuesByTeam: @Sendable (_ teamId: String) async throws -> Void
    var deleteTeam: @Sendable (_ teamId: String) async throws -> Void
    var updateTeamFilterVisibility: @Sendable (_ teamId: String, _ isHiddenFromBoard: Bool) async throws -> Void
    var fetchCommandHistory: @Sendable () async throws -> [AppCommand]
    var recordCommandUsed: @Sendable (_ command: AppCommand) async throws -> Void
}

extension DatabaseClient: DependencyKey {
    nonisolated static let liveValue: DatabaseClient = {
        let dbQueue: DatabaseQueue = {
            do {
                let fileManager = FileManager.default
                let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let appDir = appSupport.appendingPathComponent("Klausemeister")
                try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
                let dbQueue = try DatabaseQueue(path: appDir.appendingPathComponent("klausemeister.db").path)
                var migrator = DatabaseMigrator()
                DatabaseMigrations.registerAll(&migrator)
                try migrator.migrate(dbQueue)
                return dbQueue
            } catch {
                fatalError("Failed to initialize database: \(error)")
            }
        }()

        return DatabaseClient(
            getDbQueue: { dbQueue },
            fetchImportedIssues: {
                try await dbQueue.read { db in
                    try ImportedIssueRecord.order(Column("sortOrder").asc).fetchAll(db)
                }
            },
            saveImportedIssue: { record in
                try await dbQueue.write { db in try record.save(db) }
            },
            deleteImportedIssue: { linearId in
                try await dbQueue.write { db in
                    _ = try ImportedIssueRecord.deleteOne(db, key: linearId)
                }
            },
            updateIssueStatus: { linearId, status, statusId, statusType in
                try await dbQueue.write { db in
                    if var record = try ImportedIssueRecord.fetchOne(db, key: linearId) {
                        record.status = status
                        record.statusId = statusId
                        record.statusType = statusType
                        try record.update(db)
                    }
                }
            },
            updateIssueFromLinear: { record in
                try await dbQueue.write { db in try record.save(db) }
            },
            batchSaveImportedIssues: { records in
                try await dbQueue.write { db in
                    for record in records {
                        try record.save(db)
                    }
                }
            },
            fetchUnqueuedImportedIssues: {
                try await dbQueue.read { db in
                    try ImportedIssueRecord.fetchAll(db, sql: """
                        SELECT ii.*
                        FROM imported_issues ii
                        WHERE ii.linearId NOT IN (
                            SELECT issueLinearId FROM worktree_queue_items
                        )
                        ORDER BY ii.sortOrder ASC
                    """)
                }
            },
            fetchImportedIssue: { linearId in
                try await dbQueue.read { db in
                    try ImportedIssueRecord.fetchOne(db, key: linearId)
                }
            },
            fetchImportedIssueByIdentifier: { identifier in
                try await dbQueue.read { db in
                    try ImportedIssueRecord
                        .filter(Column("identifier") == identifier)
                        .fetchOne(db)
                }
            },
            markOrphanedIssues: { linearIds, isOrphaned in
                guard !linearIds.isEmpty else { return }
                try await dbQueue.write { db in
                    let placeholders = Array(repeating: "?", count: linearIds.count).joined(separator: ",")
                    let arguments: [DatabaseValueConvertible] = [isOrphaned] + linearIds
                    try db.execute(
                        sql: "UPDATE imported_issues SET isOrphaned = ? WHERE linearId IN (\(placeholders))",
                        arguments: StatementArguments(arguments)
                    )
                }
            },
            fetchWorkflowStates: {
                try await dbQueue.read { db in
                    try LinearWorkflowStateRecord.fetchAll(db)
                }
            },
            saveWorkflowStates: { records in
                try await dbQueue.write { db in
                    try db.execute(sql: "DELETE FROM linear_workflow_states")
                    for record in records {
                        try record.save(db)
                    }
                }
            },
            fetchTeams: {
                try await dbQueue.read { db in
                    try LinearTeamRecord.fetchAll(db)
                }
            },
            saveTeams: { records in
                try await dbQueue.write { db in
                    try db.execute(sql: "DELETE FROM linear_teams")
                    for record in records {
                        try record.save(db)
                    }
                }
            },
            deleteAllTeams: {
                try await dbQueue.write { db in
                    try db.execute(sql: "DELETE FROM linear_teams")
                }
            },
            deleteIssuesByTeam: { teamId in
                try await dbQueue.write { db in
                    try db.execute(
                        sql: "DELETE FROM imported_issues WHERE teamId = ?",
                        arguments: [teamId]
                    )
                }
            },
            deleteTeam: { teamId in
                try await dbQueue.write { db in
                    _ = try LinearTeamRecord.deleteOne(db, key: teamId)
                }
            },
            updateTeamFilterVisibility: { teamId, isHiddenFromBoard in
                try await dbQueue.write { db in
                    if var record = try LinearTeamRecord.fetchOne(db, key: teamId) {
                        record.isHiddenFromBoard = isHiddenFromBoard
                        try record.update(db)
                    }
                }
            },
            fetchCommandHistory: {
                try await dbQueue.read { db in
                    let records = try CommandPaletteHistoryRecord
                        .order(Column("usedAt").desc)
                        .limit(10)
                        .fetchAll(db)
                    return records.compactMap { record in
                        guard let command = AppCommand(rawValue: record.commandRawValue) else {
                            print(
                                "[CommandPalette] Ignoring unrecognized command in history: '\(record.commandRawValue)'"
                            )
                            return nil
                        }
                        return command
                    }
                }
            },
            recordCommandUsed: { command in
                try await dbQueue.write { db in
                    let now = ISO8601DateFormatter().string(from: Date())
                    if var existing = try CommandPaletteHistoryRecord
                        .fetchOne(db, key: command.rawValue)
                    {
                        existing.usedAt = now
                        existing.useCount += 1
                        try existing.update(db)
                    } else {
                        let record = CommandPaletteHistoryRecord(
                            commandRawValue: command.rawValue,
                            usedAt: now,
                            useCount: 1
                        )
                        try record.insert(db)
                    }
                }
            }
        )
    }()

    nonisolated static let testValue = DatabaseClient(
        // swiftlint:disable:next force_try
        getDbQueue: unimplemented("DatabaseClient.getDbQueue", placeholder: try! DatabaseQueue()),
        fetchImportedIssues: unimplemented("DatabaseClient.fetchImportedIssues"),
        saveImportedIssue: unimplemented("DatabaseClient.saveImportedIssue"),
        deleteImportedIssue: unimplemented("DatabaseClient.deleteImportedIssue"),
        updateIssueStatus: unimplemented("DatabaseClient.updateIssueStatus"),
        updateIssueFromLinear: unimplemented("DatabaseClient.updateIssueFromLinear"),
        batchSaveImportedIssues: unimplemented("DatabaseClient.batchSaveImportedIssues"),
        fetchUnqueuedImportedIssues: unimplemented("DatabaseClient.fetchUnqueuedImportedIssues"),
        fetchImportedIssue: unimplemented("DatabaseClient.fetchImportedIssue"),
        fetchImportedIssueByIdentifier: unimplemented("DatabaseClient.fetchImportedIssueByIdentifier"),
        markOrphanedIssues: unimplemented("DatabaseClient.markOrphanedIssues"),
        fetchWorkflowStates: unimplemented("DatabaseClient.fetchWorkflowStates"),
        saveWorkflowStates: unimplemented("DatabaseClient.saveWorkflowStates"),
        fetchTeams: unimplemented("DatabaseClient.fetchTeams"),
        saveTeams: unimplemented("DatabaseClient.saveTeams"),
        deleteAllTeams: unimplemented("DatabaseClient.deleteAllTeams"),
        deleteIssuesByTeam: unimplemented("DatabaseClient.deleteIssuesByTeam"),
        deleteTeam: unimplemented("DatabaseClient.deleteTeam"),
        updateTeamFilterVisibility: unimplemented("DatabaseClient.updateTeamFilterVisibility"),
        fetchCommandHistory: unimplemented("DatabaseClient.fetchCommandHistory"),
        recordCommandUsed: unimplemented("DatabaseClient.recordCommandUsed")
    )
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}
