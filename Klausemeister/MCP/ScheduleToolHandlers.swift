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
    ///
    /// `items[].issueLinearId` and entries in `items[].blockedByIssueLinearIds`
    /// accept either the Linear UUID or the human identifier (e.g. `KLA-220`),
    /// matching `enqueueItem` / `dequeueItem`. Both inputs are normalised to
    /// the canonical UUID before persisting so downstream queries don't need
    /// to know which form the caller used.
    static func saveSchedule(
        input: SaveScheduleInput,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.databaseClient) var databaseClient

        let scheduleId = UUID().uuidString
        let createdAt = ISO8601DateFormatter.shared.string(from: Date())

        // Resolve every issue reference (item ids + blocker ids) to canonical
        // UUIDs up front. A single missing issue aborts the whole save —
        // partial schedules are worse than none, since `runSchedule` can't
        // recover from a bad reference.
        var items: [ScheduleItem] = []
        items.reserveCapacity(input.items.count)
        for item in input.items {
            guard let resolvedIssueId = try await Self.resolveIssueLinearId(
                item.issueLinearId, databaseClient: databaseClient
            ) else {
                return .failure("Issue \(item.issueLinearId) not found in local cache — import it first")
            }

            var resolvedBlockers: [String] = []
            resolvedBlockers.reserveCapacity(item.blockedByIssueLinearIds.count)
            for blocker in item.blockedByIssueLinearIds {
                guard let resolvedBlockerId = try await Self.resolveIssueLinearId(
                    blocker, databaseClient: databaseClient
                ) else {
                    return .failure("Blocker issue \(blocker) not found in local cache — import it first")
                }
                resolvedBlockers.append(resolvedBlockerId)
            }

            items.append(ScheduleItem(
                id: UUID().uuidString,
                scheduleId: scheduleId,
                worktreeId: item.worktreeId,
                issueLinearId: resolvedIssueId,
                issueIdentifier: item.issueIdentifier,
                issueTitle: item.issueTitle,
                position: item.position,
                weight: item.weight,
                blockedByIssueLinearIds: resolvedBlockers,
                status: .planned
            ))
        }
        let schedule = Schedule(
            id: scheduleId,
            repoId: input.repoId,
            name: input.name,
            linearProjectId: input.linearProjectId,
            createdAt: createdAt,
            runAt: nil,
            items: items
        )

        try await worktreeClient.saveSchedule(schedule)
        eventContinuation.yield(.scheduleSaved(scheduleId: scheduleId))
        return try .success(Self.encodeScheduleJSON(["scheduleId": scheduleId]))
    }

    // MARK: - listSchedules

    /// Summary of every schedule for a repo, ordered newest-first. Used by
    /// the sidebar pills (KLA-197) which only need name + progress counters.
    static func listSchedules(repoId: String) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        let schedules = try await worktreeClient.fetchSchedules(repoId)
        let summaries: [ScheduleSummaryPayload] = schedules.map { schedule in
            ScheduleSummaryPayload(
                scheduleId: schedule.id,
                name: schedule.name,
                createdAt: schedule.createdAt,
                runAt: schedule.runAt,
                totalItems: schedule.items.count,
                doneItems: schedule.doneCount
            )
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
        let items: [ScheduleItemPayload] = schedule.items.map { item in
            ScheduleItemPayload(
                scheduleItemId: item.id,
                worktreeId: item.worktreeId,
                issueLinearId: item.issueLinearId,
                issueIdentifier: item.issueIdentifier,
                issueTitle: item.issueTitle,
                position: item.position,
                weight: item.weight,
                blockedByIssueLinearIds: item.blockedByIssueLinearIds,
                status: item.status.rawValue
            )
        }
        let payload = SchedulePayload(
            scheduleId: schedule.id,
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
                    scheduleItemId: item.id,
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
                try await worktreeClient.updateScheduleItemStatus(item.id, queuedStatus)
                eventContinuation.yield(.scheduleItemStatusChanged(
                    scheduleItemId: item.id, status: queuedStatus
                ))
                results.append(RunScheduleItemResult(
                    scheduleItemId: item.id,
                    ok: true,
                    error: nil
                ))
            } catch {
                results.append(RunScheduleItemResult(
                    scheduleItemId: item.id,
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

    /// Dual lookup: try the input as a Linear UUID first, then as a human
    /// identifier (e.g. `KLA-220`). Mirrors the contract of `enqueueItem` /
    /// `dequeueItem` so callers can hand the same value to any of the
    /// queue-mutation tools. Returns `nil` if the issue isn't in the local
    /// cache; callers turn that into a `.failure` ToolResult.
    private static func resolveIssueLinearId(
        _ raw: String,
        databaseClient: DatabaseClient
    ) async throws -> String? {
        if let issue = try await databaseClient.fetchImportedIssue(raw) {
            return issue.id
        }
        if let issue = try await databaseClient.fetchImportedIssueByIdentifier(raw) {
            return issue.id
        }
        return nil
    }

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
