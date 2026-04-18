// Klausemeister/Database/DatabaseClient.swift
import Dependencies
import Foundation
import GRDB

/// Persistence wrapper for every table this app owns except repositories /
/// worktrees / queue (those live in `WorktreeClient`) and team↔state
/// mappings (which live in `StateMappingClient`). Holds the single
/// `DatabaseQueue` shared with every other persistence client.
///
/// Closures fall into four concerns:
///
/// - **Imported issues** — Linear issues cached locally for the kanban.
///   `batchSaveImportedIssues` is used by sync; `updateIssueFromLinear`
///   and `updateIssueStatus` by live edits.
/// - **Workflow states / teams** — Linear metadata that backs the per-
///   team state mapping editor and the team filter UI.
/// - **Command history** — powers the command palette's "recent".
/// - **Hidden projects / orphaned issues** — persistent board filters
///   and sync bookkeeping.
///
/// `liveValue` performs the schema migration at first access via
/// `DatabaseMigrations.registerAll`; a failure to migrate `fatalError`s
/// because the app cannot start with a broken database.
///
/// All fetch/save closures speak in domain types (`LinearIssue`,
/// `LinearWorkflowState`, `LinearTeam`). Record→Domain mapping happens
/// inside `liveValue`; GRDB types never cross the dependency boundary.
struct DatabaseClient {
    var getDbQueue: @Sendable () -> DatabaseQueue
    var fetchImportedIssues: @Sendable () async throws -> [LinearIssue]
    var saveImportedIssue: @Sendable (_ issue: LinearIssue, _ importedAt: Date) async throws -> Void
    var deleteImportedIssue: @Sendable (_ linearId: String) async throws -> Void
    var updateIssueStatus: @Sendable (_ linearId: String, _ status: String, _ statusId: String, _ statusType: String) async throws -> Void
    var updateIssueFromLinear: @Sendable (_ issue: LinearIssue, _ importedAt: Date) async throws -> Void
    var batchSaveImportedIssues: @Sendable (_ issues: [LinearIssue], _ importedAt: Date) async throws -> Void
    var fetchUnqueuedImportedIssues: @Sendable () async throws -> [LinearIssue]
    var fetchImportedIssue: @Sendable (_ linearId: String) async throws -> LinearIssue?
    var fetchImportedIssueByIdentifier: @Sendable (_ identifier: String) async throws -> LinearIssue?
    var markOrphanedIssues: @Sendable (_ linearIds: [String], _ isOrphaned: Bool) async throws -> Void
    var fetchWorkflowStates: @Sendable () async throws -> [LinearWorkflowState]
    /// Timestamp of the most-recent `saveWorkflowStates`, used to decide
    /// whether to refresh from Linear. Returns `nil` when the cache is empty.
    var lastWorkflowStateFetch: @Sendable () async throws -> Date?
    var saveWorkflowStates: @Sendable (_ states: [LinearWorkflowState], _ fetchedAt: Date) async throws -> Void
    var fetchTeams: @Sendable () async throws -> [LinearTeam]
    var saveTeams: @Sendable (_ teams: [LinearTeam]) async throws -> Void
    var deleteAllTeams: @Sendable () async throws -> Void
    var deleteIssuesByTeam: @Sendable (_ teamId: String) async throws -> Void
    var deleteTeam: @Sendable (_ teamId: String) async throws -> Void
    var updateTeamFilterVisibility: @Sendable (_ teamId: String, _ isHiddenFromBoard: Bool) async throws -> Void
    var fetchCommandHistory: @Sendable () async throws -> [AppCommand]
    var recordCommandUsed: @Sendable (_ command: AppCommand) async throws -> Void
    var fetchHiddenProjects: @Sendable () async throws -> Set<String>
    var setProjectHidden: @Sendable (_ projectName: String, _ isHidden: Bool) async throws -> Void
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
                    try ImportedIssueRecord.order(Column("sortOrder").asc)
                        .fetchAll(db)
                        .map(LinearIssue.init(from:))
                }
            },
            saveImportedIssue: { issue, importedAt in
                try await dbQueue.write { db in
                    try ImportedIssueRecord(from: issue, importedAt: importedAt).save(db)
                }
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
            updateIssueFromLinear: { issue, importedAt in
                try await dbQueue.write { db in
                    try ImportedIssueRecord(from: issue, importedAt: importedAt).save(db)
                }
            },
            batchSaveImportedIssues: { issues, importedAt in
                try await dbQueue.write { db in
                    for issue in issues {
                        try ImportedIssueRecord(from: issue, importedAt: importedAt).save(db)
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
                    .map(LinearIssue.init(from:))
                }
            },
            fetchImportedIssue: { linearId in
                try await dbQueue.read { db in
                    try ImportedIssueRecord.fetchOne(db, key: linearId).map(LinearIssue.init(from:))
                }
            },
            fetchImportedIssueByIdentifier: { identifier in
                try await dbQueue.read { db in
                    try ImportedIssueRecord
                        .filter(Column("identifier") == identifier)
                        .fetchOne(db)
                        .map(LinearIssue.init(from:))
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
                        .map(LinearWorkflowState.init(from:))
                }
            },
            lastWorkflowStateFetch: {
                try await dbQueue.read { db in
                    try String.fetchOne(
                        db,
                        sql: "SELECT fetchedAt FROM linear_workflow_states ORDER BY fetchedAt DESC LIMIT 1"
                    ).flatMap { ISO8601DateFormatter.shared.date(from: $0) }
                }
            },
            saveWorkflowStates: { states, fetchedAt in
                try await dbQueue.write { db in
                    // Authoritative replacement: prune stale rows first so
                    // workflow states that were removed upstream don't linger.
                    // Then upsert. The whole block is one transaction; for the
                    // typical ~50-row state set this is not a measurable cost.
                    try db.execute(sql: "DELETE FROM linear_workflow_states")
                    for state in states {
                        try LinearWorkflowStateRecord(from: state, fetchedAt: fetchedAt)
                            .insert(db, onConflict: .replace)
                    }
                }
            },
            fetchTeams: {
                try await dbQueue.read { db in
                    try LinearTeamRecord.fetchAll(db).map(LinearTeam.init(from:))
                }
            },
            saveTeams: { teams in
                try await dbQueue.write { db in
                    // Authoritative replacement: prune teams removed upstream
                    // before upserting. `TeamSettingsFeature` relies on this
                    // semantic when the user toggles a team off and re-saves.
                    try db.execute(sql: "DELETE FROM linear_teams")
                    for team in teams {
                        try LinearTeamRecord(from: team).insert(db, onConflict: .replace)
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
                    let now = ISO8601DateFormatter.shared.string(from: Date())
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
            },
            fetchHiddenProjects: {
                try await dbQueue.read { db in
                    let records = try HiddenProjectRecord.fetchAll(db)
                    return Set(records.map(\.projectName))
                }
            },
            setProjectHidden: { projectName, isHidden in
                try await dbQueue.write { db in
                    if isHidden {
                        try HiddenProjectRecord(projectName: projectName)
                            .insert(db, onConflict: .ignore)
                    } else {
                        _ = try HiddenProjectRecord.deleteOne(db, key: projectName)
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
        lastWorkflowStateFetch: unimplemented("DatabaseClient.lastWorkflowStateFetch", placeholder: nil),
        saveWorkflowStates: unimplemented("DatabaseClient.saveWorkflowStates"),
        fetchTeams: unimplemented("DatabaseClient.fetchTeams"),
        saveTeams: unimplemented("DatabaseClient.saveTeams"),
        deleteAllTeams: unimplemented("DatabaseClient.deleteAllTeams"),
        deleteIssuesByTeam: unimplemented("DatabaseClient.deleteIssuesByTeam"),
        deleteTeam: unimplemented("DatabaseClient.deleteTeam"),
        updateTeamFilterVisibility: unimplemented("DatabaseClient.updateTeamFilterVisibility"),
        fetchCommandHistory: unimplemented("DatabaseClient.fetchCommandHistory"),
        recordCommandUsed: unimplemented("DatabaseClient.recordCommandUsed"),
        fetchHiddenProjects: unimplemented("DatabaseClient.fetchHiddenProjects"),
        setProjectHidden: unimplemented("DatabaseClient.setProjectHidden")
    )
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}
