// Klausemeister/Worktrees/ScheduleModels.swift
import Foundation

/// A saved assignment plan: a named collection of scheduled issues across
/// the repo's worktrees. Produced by `/klause-schedule` and persisted via
/// the `v14-schedules` migration. Consumed by the gantt overlay (KLA-198)
/// and the sidebar pills (KLA-197).
struct Schedule: Equatable, Identifiable {
    /// Stable UUID. Matches `ScheduleRecord.scheduleId`.
    let id: String
    var repoId: String
    var name: String
    /// Linear project the schedule was built from. `nil` for ad-hoc schedules.
    var linearProjectId: String?
    /// ISO-8601 timestamp. Matches the `createdAt` convention of other records.
    var createdAt: String
    /// ISO-8601 timestamp of the first `runSchedule`. `nil` until the schedule
    /// has been run — lets the UI distinguish planned from executed schedules.
    var runAt: String?
    var items: [ScheduleItem]
}

struct ScheduleItem: Equatable, Identifiable {
    let id: String
    var scheduleId: String
    var worktreeId: String
    var issueLinearId: String
    var issueIdentifier: String
    var issueTitle: String
    /// Per-worktree ordering, 0-indexed.
    var position: Int
    /// Dependency-graph weight used by `/klause-schedule`; also rendered in
    /// the gantt overlay as column span.
    var weight: Int
    var blockedByIssueLinearIds: [String]
    var status: ScheduleItemStatus
}

enum ScheduleItemStatus: String, Codable, Equatable {
    case planned
    case queued
    case inProgress
    case done
}

extension Schedule {
    /// Compose from the DB-layer records. Records carry the durable shape of
    /// the `schedules` / `schedule_items` tables; the reducer works with the
    /// domain types above so views never see raw rows.
    init(record: ScheduleRecord, items: [ScheduleItem]) {
        id = record.scheduleId
        repoId = record.repoId
        name = record.name
        linearProjectId = record.linearProjectId
        createdAt = record.createdAt
        runAt = record.runAt
        self.items = items
    }

    /// Count of items that have reached the `done` terminal state — used to
    /// drive the sidebar pill's progress indicator without any extra queries.
    var doneCount: Int {
        items.count(where: { $0.status == .done })
    }
}

extension ScheduleItem {
    init(record: ScheduleItemRecord) {
        id = record.scheduleItemId
        scheduleId = record.scheduleId
        worktreeId = record.worktreeId
        issueLinearId = record.issueLinearId
        issueIdentifier = record.issueIdentifier
        issueTitle = record.issueTitle
        position = record.position
        weight = record.weight
        // `blockedByIssueLinearIds` is stored as a JSON-encoded string to keep
        // the schema flat — decode defensively so a malformed row doesn't
        // crash the sidebar load.
        if let data = record.blockedByIssueLinearIds.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data)
        {
            blockedByIssueLinearIds = decoded
        } else {
            blockedByIssueLinearIds = []
        }
        status = ScheduleItemStatus(rawValue: record.status) ?? .planned
    }
}
