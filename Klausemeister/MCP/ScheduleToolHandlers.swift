// Klausemeister/MCP/ScheduleToolHandlers.swift
import Dependencies
import Foundation

/// MCP tool handlers for the saved-schedules feature (KLA-195). Lives
/// alongside `ToolHandlers` to keep its primary file under the 500-line
/// lint limit; dispatched from the same `MCPSocketListener` switch.
extension ToolHandlers {
    // MARK: - saveSchedule

    /// Persist a fresh schedule + its items in a single transaction.
    /// Returns `{ "scheduleId": ... }` so callers can immediately reference
    /// the new plan without a follow-up `listSchedules`.
    static func saveSchedule(
        input: SaveScheduleInput,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        let scheduleId = UUID().uuidString
        let createdAt = ISO8601DateFormatter.shared.string(from: Date())

        let scheduleRecord = ScheduleRecord(
            scheduleId: scheduleId,
            repoId: input.repoId,
            name: input.name,
            linearProjectId: input.linearProjectId,
            createdAt: createdAt,
            runAt: nil
        )

        let itemRecords: [ScheduleItemRecord] = try input.items.map { item in
            let blockedData = try Self.scheduleEncoder.encode(item.blockedByIssueLinearIds)
            let blockedJSON = String(bytes: blockedData, encoding: .utf8) ?? "[]"
            return ScheduleItemRecord(
                scheduleItemId: UUID().uuidString,
                scheduleId: scheduleId,
                worktreeId: item.worktreeId,
                issueLinearId: item.issueLinearId,
                issueIdentifier: item.issueIdentifier,
                issueTitle: item.issueTitle,
                position: item.position,
                weight: item.weight,
                blockedByIssueLinearIds: blockedJSON,
                status: ScheduleItemStatus.planned.rawValue
            )
        }

        try await worktreeClient.saveSchedule(scheduleRecord, itemRecords)
        eventContinuation.yield(.scheduleSaved(scheduleId: scheduleId))
        return try .success(Self.encodeScheduleJSON(["scheduleId": scheduleId]))
    }

    // MARK: - listSchedules

