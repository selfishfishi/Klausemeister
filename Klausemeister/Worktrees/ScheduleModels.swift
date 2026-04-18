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
