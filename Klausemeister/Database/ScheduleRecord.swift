// Klausemeister/Database/ScheduleRecord.swift
import Foundation
import GRDB

/// Persistence row for a saved schedule. Mirrors the `schedules` table
/// from the `v14-schedules` migration. FK on `repoId` cascades from
/// `repositories`, so deleting a repo also wipes its schedules.
struct ScheduleRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    nonisolated static let databaseTableName = "schedules"

    var scheduleId: String
    var repoId: String
    var name: String
    var linearProjectId: String?
    var createdAt: String
    var runAt: String?
}
