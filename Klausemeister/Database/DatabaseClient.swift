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
    var fetchImportedIssuesExcludingWorktreeQueues: @Sendable () async throws -> [ImportedIssueRecord]
    var fetchImportedIssue: @Sendable (_ linearId: String) async throws -> ImportedIssueRecord?
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
            fetchImportedIssuesExcludingWorktreeQueues: {
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
            }
        )
    }()

    nonisolated static let testValue = DatabaseClient(
        getDbQueue: unimplemented("DatabaseClient.getDbQueue"),
        fetchImportedIssues: unimplemented("DatabaseClient.fetchImportedIssues"),
        saveImportedIssue: unimplemented("DatabaseClient.saveImportedIssue"),
        deleteImportedIssue: unimplemented("DatabaseClient.deleteImportedIssue"),
        updateIssueStatus: unimplemented("DatabaseClient.updateIssueStatus"),
        updateIssueFromLinear: unimplemented("DatabaseClient.updateIssueFromLinear"),
        batchSaveImportedIssues: unimplemented("DatabaseClient.batchSaveImportedIssues"),
        fetchImportedIssuesExcludingWorktreeQueues: unimplemented("DatabaseClient.fetchImportedIssuesExcludingWorktreeQueues"),
        fetchImportedIssue: unimplemented("DatabaseClient.fetchImportedIssue")
    )
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClient.self] }
        set { self[DatabaseClient.self] = newValue }
    }
}
