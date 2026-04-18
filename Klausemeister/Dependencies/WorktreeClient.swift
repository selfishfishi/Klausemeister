// Klausemeister/Dependencies/WorktreeClient.swift
import Dependencies
import Foundation
import GRDB

/// Persistence wrapper for the `repositories`, `worktrees`, and
/// `worktree_queue_items` tables. Shares `DatabaseClient`'s GRDB queue
/// (see `liveValue`). Closures are grouped by concern:
///
/// - **Repository CRUD** — register / remove top-level repos from disk.
/// - **Worktree CRUD** — create / rename / reorder / delete worktrees.
/// - **Queue management** — move an issue between inbox / processing /
///   outbox slots; reorder within a slot.
/// - **Drag-and-drop convenience** — issue-ID-based variants of the
///   queue operations that look up the queue-item-id internally.
/// - **Discovery / sync** — reconcile the DB's worktree rows against
///   what `git worktree list` reports on disk.
///
/// All writes are serialized through the shared `DatabaseQueue`, so
/// callers never need to worry about GRDB locking. Throwing closures
/// surface GRDB / filesystem errors unchanged; reducers must `catch`.
///
/// All fetch/create closures return domain types — no GRDB `*Record`
/// types cross the dependency boundary. Reads map internally inside
/// `liveValue` so reducers never see persistence shapes.
struct WorktreeClient {
    // MARK: - Repository CRUD

    var fetchRepositories: @Sendable () async throws -> [Repository]
    var addRepository: @Sendable (_ name: String, _ path: String) async throws -> Repository
    var removeRepository: @Sendable (_ repoId: String) async throws -> Void

    // MARK: - Worktree CRUD

    var fetchWorktrees: @Sendable () async throws -> [WorktreesLoadedWorktree]
    var createWorktree: @Sendable (_ name: String, _ gitWorktreePath: String, _ repoId: String) async throws -> WorktreesLoadedWorktree
    var deleteWorktree: @Sendable (_ worktreeId: String) async throws -> Void
    var renameWorktree: @Sendable (_ worktreeId: String, _ newName: String) async throws -> Void
    var updateWorktreeOrder: @Sendable (_ orderedIds: [String]) async throws -> Void
    var ignoreWorktreePath: @Sendable (_ path: String, _ repoId: String) async throws -> Void

    // MARK: - Queue Management

    var fetchQueueItems: @Sendable (_ worktreeId: String) async throws -> [WorktreeQueueItem]
    /// Single-query fetch of every queue item across every worktree. Callers
    /// needing a full snapshot (app launch, MCP `listWorktrees`) should use
    /// this instead of looping `fetchQueueItems` per worktree — one read on
    /// the shared `DatabaseQueue` instead of N.
    var fetchAllQueueItems: @Sendable () async throws -> [WorktreeQueueItem]
    var assignIssueToWorktree: @Sendable (_ issueLinearId: String, _ worktreeId: String) async throws -> Void
    var moveToOutbox: @Sendable (_ queueItemId: String) async throws -> Void
    var removeFromQueue: @Sendable (_ queueItemId: String) async throws -> Void
    var moveToProcessing: @Sendable (_ queueItemId: String) async throws -> Void
    var findQueueItemId: @Sendable (_ issueLinearId: String, _ worktreeId: String) async throws -> String?
    var reorderQueue: @Sendable (_ worktreeId: String, _ queuePosition: QueuePosition, _ itemIds: [String]) async throws -> Void

    // MARK: - Convenience (issue-ID-based, for drag-and-drop)

    var moveToProcessingByIssueId: @Sendable (_ issueLinearId: String, _ worktreeId: String) async throws -> Void
    var moveToOutboxByIssueId: @Sendable (_ issueLinearId: String, _ worktreeId: String) async throws -> Void
    var removeFromQueueByIssueId: @Sendable (_ issueLinearId: String, _ worktreeId: String) async throws -> Void

    // MARK: - Discovery / Sync

    var syncWorktreesForRepo: @Sendable (
        _ repoId: String,
        _ entries: [GitClient.WorktreeListEntry]
    ) async throws -> SyncResult

    struct SyncResult: Equatable {
        let inserted: [WorktreesLoadedWorktree]
        let deletedWorktreeIds: [String]
    }
}

