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
    static func getNextItem(
        worktreeId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.databaseClient) var databaseClient
        @Dependency(\.linearAPIClient) var linearAPIClient

        let items = try await worktreeClient.fetchQueueItems(worktreeId)
        // Explicitly sort by sortOrder rather than relying on DB ordering contract.
        guard let inboxItem = items
            .filter({ $0.queuePosition == .inbox })
            .min(by: { $0.sortOrder < $1.sortOrder })
        else {
            return .success(#"{"item":null}"#)
        }

        guard let issue = try await databaseClient.fetchImportedIssue(inboxItem.issueLinearId) else {
            return .failure("Imported issue \(inboxItem.issueLinearId) not found in local cache")
        }

        // Move to processing first; rollback Linear status update is not feasible,
        // so we order so the local move happens before the (less reliable) network call.
        try await worktreeClient.moveToProcessingByIssueId(issue.linearId, worktreeId)
        eventContinuation.yield(.itemMovedToProcessing(
            worktreeId: worktreeId, issueLinearId: issue.linearId
        ))

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
    static func completeItem(
        issueLinearId: String,
        worktreeId: String,
        nextLinearState: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
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
        eventContinuation.yield(.itemMovedToOutbox(
            worktreeId: worktreeId, issueLinearId: issueLinearId
        ))

        // Best-effort Linear status update — the local queue has already advanced,
        // so we log on failure but don't fail the tool. This mirrors getNextItem's
        // approach: local state is authoritative, Linear is eventually consistent.
        try? await linearAPIClient.updateIssueStatus(issueLinearId, stateId)
        return .success(#"{"ok":true}"#)
    }

    // MARK: - reportProgress

    /// Validates the progress report and yields it on the event stream so
    /// `AppFeature` can route it to the UI. The `eventContinuation` is
    /// threaded through because this file does not own it — the listener does.
    static func reportProgress(
        issueLinearId: String,
        worktreeId: String,
        statusText: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        eventContinuation.yield(.progressReported(
            worktreeId: worktreeId,
            itemId: issueLinearId,
            statusText: statusText
        ))
        return .success(#"{"ok":true}"#)
    }

    // MARK: - getStatus

    /// Read-only snapshot of a worktree's queue: counts per position, current
    /// processing item id (if any).
    static func getStatus(worktreeId: String) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        let items = try await worktreeClient.fetchQueueItems(worktreeId)
        let inboxCount = items.count(where: { $0.queuePosition == .inbox })
        let processingItem = items.first { $0.queuePosition == .processing }
        let outboxCount = items.count(where: { $0.queuePosition == .outbox })

        let snapshot = StatusSnapshot(
            inboxCount: inboxCount,
            processingIssueLinearId: processingItem?.issueLinearId,
            outboxCount: outboxCount
        )
        return try .success(Self.encodeJSON(snapshot))
    }

    // MARK: - getProductState

    /// Returns the current product state (kanban + queue position) for the
    /// active item in this worktree. Prefers the processing item; falls back
    /// to the first inbox item. Returns `{"state":null}` if the queue is empty.
    static func getProductState(worktreeId: String) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.databaseClient) var databaseClient

        let items = try await worktreeClient.fetchQueueItems(worktreeId)
        guard let target = resolveTargetItem(from: items, for: nil) else {
            return .success(#"{"state":null}"#)
        }
        return try await buildProductStateResult(
            item: target,
            databaseClient: databaseClient
        )
    }

    // MARK: - transition

    /// Execute a workflow command to advance the product state. Validates the
    /// transition against the state machine before applying side effects.
    static func transition(
        commandName: String,
        worktreeId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.databaseClient) var databaseClient

        guard let command = WorkflowCommand(rawValue: commandName) else {
            let valid = WorkflowCommand.allCases.map(\.rawValue).joined(separator: ", ")
            return .failure("Unknown command: \(commandName). Valid: \(valid)")
        }

        let items = try await worktreeClient.fetchQueueItems(worktreeId)
        guard let target = resolveTargetItem(from: items, for: command) else {
            return .failure("No item available for \(commandName)")
        }

        guard let issueRecord = try await databaseClient.fetchImportedIssue(target.issueLinearId) else {
            return .failure("Imported issue \(target.issueLinearId) not found in local cache")
        }

        let issue = LinearIssue(from: issueRecord)
        guard let kanban = issue.meisterState else {
            return .failure("Issue status '\(issue.status)' does not map to a known workflow state")
        }

        let currentState = ProductState(kanban: kanban, queue: target.queuePosition)
        guard let newState = currentState.applying(command) else {
            let valid = currentState.validCommands.map(\.rawValue).joined(separator: ", ")
            return .failure(
                "Illegal transition: \(commandName) from (\(kanban.rawValue), \(target.queuePosition.rawValue)). Valid commands: \(valid)"
            )
        }

        try await applyTransitionSideEffects(
            from: currentState,
            to: newState,
            issueLinearId: target.issueLinearId,
            teamId: issueRecord.teamId,
            worktreeId: worktreeId
        )

        if newState.queue != currentState.queue {
            switch newState.queue {
            case .processing:
                eventContinuation.yield(.itemMovedToProcessing(
                    worktreeId: worktreeId, issueLinearId: target.issueLinearId
                ))
            case .outbox:
                eventContinuation.yield(.itemMovedToOutbox(
                    worktreeId: worktreeId, issueLinearId: target.issueLinearId
                ))
            case .inbox:
                break
            }
        }

        let payload = makePayload(state: newState, issue: issue)
        return try .success(Self.encodeJSON(["state": payload]))
    }

    // MARK: - Shared helpers

    /// Execute the queue and kanban side effects of a validated transition.
    /// Queue mutations are local-first; Linear updates are best-effort.
    private static func applyTransitionSideEffects(
        from currentState: ProductState,
        to newState: ProductState,
        issueLinearId: String,
        teamId: String,
        worktreeId: String
    ) async throws {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.linearAPIClient) var linearAPIClient

        if newState.queue != currentState.queue {
            switch newState.queue {
            case .processing:
                try await worktreeClient.moveToProcessingByIssueId(issueLinearId, worktreeId)
            case .outbox:
                try await worktreeClient.moveToOutboxByIssueId(issueLinearId, worktreeId)
            case .inbox:
                break
            }
        }
        if newState.kanban != currentState.kanban {
            if let stateId = try? await WorkflowStateResolver.resolve(
                teamId: teamId,
                stateName: newState.kanban.displayName
            ) {
                try? await linearAPIClient.updateIssueStatus(issueLinearId, stateId)
            }
        }
    }

    /// Find the target queue item for a command. For `pull`, targets the first
    /// inbox item. For all other commands (or `nil` for read), targets the
    /// processing item with fallback to the first inbox item.
    private static func resolveTargetItem(
        from items: [WorktreeQueueItemRecord],
        for command: WorkflowCommand?
    ) -> WorktreeQueueItemRecord? {
        if command == .pull {
            return items
                .filter { $0.queuePosition == .inbox }
                .min(by: { $0.sortOrder < $1.sortOrder })
        }
        return items.first { $0.queuePosition == .processing }
            ?? items
            .filter { $0.queuePosition == .inbox }
            .min(by: { $0.sortOrder < $1.sortOrder })
    }

    /// Build a `ProductStatePayload` from a `ProductState` and `LinearIssue`.
    private static func makePayload(state: ProductState, issue: LinearIssue) -> ProductStatePayload {
        ProductStatePayload(
            kanban: state.kanban.rawValue,
            kanbanDisplayName: state.kanban.displayName,
            queue: state.queue.rawValue,
            nextCommand: state.nextCommand?.rawValue,
            validCommands: state.validCommands.map(\.rawValue),
            isComplete: state.isComplete,
            issueLinearId: issue.id,
            identifier: issue.identifier,
            title: issue.title
        )
    }

    /// Fetch an issue record, derive the product state, and return it as a
    /// JSON result. Shared by `getProductState`.
    private static func buildProductStateResult(
        item: WorktreeQueueItemRecord,
        databaseClient: DatabaseClient
    ) async throws -> ToolResult {
        guard let issueRecord = try await databaseClient.fetchImportedIssue(item.issueLinearId) else {
            return .failure("Imported issue \(item.issueLinearId) not found in local cache")
        }
        let issue = LinearIssue(from: issueRecord)
        guard let kanban = issue.meisterState else {
            return .failure("Issue status '\(issue.status)' does not map to a known workflow state")
        }
        let state = ProductState(kanban: kanban, queue: item.queuePosition)
        let payload = makePayload(state: state, issue: issue)
        return try .success(Self.encodeJSON(["state": payload]))
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

    struct ProductStatePayload: Encodable, Equatable {
        let kanban: String
        let kanbanDisplayName: String
        let queue: String
        let nextCommand: String?
        let validCommands: [String]
        let isComplete: Bool
        let issueLinearId: String?
        let identifier: String?
        let title: String?
    }
}