    /// Summary of every schedule for a repo, ordered newest-first. Used by
    /// the sidebar pills (KLA-197) which only need name + progress counters.
    static func listSchedules(repoId: String) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        let schedules = try await worktreeClient.fetchSchedules(repoId)
        var summaries: [ScheduleSummaryPayload] = []
        summaries.reserveCapacity(schedules.count)
        for schedule in schedules {
            let items = try await worktreeClient.fetchScheduleItems(schedule.scheduleId)
            let doneItems = items.count(where: { $0.status == ScheduleItemStatus.done.rawValue })
            summaries.append(ScheduleSummaryPayload(
                scheduleId: schedule.scheduleId,
                name: schedule.name,
                createdAt: schedule.createdAt,
                runAt: schedule.runAt,
                totalItems: items.count,
                doneItems: doneItems
            ))
        }
        return try .success(Self.encodeScheduleJSON(["schedules": summaries]))
    }

    // MARK: - getSchedule

    /// Full schedule + items payload. Callers (gantt overlay, /klause-schedule
    /// "restore" path) need the complete shape including `blockedByIssueLinearIds`.
    static func getSchedule(scheduleId: String) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        guard let schedule = try await worktreeClient.fetchSchedule(scheduleId) else {
            return .failure("Schedule \(scheduleId) not found")
        }
        let itemRecords = try await worktreeClient.fetchScheduleItems(scheduleId)
        let items: [ScheduleItemPayload] = itemRecords.map { record in
            ScheduleItemPayload(
                scheduleItemId: record.scheduleItemId,
                worktreeId: record.worktreeId,
                issueLinearId: record.issueLinearId,
                issueIdentifier: record.issueIdentifier,
                issueTitle: record.issueTitle,
                position: record.position,
                weight: record.weight,
                blockedByIssueLinearIds: decodeBlockedIds(record.blockedByIssueLinearIds),
                status: record.status
            )
        }
        let payload = SchedulePayload(
            scheduleId: schedule.scheduleId,
            repoId: schedule.repoId,
            name: schedule.name,
            linearProjectId: schedule.linearProjectId,
            createdAt: schedule.createdAt,
            runAt: schedule.runAt,
            items: items
        )
        return try .success(Self.encodeScheduleJSON(["schedule": payload]))
    }

    // MARK: - deleteSchedule

    static func deleteSchedule(
        scheduleId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        try await worktreeClient.deleteSchedule(scheduleId)
        eventContinuation.yield(.scheduleDeleted(scheduleId: scheduleId))
        return .success(#"{"ok":true}"#)
    }

    // MARK: - runSchedule

    /// Enqueue every item in plan order (per-worktree, position ascending),
    /// flip each item's status to `queued`, then stamp `runAt`. Per-item
    /// failures (e.g. worktree deleted between save and run) don't abort
    /// the whole run — they surface in the per-item `results` array.
    static func runSchedule(
        scheduleId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        guard try await worktreeClient.fetchSchedule(scheduleId) != nil else {
            return .failure("Schedule \(scheduleId) not found")
        }
        let items = try await worktreeClient.fetchScheduleItems(scheduleId)
        let worktrees = try await worktreeClient.fetchWorktrees()
        let validWorktreeIds = Set(worktrees.map(\.id))

        var results: [RunScheduleItemResult] = []
        results.reserveCapacity(items.count)
        let queuedStatus = ScheduleItemStatus.queued.rawValue

        for item in items {
            guard validWorktreeIds.contains(item.worktreeId) else {
                results.append(RunScheduleItemResult(
                    scheduleItemId: item.scheduleItemId,
                    ok: false,
                    error: "worktree gone"
                ))
                continue
            }
            do {
                // Uses the same underlying write as `enqueueItem`; `assignIssueToWorktree`
                // is idempotent so a re-run of a partially-queued schedule is safe.
                try await worktreeClient.assignIssueToWorktree(item.issueLinearId, item.worktreeId)
                eventContinuation.yield(.itemAddedToInbox(
                    worktreeId: item.worktreeId, issueLinearId: item.issueLinearId
                ))
                try await worktreeClient.updateScheduleItemStatus(item.scheduleItemId, queuedStatus)
                eventContinuation.yield(.scheduleItemStatusChanged(
                    scheduleItemId: item.scheduleItemId, status: queuedStatus
                ))
                results.append(RunScheduleItemResult(
                    scheduleItemId: item.scheduleItemId,
                    ok: true,
                    error: nil
                ))
            } catch {
                results.append(RunScheduleItemResult(
                    scheduleItemId: item.scheduleItemId,
                    ok: false,
                    error: error.localizedDescription
                ))
            }
        }

        let runAt = ISO8601DateFormatter.shared.string(from: Date())
        try await worktreeClient.markScheduleRun(scheduleId, runAt)
        eventContinuation.yield(.scheduleRun(scheduleId: scheduleId))
        return try .success(Self.encodeScheduleJSON(["results": results]))
    }

    // MARK: - Helpers

    nonisolated private static let scheduleEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    /// File-local equivalent of `ToolHandlers.encodeJSON` (which is `private`
    /// in the adjacent file and not visible here). Keeping a parallel helper
    /// avoids widening the main file's access level just for this extension.
    nonisolated private static func encodeScheduleJSON(_ value: some Encodable) throws -> String {
        let data = try scheduleEncoder.encode(value)
        guard let json = String(bytes: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// Decode the JSON-string `blockedByIssueLinearIds` column. Failed
    /// decode → empty array; we'd rather surface an empty block list than
    /// blow up a read with one malformed row.
    nonisolated private static let blockedDecoder = JSONDecoder()

    nonisolated private static func decodeBlockedIds(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let decoded = try? blockedDecoder.decode([String].self, from: data)
        else { return [] }
        return decoded
    }
}

// MARK: - Input / payload types

extension ToolHandlers {
    struct SaveScheduleInput: Equatable {
        let repoId: String
        let name: String
        let linearProjectId: String?
        let items: [SaveScheduleItemInput]

        // swiftlint:disable:next nesting
        struct SaveScheduleItemInput: Equatable {
            let worktreeId: String
            let issueLinearId: String
            let issueIdentifier: String
            let issueTitle: String
            let position: Int
            let weight: Int
            let blockedByIssueLinearIds: [String]
        }
    }

    struct ScheduleSummaryPayload: Encodable, Equatable {
        let scheduleId: String
        let name: String
        let createdAt: String
        let runAt: String?
        let totalItems: Int
        let doneItems: Int
    }

    struct SchedulePayload: Encodable, Equatable {
        let scheduleId: String
        let repoId: String
        let name: String
        let linearProjectId: String?
        let createdAt: String
        let runAt: String?
        let items: [ScheduleItemPayload]
    }

    struct ScheduleItemPayload: Encodable, Equatable {
        let scheduleItemId: String
        let worktreeId: String
        let issueLinearId: String
        let issueIdentifier: String
        let issueTitle: String
        let position: Int
        let weight: Int
        let blockedByIssueLinearIds: [String]
        let status: String
    }

    struct RunScheduleItemResult: Encodable, Equatable {
        let scheduleItemId: String
        // `ok` is the JSON contract the `/klause-schedule` skill expects;
        // keeping the Swift property name aligned with the wire format.
        // swiftlint:disable:next identifier_name
        let ok: Bool
        let error: String?
    }
}

// Decodable conformances declared in nonisolated extensions so their
// synthesized `init(from:)` is callable from non-MainActor contexts
// (e.g. the MCP dispatch path, which inherits caller isolation).
nonisolated extension ToolHandlers.SaveScheduleInput: Decodable {}
nonisolated extension ToolHandlers.SaveScheduleInput.SaveScheduleItemInput: Decodable {}