// MARK: - Live & Test values

extension WorktreeClient: DependencyKey {
    nonisolated static let liveValue: WorktreeClient = {
        @Dependency(\.databaseClient) var databaseClient
        let dbQueue = databaseClient.getDbQueue()

        return WorktreeClient(
            fetchRepositories: {
                try await dbQueue.read { db in
                    try RepositoryRecord.order(Column("sortOrder").asc)
                        .fetchAll(db)
                        .map(Repository.init(from:))
                }
            },

            addRepository: { name, path in
                try await dbQueue.write { db in
                    let maxSort = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM repositories") ?? -1
                    let record = RepositoryRecord(
                        repoId: UUID().uuidString,
                        name: name,
                        path: path,
                        createdAt: ISO8601DateFormatter.shared.string(from: Date()),
                        sortOrder: maxSort + 1
                    )
                    try record.save(db)
                    return Repository(from: record)
                }
            },

            removeRepository: { repoId in
                try await dbQueue.write { db in
                    try db.execute(
                        sql: "DELETE FROM worktrees WHERE repoId = ?",
                        arguments: [repoId]
                    )
                    try db.execute(
                        sql: "DELETE FROM ignored_worktree_paths WHERE repoId = ?",
                        arguments: [repoId]
                    )
                    _ = try RepositoryRecord.deleteOne(db, key: ["repoId": repoId])
                }
            },

            fetchWorktrees: {
                try await dbQueue.read { db in
                    try WorktreeRecord.order(Column("sortOrder").asc)
                        .fetchAll(db)
                        .map(WorktreesLoadedWorktree.init(from:))
                }
            },

            createWorktree: { name, gitWorktreePath, repoId in
                try await dbQueue.write { db in
                    let maxSort = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM worktrees") ?? -1
                    let record = WorktreeRecord(
                        worktreeId: UUID().uuidString,
                        name: name,
                        sortOrder: maxSort + 1,
                        gitWorktreePath: gitWorktreePath,
                        createdAt: ISO8601DateFormatter.shared.string(from: Date()),
                        repoId: repoId
                    )
                    try record.save(db)
                    return WorktreesLoadedWorktree(from: record)
                }
            },

            deleteWorktree: { worktreeId in
                try await dbQueue.write { db in
                    _ = try WorktreeRecord.deleteOne(db, key: ["worktreeId": worktreeId])
                }
            },

            renameWorktree: { worktreeId, newName in
                try await dbQueue.write { db in
                    try db.execute(
                        sql: "UPDATE worktrees SET name = ? WHERE worktreeId = ?",
                        arguments: [newName, worktreeId]
                    )
                }
            },

            updateWorktreeOrder: { orderedIds in
                try await dbQueue.write { db in
                    for (index, worktreeId) in orderedIds.enumerated() {
                        try db.execute(
                            sql: "UPDATE worktrees SET sortOrder = ? WHERE worktreeId = ?",
                            arguments: [index, worktreeId]
                        )
                    }
                }
            },

            ignoreWorktreePath: { path, repoId in
                try await dbQueue.write { db in
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO ignored_worktree_paths (path, repoId) VALUES (?, ?)",
                        arguments: [path, repoId]
                    )
                }
            },

            fetchQueueItems: { worktreeId in
                try await dbQueue.read { db in
                    try WorktreeQueueItemRecord
                        .filter(Column("worktreeId") == worktreeId)
                        .order(Column("queuePosition").asc, Column("sortOrder").asc)
                        .fetchAll(db)
                        .map(WorktreeQueueItem.init(from:))
                }
            },

            fetchAllQueueItems: {
                try await dbQueue.read { db in
                    try WorktreeQueueItemRecord
                        .order(Column("queuePosition").asc, Column("sortOrder").asc)
                        .fetchAll(db)
                        .map(WorktreeQueueItem.init(from:))
                }
            },

            assignIssueToWorktree: { issueLinearId, worktreeId in
                try await dbQueue.write { db in
                    let alreadyQueued = try WorktreeQueueItemRecord
                        .filter(Column("worktreeId") == worktreeId)
                        .filter(Column("issueLinearId") == issueLinearId)
                        .fetchCount(db) > 0
                    guard !alreadyQueued else { return }

                    let maxSort = try Int.fetchOne(
                        db,
                        sql: "SELECT MAX(sortOrder) FROM worktree_queue_items WHERE worktreeId = ? AND queuePosition = ?",
                        arguments: [worktreeId, QueuePosition.inbox]
                    ) ?? -1
                    let record = WorktreeQueueItemRecord(
                        id: UUID().uuidString,
                        worktreeId: worktreeId,
                        issueLinearId: issueLinearId,
                        queuePosition: QueuePosition.inbox,
                        sortOrder: maxSort + 1,
                        assignedAt: ISO8601DateFormatter.shared.string(from: Date()),
                        completedAt: nil
                    )
                    try record.save(db)
                }
            },

            moveToOutbox: { queueItemId in
                try await dbQueue.write { db in
                    guard var record = try WorktreeQueueItemRecord.fetchOne(db, key: queueItemId) else {
                        throw WorktreeClientError.queueItemNotFound(queueItemId)
                    }
                    record.queuePosition = QueuePosition.outbox
                    record.completedAt = ISO8601DateFormatter.shared.string(from: Date())
                    try record.update(db)
                }
            },

            removeFromQueue: { queueItemId in
                try await dbQueue.write { db in
                    _ = try WorktreeQueueItemRecord.deleteOne(db, key: queueItemId)
                }
            },

            moveToProcessing: { queueItemId in
                try await dbQueue.write { db in
                    guard var record = try WorktreeQueueItemRecord.fetchOne(db, key: queueItemId) else {
                        throw WorktreeClientError.queueItemNotFound(queueItemId)
                    }
                    record.queuePosition = QueuePosition.processing
                    try record.update(db)
                }
            },

            findQueueItemId: { issueLinearId, worktreeId in
                try await dbQueue.read { db in
                    try WorktreeQueueItemRecord
                        .filter(Column("worktreeId") == worktreeId)
                        .filter(Column("issueLinearId") == issueLinearId)
                        .fetchOne(db)?
                        .id
                }
            },

            reorderQueue: { worktreeId, queuePosition, itemIds in
                try await dbQueue.write { db in
                    for (index, itemId) in itemIds.enumerated() {
                        try db.execute(
                            sql: "UPDATE worktree_queue_items SET sortOrder = ? WHERE id = ? AND worktreeId = ? AND queuePosition = ?",
                            arguments: [index, itemId, worktreeId, queuePosition]
                        )
                    }
                }
            },

            moveToProcessingByIssueId: { issueLinearId, worktreeId in
                try await dbQueue.write { db in
                    guard var record = try WorktreeQueueItemRecord
                        .filter(Column("worktreeId") == worktreeId)
                        .filter(Column("issueLinearId") == issueLinearId)
                        .filter(Column("queuePosition") == QueuePosition.inbox)
                        .fetchOne(db)
                    else {
                        throw WorktreeClientError.queueItemNotFound(issueLinearId)
                    }
                    record.queuePosition = QueuePosition.processing
                    try record.update(db)
                }
            },

            moveToOutboxByIssueId: { issueLinearId, worktreeId in
                try await dbQueue.write { db in
                    guard var record = try WorktreeQueueItemRecord
                        .filter(Column("worktreeId") == worktreeId)
                        .filter(Column("issueLinearId") == issueLinearId)
                        .filter(sql: "queuePosition IN (?, ?)", arguments: [
                            QueuePosition.inbox,
                            QueuePosition.processing
                        ])
                        .fetchOne(db)
                    else {
                        throw WorktreeClientError.queueItemNotFound(issueLinearId)
                    }
                    record.queuePosition = QueuePosition.outbox
                    record.completedAt = ISO8601DateFormatter.shared.string(from: Date())
                    try record.update(db)
                }
            },

            removeFromQueueByIssueId: { issueLinearId, worktreeId in
                try await dbQueue.write { db in
                    try db.execute(
                        sql: "DELETE FROM worktree_queue_items WHERE issueLinearId = ? AND worktreeId = ?",
                        arguments: [issueLinearId, worktreeId]
                    )
                }
            },

            syncWorktreesForRepo: { repoId, entries in
                try await dbQueue.write { db in
                    // Defense in depth: never sync main worktrees, even if caller forgets to filter
                    let secondaryEntries = entries.filter { !$0.isMain }
                    let existing = try WorktreeRecord
                        .filter(Column("repoId") == repoId)
                        .fetchAll(db)
                    let existingByPath = Dictionary(
                        uniqueKeysWithValues: existing.map { ($0.gitWorktreePath, $0) }
                    )
                    let entryPaths = Set(secondaryEntries.map(\.path))

                    // Paths the user explicitly removed — never re-import these
                    let ignoredPaths = try Set(
                        String.fetchAll(
                            db,
                            sql: "SELECT path FROM ignored_worktree_paths WHERE repoId = ?",
                            arguments: [repoId]
                        )
                    )

                    // Delete orphaned records (in DB, no longer on disk)
                    var deletedIds: [String] = []
                    for record in existing where !entryPaths.contains(record.gitWorktreePath) {
                        try record.delete(db)
                        deletedIds.append(record.worktreeId)
                    }

                    // Insert new records (on disk, not in DB, not ignored)
                    var inserted: [WorktreesLoadedWorktree] = []
                    var maxSort = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM worktrees") ?? -1
                    for entry in secondaryEntries
                        where existingByPath[entry.path] == nil && !ignoredPaths.contains(entry.path)
                    {
                        maxSort += 1
                        let name = URL(fileURLWithPath: entry.path).lastPathComponent
                        let record = WorktreeRecord(
                            worktreeId: UUID().uuidString,
                            name: name,
                            sortOrder: maxSort,
                            gitWorktreePath: entry.path,
                            createdAt: ISO8601DateFormatter.shared.string(from: Date()),
                            repoId: repoId
                        )
                        try record.save(db)
                        inserted.append(WorktreesLoadedWorktree(from: record))
                    }

                    return SyncResult(inserted: inserted, deletedWorktreeIds: deletedIds)
                }
            }
        )
    }()

    nonisolated static let testValue = WorktreeClient(
        fetchRepositories: unimplemented("WorktreeClient.fetchRepositories"),
        addRepository: unimplemented("WorktreeClient.addRepository"),
        removeRepository: unimplemented("WorktreeClient.removeRepository"),
        fetchWorktrees: unimplemented("WorktreeClient.fetchWorktrees"),
        createWorktree: unimplemented("WorktreeClient.createWorktree"),
        deleteWorktree: unimplemented("WorktreeClient.deleteWorktree"),
        renameWorktree: unimplemented("WorktreeClient.renameWorktree"),
        updateWorktreeOrder: unimplemented("WorktreeClient.updateWorktreeOrder"),
        ignoreWorktreePath: unimplemented("WorktreeClient.ignoreWorktreePath"),
        fetchQueueItems: unimplemented("WorktreeClient.fetchQueueItems"),
        fetchAllQueueItems: unimplemented("WorktreeClient.fetchAllQueueItems"),
        assignIssueToWorktree: unimplemented("WorktreeClient.assignIssueToWorktree"),
        moveToOutbox: unimplemented("WorktreeClient.moveToOutbox"),
        removeFromQueue: unimplemented("WorktreeClient.removeFromQueue"),
        moveToProcessing: unimplemented("WorktreeClient.moveToProcessing"),
        findQueueItemId: unimplemented("WorktreeClient.findQueueItemId"),
        reorderQueue: unimplemented("WorktreeClient.reorderQueue"),
        moveToProcessingByIssueId: unimplemented("WorktreeClient.moveToProcessingByIssueId"),
        moveToOutboxByIssueId: unimplemented("WorktreeClient.moveToOutboxByIssueId"),
        removeFromQueueByIssueId: unimplemented("WorktreeClient.removeFromQueueByIssueId"),
        syncWorktreesForRepo: unimplemented("WorktreeClient.syncWorktreesForRepo")
    )
}

enum WorktreeClientError: Error, Equatable {
    case queueItemNotFound(String)
}

extension DependencyValues {
    var worktreeClient: WorktreeClient {
        get { self[WorktreeClient.self] }
        set { self[WorktreeClient.self] = newValue }
    }
}
