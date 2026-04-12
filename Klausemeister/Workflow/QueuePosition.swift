// Klausemeister/Workflow/QueuePosition.swift
import Foundation
import GRDB

/// The three physical positions an issue can occupy within a worktree's queue.
///
/// Maps 1:1 to the `queuePosition` text column in the `worktree_queue_items`
/// table. Raw values match the existing DB strings so no migration is needed.
/// `DatabaseValueConvertible` lets GRDB store/fetch this enum directly,
/// eliminating `.rawValue` at every comparison and assignment site.
enum QueuePosition: String, CaseIterable, Equatable, Hashable, DatabaseValueConvertible {
    case inbox
    case processing
    case outbox
}
