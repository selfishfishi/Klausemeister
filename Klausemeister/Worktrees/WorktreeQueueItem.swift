// Klausemeister/Worktrees/WorktreeQueueItem.swift
import Foundation

/// Domain representation of a queued work item assigned to a worktree.
/// Mirrors `WorktreeQueueItemRecord` but without the GRDB conformance so
/// the type can cross the dependency boundary (e.g. appear in action
/// enums and state). See `WorktreeQueueItemRecord.init(from:)` for the
/// write-side mapping.
struct WorktreeQueueItem: Equatable, Identifiable {
    let id: String
    let worktreeId: String
    let issueLinearId: String
    let queuePosition: QueuePosition
    let sortOrder: Int

    nonisolated init(from record: WorktreeQueueItemRecord) {
        id = record.id
        worktreeId = record.worktreeId
        issueLinearId = record.issueLinearId
        queuePosition = record.queuePosition
        sortOrder = record.sortOrder
    }
}
