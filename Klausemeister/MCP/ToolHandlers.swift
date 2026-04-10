// Klausemeister/MCP/ToolHandlers.swift
import Dependencies
import Foundation

/// Result returned by every tool handler. The MCP layer (`MCPSocketListener`)
/// converts this to/from the SDK's `CallTool.Result` so that this file —
/// the testable business logic — does not need to import the MCP SDK.
///
/// `text` is opaque to the bridge; tools that return structured data
/// (e.g. `getNextItem`) encode JSON inside it.
struct ToolResult: Equatable {
    let text: String
    let isError: Bool

    static func success(_ text: String) -> ToolResult {
        ToolResult(text: text, isError: false)
    }

    static func failure(_ message: String) -> ToolResult {
        ToolResult(text: message, isError: true)
    }
}

/// Free-function tool handlers wrapping `WorktreeClient` + `LinearAPIClient`
/// + `DatabaseClient`. Each handler is `async throws` and uses `@Dependency`
/// at call time, so tests can stub clients via `withDependencies`.
enum ToolHandlers {
    // MARK: - getNextItem

    /// Claim the next inbox item for a worktree, set its Linear status to
    /// "In Progress", and return its details. Returns a `success` result with
    /// `{"item":null}` if the inbox is empty.
    nonisolated static func getNextItem(worktreeId: String) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.databaseClient) var databaseClient
        @Dependency(\.linearAPIClient) var linearAPIClient

        let items = try await worktreeClient.fetchQueueItems(worktreeId)
        guard let inboxItem = items.first(where: { $0.queuePosition == "inbox" }) else {
            return .success(#"{"item":null}"#)
        }

        guard let issue = try await databaseClient.fetchImportedIssue(inboxItem.issueLinearId) else {
            return .failure("Imported issue \(inboxItem.issueLinearId) not found in local cache")
        }

        // Move to processing first; rollback Linear status update is not feasible,
        // so we order so the local move happens before the (less reliable) network call.
        try await worktreeClient.moveToProcessingByIssueId(issue.linearId, worktreeId)

        // Best-effort Linear status update — log on failure but do not fail the tool,
        // because the queue side has already advanced.
        if let inProgressId = try? await WorkflowStateResolver.resolve(
            teamId: issue.teamId,
            stateName: "In Progress"
        ) {
            try? await linearAPIClient.updateIssueStatus(issue.linearId, inProgressId)
        }

        let payload = ItemPayload(
            queueItemId: inboxItem.id,
            issueLinearId: issue.linearId,
            identifier: issue.identifier,
            title: issue.title,
            statusName: issue.status,
            description: issue.description,
            url: issue.url,
            teamId: issue.teamId
        )
        return try .success(Self.encodeJSON(["item": payload]))
    }

    // MARK: - completeItem

    /// Move an item from processing → outbox and set its Linear state to `nextLinearState`.
    ///
    /// `nextLinearState` is a state name (e.g. `"Todo"`, `"Done"`); it is resolved to
    /// a team-specific UUID before calling `LinearAPIClient.updateIssueStatus`.
    nonisolated static func completeItem(
        issueLinearId: String,
        worktreeId: String,
        nextLinearState: String
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.databaseClient) var databaseClient
        @Dependency(\.linearAPIClient) var linearAPIClient

        guard let issue = try await databaseClient.fetchImportedIssue(issueLinearId) else {
            return .failure("Imported issue \(issueLinearId) not found in local cache")
        }

        guard let stateId = try await WorkflowStateResolver.resolve(
            teamId: issue.teamId,
            stateName: nextLinearState
        ) else {
            return .failure(
                "No workflow state named \"\(nextLinearState)\" exists for team \(issue.teamId)"
            )
        }

        try await worktreeClient.moveToOutboxByIssueId(issueLinearId, worktreeId)
        try await linearAPIClient.updateIssueStatus(issueLinearId, stateId)
        return .success(#"{"ok":true}"#)
    }

    // MARK: - reportProgress

    /// Records that the master is making progress on an item. The actual broadcast
    /// to the UI happens in `MCPSocketListener`, which yields a `MCPServerEvent`
    /// on the bridge stream after this returns. This handler is intentionally
    /// trivial so the listener can call it for validation/logging without needing
    /// to interpret the bytes.
    nonisolated static func reportProgress(
        issueLinearId _: String,
        worktreeId _: String,
        statusText _: String
    ) async throws -> ToolResult {
        .success(#"{"ok":true}"#)
    }

    // MARK: - getStatus

    /// Read-only snapshot of a worktree's queue: counts per position, current
    /// processing item id (if any).
    nonisolated static func getStatus(worktreeId: String) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        let items = try await worktreeClient.fetchQueueItems(worktreeId)
        let inboxCount = items.count(where: { $0.queuePosition == "inbox" })
        let processingItem = items.first { $0.queuePosition == "processing" }
        let outboxCount = items.count(where: { $0.queuePosition == "outbox" })

        let snapshot = StatusSnapshot(
            inboxCount: inboxCount,
            processingIssueLinearId: processingItem?.issueLinearId,
            outboxCount: outboxCount
        )
        return try .success(Self.encodeJSON(snapshot))
    }

    // MARK: - JSON helpers

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static func encodeJSON(_ value: some Encodable) throws -> String {
        let data = try encoder.encode(value)
        guard let json = String(bytes: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

// MARK: - Payloads

extension ToolHandlers {
    struct ItemPayload: Encodable, Equatable {
        let queueItemId: String
        let issueLinearId: String
        let identifier: String
        let title: String
        let statusName: String
        let description: String?
        let url: String
        let teamId: String
    }

    struct StatusSnapshot: Encodable, Equatable {
        let inboxCount: Int
        let processingIssueLinearId: String?
        let outboxCount: Int
    }
}
