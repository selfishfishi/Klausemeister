// Klausemeister/Database/ScheduleItemRecord.swift
import Foundation
import GRDB

/// Persistence row for one item in a saved schedule. Mirrors the
/// `schedule_items` table from the `v14-schedules` migration. FKs on
/// `scheduleId`, `worktreeId`, and `issueLinearId` all cascade — deleting
/// any of those upstream rows wipes the corresponding schedule_items.
struct ScheduleItemRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "schedule_items"

    var scheduleItemId: String
    var scheduleId: String
    var worktreeId: String
    var issueLinearId: String
    var issueIdentifier: String
    var issueTitle: String
    var position: Int
    var weight: Int
    /// JSON-encoded `[String]`. Decoded into
    /// `ScheduleItem.blockedByIssueLinearIds` at the domain-conversion boundary.
    var blockedByIssueLinearIds: String
    /// Raw `ScheduleItemStatus` raw-value string (`planned` / `queued` /
    /// `inProgress` / `done`). Stored as text so the DB survives enum renames.
    var status: String
}
