// Klausemeister/Database/RecordConversions.swift
import Foundation

// Mapping between GRDB persistence records and the domain types that
// cross the dependency boundary (reducer state, actions, etc.). Keeping
// these in one file makes it easy to find "the write-side" of any read
// that appears in a reducer effect.
//
// All conversions are `nonisolated` so they can be called from the
// nonisolated `liveValue` of dependency clients without actor hops.

// MARK: - LinearWorkflowState ↔ LinearWorkflowStateRecord

extension LinearWorkflowState {
    nonisolated init(from record: LinearWorkflowStateRecord) {
        self.init(
            id: record.id,
            name: record.name,
            type: record.type,
            position: record.position,
            teamId: record.teamId
        )
    }
}

extension LinearWorkflowStateRecord {
    nonisolated init(from state: LinearWorkflowState, fetchedAt: Date) {
        self.init(
            id: state.id,
            teamId: state.teamId,
            name: state.name,
            type: state.type,
            position: state.position,
            fetchedAt: ISO8601DateFormatter.shared.string(from: fetchedAt)
        )
    }
}

// MARK: - LinearIssue ↔ ImportedIssueRecord

extension LinearIssue {
    nonisolated init(from record: ImportedIssueRecord) {
        let decodedLabels: [String] = if let data = record.labels.data(using: .utf8),
                                         let parsed = try? JSONDecoder().decode([String].self, from: data)
        {
            parsed
        } else {
            []
        }
        self.init(
            id: record.linearId,
            identifier: record.identifier,
            title: record.title,
            status: record.status,
            statusId: record.statusId,
            statusType: record.statusType,
            teamId: record.teamId,
            projectName: record.projectName,
            labels: decodedLabels,
            description: record.description,
            url: record.url,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            isOrphaned: record.isOrphaned
        )
    }
}

extension ImportedIssueRecord {
    nonisolated init(from issue: LinearIssue, importedAt: Date = Date()) {
        let labelsJSON: String = if let data = try? JSONEncoder().encode(issue.labels),
                                    let str = String(data: data, encoding: .utf8)
        {
            str
        } else {
            "[]"
        }
        self.init(
            linearId: issue.id,
            identifier: issue.identifier,
            title: issue.title,
            status: issue.status,
            statusId: issue.statusId,
            statusType: issue.statusType,
            teamId: issue.teamId,
            projectName: issue.projectName,
            labels: labelsJSON,
            description: issue.description,
            url: issue.url,
            createdAt: issue.createdAt,
            updatedAt: issue.updatedAt,
            importedAt: ISO8601DateFormatter.shared.string(from: importedAt),
            sortOrder: 0,
            isOrphaned: issue.isOrphaned
        )
    }
}

// MARK: - Schedule ↔ ScheduleRecord

extension Schedule {
    /// Compose a full schedule from its record plus its already-mapped items.
    /// Items are fetched separately because the `schedules` and
    /// `schedule_items` tables are independent GRDB entities.
    nonisolated init(from record: ScheduleRecord, items: [ScheduleItem]) {
        self.init(
            id: record.scheduleId,
            repoId: record.repoId,
            name: record.name,
            linearProjectId: record.linearProjectId,
            createdAt: record.createdAt,
            runAt: record.runAt,
            items: items
        )
    }
}

extension ScheduleRecord {
    nonisolated init(from schedule: Schedule) {
        self.init(
            scheduleId: schedule.id,
            repoId: schedule.repoId,
            name: schedule.name,
            linearProjectId: schedule.linearProjectId,
            createdAt: schedule.createdAt,
            runAt: schedule.runAt
        )
    }
}

// MARK: - ScheduleItem ↔ ScheduleItemRecord

extension ScheduleItem {
    nonisolated init(from record: ScheduleItemRecord) {
        // `blockedByIssueLinearIds` is stored as a JSON-encoded string to keep
        // the schema flat — decode defensively so a malformed row doesn't
        // crash the sidebar load.
        let decodedBlockers: [String] = if let data = record.blockedByIssueLinearIds.data(using: .utf8),
                                           let decoded = try? JSONDecoder().decode([String].self, from: data)
        {
            decoded
        } else {
            []
        }
        self.init(
            id: record.scheduleItemId,
            scheduleId: record.scheduleId,
            worktreeId: record.worktreeId,
            issueLinearId: record.issueLinearId,
            issueIdentifier: record.issueIdentifier,
            issueTitle: record.issueTitle,
            position: record.position,
            weight: record.weight,
            blockedByIssueLinearIds: decodedBlockers,
            status: ScheduleItemStatus(rawValue: record.status) ?? .planned
        )
    }
}

extension ScheduleItemRecord {
    nonisolated init(from item: ScheduleItem) {
        let blockersJSON: String = if let data = try? JSONEncoder().encode(item.blockedByIssueLinearIds),
                                      let str = String(data: data, encoding: .utf8)
        {
            str
        } else {
            "[]"
        }
        self.init(
            scheduleItemId: item.id,
            scheduleId: item.scheduleId,
            worktreeId: item.worktreeId,
            issueLinearId: item.issueLinearId,
            issueIdentifier: item.issueIdentifier,
            issueTitle: item.issueTitle,
            position: item.position,
            weight: item.weight,
            blockedByIssueLinearIds: blockersJSON,
            status: item.status.rawValue
        )
    }
}
