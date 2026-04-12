// Klausemeister/Database/WorktreeQueueItemRecord.swift
import Foundation
import GRDB

struct WorktreeQueueItemRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "worktree_queue_items"

    var id: String
    var worktreeId: String
    var issueLinearId: String
    var queuePosition: QueuePosition
    var sortOrder: Int
    var assignedAt: String
    var completedAt: String?
}
