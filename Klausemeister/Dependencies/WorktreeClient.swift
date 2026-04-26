// Klausemeister/Dependencies/WorktreeClient.swift
// swiftlint:disable file_length
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

    // MARK: - Saved schedules (KLA-195)

    /// Every schedule for a repo, each populated with its items. Ordered
    /// newest-first by `createdAt`. GRDB `*Record` types are mapped to
    /// domain types inside `liveValue` so the boundary stays clean.
    var fetchSchedules: @Sendable (_ repoId: String) async throws -> [Schedule]
    /// Full schedule with items. Returns `nil` if the schedule does not exist.
    var fetchSchedule: @Sendable (_ scheduleId: String) async throws -> Schedule?
    var fetchScheduleItems: @Sendable (_ scheduleId: String) async throws -> [ScheduleItem]
    /// Cross-schedule lookup by issue id. Returns every item whose
    /// `issueLinearId` is in the input set, across all schedules. Used by
    /// `getNextItem` (KLA-200) to skip inbox items whose blockers aren't yet
    /// `done`. Backed by the `idx_schedule_items_issue_linear_id` index.
    var fetchScheduleItemsByIssueLinearIds: @Sendable (
        _ issueLinearIds: [String]
    ) async throws -> [ScheduleItem]
    /// Single-transaction write: replaces any existing items for the same
    /// `scheduleId` and upserts the schedule row. Keeps the on-disk view
    /// consistent — a partial write would leave orphans behind.
    var saveSchedule: @Sendable (_ schedule: Schedule) async throws -> Void
    var deleteSchedule: @Sendable (_ scheduleId: String) async throws -> Void
    var updateScheduleItemStatus: @Sendable (
        _ scheduleItemId: String,
        _ status: String
    ) async throws -> Void
    /// Stamps `runAt` on the schedule row. Called by `runSchedule` after
    /// the items have been enqueued so the UI knows the schedule has fired.
    var markScheduleRun: @Sendable (
        _ scheduleId: String,
        _ runAt: String
    ) async throws -> Void
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
                        repoId: repoId,
                        meisterAgent: MeisterAgent.claude.rawValue
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
                            repoId: repoId,
                            meisterAgent: MeisterAgent.claude.rawValue
                        )
                        try record.save(db)
                        inserted.append(WorktreesLoadedWorktree(from: record))
                    }

                    return SyncResult(inserted: inserted, deletedWorktreeIds: deletedIds)
                }
            },

            fetchSchedules: { repoId in
                try await dbQueue.read { db in
                    let scheduleRecords = try ScheduleRecord
                        .filter(Column("repoId") == repoId)
                        .order(Column("createdAt").desc)
                        .fetchAll(db)
                    return try scheduleRecords.map { record in
                        let itemRecords = try ScheduleItemRecord
                            .filter(Column("scheduleId") == record.scheduleId)
                            .order(Column("worktreeId"), Column("position").asc)
                            .fetchAll(db)
                        return Schedule(
                            from: record,
                            items: itemRecords.map(ScheduleItem.init(from:))
                        )
                    }
                }
            },

            fetchSchedule: { scheduleId in
                try await dbQueue.read { db in
                    guard let record = try ScheduleRecord.fetchOne(db, key: scheduleId) else {
                        return nil
                    }
                    let itemRecords = try ScheduleItemRecord
                        .filter(Column("scheduleId") == scheduleId)
                        .order(Column("worktreeId"), Column("position").asc)
                        .fetchAll(db)
                    return Schedule(
                        from: record,
                        items: itemRecords.map(ScheduleItem.init(from:))
                    )
                }
            },

            fetchScheduleItems: { scheduleId in
                try await dbQueue.read { db in
                    try ScheduleItemRecord
                        .filter(Column("scheduleId") == scheduleId)
                        .order(Column("worktreeId"), Column("position").asc)
                        .fetchAll(db)
                        .map(ScheduleItem.init(from:))
                }
            },

            fetchScheduleItemsByIssueLinearIds: { issueLinearIds in
                guard !issueLinearIds.isEmpty else { return [] }
                return try await dbQueue.read { db in
                    // `issueLinearIds` is app-supplied, never user input, so
                    // interpolation via `IN ?` is safe here. GRDB binds the
                    // array as individual parameters.
                    try ScheduleItemRecord
                        .filter(issueLinearIds.contains(Column("issueLinearId")))
                        .fetchAll(db)
                        .map(ScheduleItem.init(from:))
                }
            },

            saveSchedule: { schedule in
                try await dbQueue.write { db in
                    // Single transaction: upsert the schedule row, then
                    // replace its items wholesale. Items are replaced, not
                    // merged, because a schedule's composition is considered
                    // atomic — callers regenerate the full plan on each save.
                    let scheduleRecord = ScheduleRecord(from: schedule)
                    try scheduleRecord.save(db)
                    try db.execute(
                        sql: "DELETE FROM schedule_items WHERE scheduleId = ?",
                        arguments: [schedule.id]
                    )
                    for item in schedule.items {
                        try ScheduleItemRecord(from: item).insert(db)
                    }
                }
            },

            deleteSchedule: { scheduleId in
                try await dbQueue.write { db in
                    _ = try ScheduleRecord.deleteOne(db, key: scheduleId)
                    // FK ON DELETE CASCADE handles `schedule_items`.
                }
            },

            updateScheduleItemStatus: { scheduleItemId, status in
                try await dbQueue.write { db in
                    try db.execute(
                        sql: "UPDATE schedule_items SET status = ? WHERE scheduleItemId = ?",
                        arguments: [status, scheduleItemId]
                    )
                }
            },

            markScheduleRun: { scheduleId, runAt in
                try await dbQueue.write { db in
                    try db.execute(
                        sql: "UPDATE schedules SET runAt = ? WHERE scheduleId = ?",
                        arguments: [runAt, scheduleId]
                    )
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
        assignIssueToWorktree: unimplemented("WorktreeClient.assignIssueToWorktree"),
        moveToOutbox: unimplemented("WorktreeClient.moveToOutbox"),
        removeFromQueue: unimplemented("WorktreeClient.removeFromQueue"),
        moveToProcessing: unimplemented("WorktreeClient.moveToProcessing"),
        findQueueItemId: unimplemented("WorktreeClient.findQueueItemId"),
        reorderQueue: unimplemented("WorktreeClient.reorderQueue"),
        moveToProcessingByIssueId: unimplemented("WorktreeClient.moveToProcessingByIssueId"),
        moveToOutboxByIssueId: unimplemented("WorktreeClient.moveToOutboxByIssueId"),
        removeFromQueueByIssueId: unimplemented("WorktreeClient.removeFromQueueByIssueId"),
        syncWorktreesForRepo: unimplemented("WorktreeClient.syncWorktreesForRepo"),
        fetchSchedules: unimplemented("WorktreeClient.fetchSchedules"),
        fetchSchedule: unimplemented("WorktreeClient.fetchSchedule"),
        fetchScheduleItems: unimplemented("WorktreeClient.fetchScheduleItems"),
        fetchScheduleItemsByIssueLinearIds: unimplemented(
            "WorktreeClient.fetchScheduleItemsByIssueLinearIds"
        ),
        saveSchedule: unimplemented("WorktreeClient.saveSchedule"),
        deleteSchedule: unimplemented("WorktreeClient.deleteSchedule"),
        updateScheduleItemStatus: unimplemented("WorktreeClient.updateScheduleItemStatus"),
        markScheduleRun: unimplemented("WorktreeClient.markScheduleRun")
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
