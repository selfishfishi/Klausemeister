// Klausemeister/Dependencies/WorktreeClient.swift
import Dependencies
import Foundation
import GRDB

struct WorktreeClient {
    // MARK: - Repository CRUD

    var fetchRepositories: @Sendable () async throws -> [RepositoryRecord]
    var addRepository: @Sendable (_ name: String, _ path: String) async throws -> RepositoryRecord
    var removeRepository: @Sendable (_ repoId: String) async throws -> Void

    // MARK: - Worktree CRUD

    var fetchWorktrees: @Sendable () async throws -> [WorktreeRecord]
    var createWorktree: @Sendable (_ name: String, _ gitWorktreePath: String, _ repoId: String) async throws -> WorktreeRecord
    var deleteWorktree: @Sendable (_ worktreeId: String) async throws -> Void
    var updateWorktreeOrder: @Sendable (_ orderedIds: [String]) async throws -> Void

    // MARK: - Queue Management

    var fetchQueueItems: @Sendable (_ worktreeId: String) async throws -> [WorktreeQueueItemRecord]
    var assignIssueToWorktree: @Sendable (_ issueLinearId: String, _ worktreeId: String) async throws -> Void
    var moveToOutbox: @Sendable (_ queueItemId: String) async throws -> Void
    var removeFromQueue: @Sendable (_ queueItemId: String) async throws -> Void
    var moveToProcessing: @Sendable (_ queueItemId: String) async throws -> Void
    var reorderQueue: @Sendable (_ worktreeId: String, _ queuePosition: String, _ itemIds: [String]) async throws -> Void
}

// MARK: - Live & Test values

extension WorktreeClient: DependencyKey {
    nonisolated static let liveValue: WorktreeClient = {
        @Dependency(\.databaseClient) var databaseClient
        let dbQueue = databaseClient.getDbQueue()

        return WorktreeClient(
            fetchRepositories: {
                try await dbQueue.read { db in
                    try RepositoryRecord.order(Column("sortOrder").asc).fetchAll(db)
                }
            },

            addRepository: { name, path in
                try await dbQueue.write { db in
                    let maxSort = try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM repositories") ?? -1
                    let record = RepositoryRecord(
                        repoId: UUID().uuidString,
                        name: name,
                        path: path,
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        sortOrder: maxSort + 1
                    )
                    try record.save(db)
                    return record
                }
            },

            removeRepository: { repoId in
                try await dbQueue.write { db in
                    try db.execute(
                        sql: "DELETE FROM worktrees WHERE repoId = ?",
                        arguments: [repoId]
                    )
                    _ = try RepositoryRecord.deleteOne(db, key: ["repoId": repoId])
                }
            },

            fetchWorktrees: {
                try await dbQueue.read { db in
                    try WorktreeRecord.order(Column("sortOrder").asc).fetchAll(db)
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
                        createdAt: ISO8601DateFormatter().string(from: Date()),
                        repoId: repoId
                    )
                    try record.save(db)
                    return record
                }
            },

            deleteWorktree: { worktreeId in
                try await dbQueue.write { db in
                    _ = try WorktreeRecord.deleteOne(db, key: ["worktreeId": worktreeId])
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

            fetchQueueItems: { worktreeId in
                try await dbQueue.read { db in
                    try WorktreeQueueItemRecord
                        .filter(Column("worktreeId") == worktreeId)
                        .order(Column("queuePosition").asc, Column("sortOrder").asc)
                        .fetchAll(db)
                }
            },

            assignIssueToWorktree: { issueLinearId, worktreeId in
                try await dbQueue.write { db in
                    let alreadyQueued = try WorktreeQueueItemRecord
                        .filter(Column("worktreeId") == worktreeId)
                        .filter(Column("issueLinearId") == issueLinearId)
                        .filter(sql: "queuePosition IN ('inbox', 'processing', 'outbox')")
                        .fetchCount(db) > 0
                    guard !alreadyQueued else { return }

                    let maxSort = try Int.fetchOne(
                        db,
                        sql: "SELECT MAX(sortOrder) FROM worktree_queue_items WHERE worktreeId = ? AND queuePosition = 'inbox'",
                        arguments: [worktreeId]
                    ) ?? -1
                    let record = WorktreeQueueItemRecord(
                        id: UUID().uuidString,
                        worktreeId: worktreeId,
                        issueLinearId: issueLinearId,
                        queuePosition: "inbox",
                        sortOrder: maxSort + 1,
                        assignedAt: ISO8601DateFormatter().string(from: Date()),
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
                    record.queuePosition = "outbox"
                    record.completedAt = ISO8601DateFormatter().string(from: Date())
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
                    record.queuePosition = "processing"
                    try record.update(db)
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
        updateWorktreeOrder: unimplemented("WorktreeClient.updateWorktreeOrder"),
        fetchQueueItems: unimplemented("WorktreeClient.fetchQueueItems"),
        assignIssueToWorktree: unimplemented("WorktreeClient.assignIssueToWorktree"),
        moveToOutbox: unimplemented("WorktreeClient.moveToOutbox"),
        removeFromQueue: unimplemented("WorktreeClient.removeFromQueue"),
        moveToProcessing: unimplemented("WorktreeClient.moveToProcessing"),
        reorderQueue: unimplemented("WorktreeClient.reorderQueue")
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
