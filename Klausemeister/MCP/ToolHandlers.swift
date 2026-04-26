// Klausemeister/MCP/ToolHandlers.swift
// swiftlint:disable file_length
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

// swiftlint:disable type_body_length

/// Free-function tool handlers wrapping `WorktreeClient` + `LinearAPIClient`
/// + `DatabaseClient`. Each handler is `async throws` and uses `@Dependency`
/// at call time, so tests can stub clients via `withDependencies`.
///
/// **Adding a new tool requires three coordinated edits — and a rebuild +
/// relaunch of Klausemeister.app.** A new handler here is invisible to
/// caller sessions until you also (1) wire a `case "<name>":` branch in
/// `MCPSocketListener.dispatchTool` and (2) register a `Tool(...)` entry
/// in `MCPSocketListener.ToolCatalog.tools`. Stale-process symptom: the
/// new tool name is missing from a meister session's `ToolSearch`. The
/// shim is a pure byte bridge — it does not cache the catalog, so
/// rebuilding and relaunching the app is sufficient. See KLA-221.
enum ToolHandlers {
    // MARK: - getNextItem

    /// Claim the next *unblocked* inbox item for a worktree, set its Linear
    /// status to "In Progress", and return its details.
    ///
    /// An inbox item is considered BLOCKED when a `schedule_items` row exists
    /// for it (i.e. it was placed by `/klause-schedule`) AND any of its
    /// `blockedByIssueLinearIds` blockers still has a schedule_item whose
    /// `status != "done"`. Items not present in any schedule (direct
    /// `enqueueItem` path) are always unblocked, preserving the non-schedule
    /// workflow.
    ///
    /// Return shapes:
    /// - Success with `{"item": { ... }}` — claimed.
    /// - Success with `{"item": null}` — inbox empty.
    /// - Success with `{"item": null, "reason": "all-blocked",
    ///   "blockedItems": [{ "issueLinearId": …, "blockedBy": […] }]}` —
    ///   inbox non-empty but every candidate is waiting on a dependency.
    ///   The meister loop uses `blockedBy` identifiers to narrate progress
    ///   ("idle — waiting on KLA-195").
    static func getNextItem(
        worktreeId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        let items = try await worktreeClient.fetchQueueItems(worktreeId)
        // Explicit sort — never rely on DB ordering contract.
        let inbox = items
            .filter { $0.queuePosition == .inbox }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !inbox.isEmpty else {
            return .success(#"{"item":null}"#)
        }

        let selection = try await selectNextUnblocked(
            inbox: inbox,
            worktreeClient: worktreeClient
        )
        switch selection {
        case let .claim(item):
            return try await claimInboxItem(
                item,
                worktreeId: worktreeId,
                eventContinuation: eventContinuation
            )
        case let .allBlocked(hints):
            return try .success(Self.encodeJSON(AllBlockedPayload(blockedItems: hints)))
        }
    }

    /// Resolution of an inbox-scan. Either we found something runnable, or
    /// every candidate is waiting on a blocker.
    enum InboxSelection: Equatable {
        case claim(WorktreeQueueItem)
        case allBlocked([BlockedItemHint])
    }

    /// Scan `inbox` in sortOrder and pick the first item whose schedule
    /// dependencies are all `done`. Pure function over the two DB reads —
    /// separated so it can be unit tested without stubbing the whole claim
    /// path.
    static func selectNextUnblocked(
        inbox: [WorktreeQueueItem],
        worktreeClient: WorktreeClient
    ) async throws -> InboxSelection {
        let candidateIds = inbox.map(\.issueLinearId)
        let candidateScheduleItems = try await worktreeClient
            .fetchScheduleItemsByIssueLinearIds(candidateIds)

        // Fast path: none of the inbox items are in any schedule, so the
        // legacy "first in FIFO" rule applies and we can skip the blocker
        // lookup entirely.
        if candidateScheduleItems.isEmpty {
            return .claim(inbox[0])
        }

        let byCandidate = Dictionary(
            grouping: candidateScheduleItems, by: \.issueLinearId
        )
        let allBlockerIds = Set(
            candidateScheduleItems.flatMap(\.blockedByIssueLinearIds)
        )
        let blockersByIssue: [String: [ScheduleItem]]
        if allBlockerIds.isEmpty {
            blockersByIssue = [:]
        } else {
            let blockerEntries = try await worktreeClient
                .fetchScheduleItemsByIssueLinearIds(Array(allBlockerIds))
            blockersByIssue = Dictionary(grouping: blockerEntries, by: \.issueLinearId)
        }

        var hints: [BlockedItemHint] = []
        for candidate in inbox {
            let candidateEntries = byCandidate[candidate.issueLinearId] ?? []
            if candidateEntries.isEmpty {
                // Item enqueued outside any schedule → treat as unblocked,
                // matching the tradeoff called out in KLA-200.
                return .claim(candidate)
            }
            let blockingIdentifiers = blockingBlockerIdentifiers(
                for: candidateEntries,
                blockersByIssue: blockersByIssue
            )
            if blockingIdentifiers.isEmpty {
                return .claim(candidate)
            }
            hints.append(BlockedItemHint(
                issueLinearId: candidate.issueLinearId,
                blockedBy: blockingIdentifiers
            ))
        }
        return .allBlocked(hints)
    }

    /// Distinct identifiers (e.g. "KLA-195") of blockers that still have a
    /// non-`done` schedule_item. Deduped in encounter order so the narration
    /// reads left-to-right as discovered.
    private static func blockingBlockerIdentifiers(
        for candidateEntries: [ScheduleItem],
        blockersByIssue: [String: [ScheduleItem]]
    ) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for entry in candidateEntries {
            for blockerId in entry.blockedByIssueLinearIds {
                let blockerEntries = blockersByIssue[blockerId] ?? []
                // If we don't know about the blocker at all in any schedule,
                // we can't prove it's done — treat as still blocking. This
                // matches the strictest-safe interpretation.
                let isBlockerDone: Bool = if blockerEntries.isEmpty {
                    false
                } else {
                    blockerEntries.allSatisfy { $0.status == .done }
                }
                guard !isBlockerDone else { continue }
                let identifier = blockerEntries.first?.issueIdentifier ?? blockerId
                if seen.insert(identifier).inserted {
                    result.append(identifier)
                }
            }
        }
        return result
    }

    /// Shared claim + Linear-update path. Called once a candidate has passed
    /// the blocker check.
    private static func claimInboxItem(
        _ inboxItem: WorktreeQueueItem,
        worktreeId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.databaseClient) var databaseClient
        @Dependency(\.linearAPIClient) var linearAPIClient

        guard let issue = try await databaseClient.fetchImportedIssue(inboxItem.issueLinearId) else {
            return .failure("Imported issue \(inboxItem.issueLinearId) not found in local cache")
        }

        // Move to processing first; a Linear-side rollback is not feasible,
        // so the more-reliable local move must happen before the network call.
        try await worktreeClient.moveToProcessingByIssueId(issue.id, worktreeId)
        eventContinuation.yield(.itemMovedToProcessing(
            worktreeId: worktreeId, issueLinearId: issue.id
        ))

        // Best-effort Linear status update — log on failure but do not fail the
        // tool, because the queue side has already advanced.
        if let inProgressId = try? await WorkflowStateResolver.resolve(
            teamId: issue.teamId,
            stateName: "In Progress"
        ) {
            try? await linearAPIClient.updateIssueStatus(issue.id, inProgressId)
        }

        let payload = ItemPayload(
            queueItemId: inboxItem.id,
            issueLinearId: issue.id,
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

        guard let issue = try await databaseClient.fetchImportedIssue(target.issueLinearId) else {
            return .failure("Imported issue \(target.issueLinearId) not found in local cache")
        }

        guard let kanban = issue.meisterState else {
            return .failure("Issue status '\(issue.status)' does not map to a known workflow state")
        }

        let currentState = ProductState(kanban: kanban, queue: target.queuePosition)
        guard let newState = currentState.applying(command) else {
            // Idempotent: already at the result state of this command — treat as no-op success
            if currentState.isResultOf(command) {
                let payload = makePayload(state: currentState, issue: issue)
                return try .success(Self.encodeJSON(["state": payload]))
            }
            let valid = currentState.validCommands.map(\.rawValue).joined(separator: ", ")
            let next = currentState.nextCommand.map { ". Next command: \($0.rawValue)" } ?? ""
            return .failure(
                "Illegal transition: \(commandName) from (\(kanban.rawValue), \(target.queuePosition.rawValue)). Valid commands: \(valid)\(next)"
            )
        }

        try await applyTransitionSideEffects(
            from: currentState,
            to: newState,
            issueLinearId: target.issueLinearId,
            teamId: issue.teamId,
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
        @Dependency(\.databaseClient) var databaseClient

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
                // Sync local cache so subsequent getProductState reads see the new state
                let states = try? await databaseClient.fetchWorkflowStates()
                if let resolved = states?.first(where: { $0.id == stateId }) {
                    try? await databaseClient.updateIssueStatus(
                        issueLinearId, resolved.name, stateId, resolved.type
                    )
                }
            }
        }
    }

    /// Find the target queue item for a command. For `pull`, targets the first
    /// inbox item. For all other commands (or `nil` for read), targets the
    /// processing item with fallback to the first inbox item.
    private static func resolveTargetItem(
        from items: [WorktreeQueueItem],
        for command: WorkflowCommand?
    ) -> WorktreeQueueItem? {
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
        item: WorktreeQueueItem,
        databaseClient: DatabaseClient
    ) async throws -> ToolResult {
        guard let issue = try await databaseClient.fetchImportedIssue(item.issueLinearId) else {
            return .failure("Imported issue \(item.issueLinearId) not found in local cache")
        }
        guard let kanban = issue.meisterState else {
            return .failure("Issue status '\(issue.status)' does not map to a known workflow state")
        }
        let state = ProductState(kanban: kanban, queue: item.queuePosition)
        let payload = makePayload(state: state, issue: issue)
        return try .success(Self.encodeJSON(["state": payload]))
    }

    // MARK: - listWorktrees

    /// Returns all Klausemeister-tracked worktrees with their queue state.
    static func listWorktrees() async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient

        let worktrees = try await worktreeClient.fetchWorktrees()
        var entries: [WorktreeEntry] = []
        for snapshot in worktrees {
            let items = try await worktreeClient.fetchQueueItems(snapshot.id)
            let inboxItems = items
                .filter { $0.queuePosition == .inbox }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map { InboxEntry(issueLinearId: $0.issueLinearId, sortOrder: $0.sortOrder) }
            let processingItem = items.first { $0.queuePosition == .processing }
            let outboxCount = items.count(where: { $0.queuePosition == .outbox })
            entries.append(WorktreeEntry(
                worktreeId: snapshot.id,
                name: snapshot.name,
                repoId: snapshot.repoId,
                gitWorktreePath: snapshot.gitWorktreePath,
                inboxCount: inboxItems.count,
                inboxItems: inboxItems,
                processingIssueLinearId: processingItem?.issueLinearId,
                outboxCount: outboxCount
            ))
        }
        return try .success(Self.encodeJSON(["worktrees": entries]))
    }

    // MARK: - enqueueItem

    /// Add an issue to a worktree's inbox queue. Idempotent — no-op if the
    /// issue is already queued on that worktree. Appends to the end (FIFO).
    ///
    /// `issueLinearId` accepts either the Linear UUID or the human identifier
    /// (e.g. `KLA-136`). Identifier lookups exist because the Linear MCP wrapper
    /// only surfaces identifiers, so external callers (the `/klause-schedule`
    /// skill in particular) cannot easily obtain UUIDs.
    static func enqueueItem(
        issueLinearId: String,
        targetWorktreeId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.databaseClient) var databaseClient

        // Resolve to the canonical UUID — accept either UUID or identifier on input.
        let resolvedIssueId: String
        if let issue = try await databaseClient.fetchImportedIssue(issueLinearId) {
            resolvedIssueId = issue.id
        } else if let issue = try await databaseClient.fetchImportedIssueByIdentifier(issueLinearId) {
            resolvedIssueId = issue.id
        } else {
            return .failure("Issue \(issueLinearId) not found in local cache — import it first")
        }

        // Verify the worktree exists.
        let worktrees = try await worktreeClient.fetchWorktrees()
        guard worktrees.contains(where: { $0.id == targetWorktreeId }) else {
            return .failure("Worktree \(targetWorktreeId) not found")
        }

        // Check if already queued before writing — only yield the UI event
        // when a new row is actually inserted.
        let existingItems = try await worktreeClient.fetchQueueItems(targetWorktreeId)
        let alreadyQueued = existingItems.contains { $0.issueLinearId == resolvedIssueId }

        try await worktreeClient.assignIssueToWorktree(resolvedIssueId, targetWorktreeId)

        if !alreadyQueued {
            eventContinuation.yield(.itemAddedToInbox(
                worktreeId: targetWorktreeId, issueLinearId: resolvedIssueId
            ))
        }
        return .success(#"{"ok":true}"#)
    }

    // MARK: - dequeueItem

    /// Remove an issue from a worktree's inbox without claiming it.
    /// Idempotent — no-op if the issue isn't queued on that worktree.
    /// Refuses if the issue is currently in `processing` (caller should
    /// `completeItem` instead) or `outbox` (out of scope for this tool).
    ///
    /// `issueLinearId` accepts either the Linear UUID or the human identifier
    /// (e.g. `KLA-136`), matching `enqueueItem`'s contract.
    static func dequeueItem(
        issueLinearId: String,
        targetWorktreeId: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        @Dependency(\.worktreeClient) var worktreeClient
        @Dependency(\.databaseClient) var databaseClient

        let resolvedIssueId: String
        if let issue = try await databaseClient.fetchImportedIssue(issueLinearId) {
            resolvedIssueId = issue.id
        } else if let issue = try await databaseClient.fetchImportedIssueByIdentifier(issueLinearId) {
            resolvedIssueId = issue.id
        } else {
            return .failure("Issue \(issueLinearId) not found in local cache")
        }

        let worktrees = try await worktreeClient.fetchWorktrees()
        guard worktrees.contains(where: { $0.id == targetWorktreeId }) else {
            return .failure("Worktree \(targetWorktreeId) not found")
        }

        let existingItems = try await worktreeClient.fetchQueueItems(targetWorktreeId)
        guard let target = existingItems.first(where: { $0.issueLinearId == resolvedIssueId }) else {
            // Idempotent: already absent, nothing to do.
            return .success(#"{"ok":true}"#)
        }

        switch target.queuePosition {
        case .processing:
            return .failure(
                "Cannot dequeue an item that's in processing — complete or skip it instead"
            )
        case .outbox:
            return .failure(
                "Cannot dequeue an item from outbox — dequeueItem operates on inbox only"
            )
        case .inbox:
            break
        }

        try await worktreeClient.removeFromQueueByIssueId(resolvedIssueId, targetWorktreeId)
        eventContinuation.yield(.itemRemovedFromInbox(
            worktreeId: targetWorktreeId, issueLinearId: resolvedIssueId
        ))
        return .success(#"{"ok":true}"#)
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

    struct WorktreeEntry: Encodable, Equatable {
        let worktreeId: String
        let name: String
        let repoId: String?
        let gitWorktreePath: String
        let inboxCount: Int
        let inboxItems: [InboxEntry]
        let processingIssueLinearId: String?
        let outboxCount: Int
    }

    struct InboxEntry: Encodable, Equatable {
        let issueLinearId: String
        let sortOrder: Int
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

    /// One entry in the `blockedItems` array returned by `getNextItem` when
    /// every inbox candidate is waiting on dependencies. `blockedBy` holds
    /// human identifiers (e.g. "KLA-195") — callers present these directly
    /// in progress narration; they can fall back to the raw UUID only when
    /// no schedule_item is yet available for the blocker.
    struct BlockedItemHint: Encodable, Equatable {
        let issueLinearId: String
        let blockedBy: [String]
    }

    /// Response envelope for the all-blocked case. Manually encodes `item`
    /// as JSON `null` rather than omitting the key — callers' JSON parsers
    /// expect the presence of `item` as the "no work claimed" signal.
    struct AllBlockedPayload: Encodable, Equatable {
        let blockedItems: [BlockedItemHint]

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: AllBlockedPayloadKey.self)
            try container.encodeNil(forKey: .item)
            try container.encode("all-blocked", forKey: .reason)
            try container.encode(blockedItems, forKey: .blockedItems)
        }
    }

    /// Extracted from `AllBlockedPayload` so the inner struct doesn't nest
    /// two levels under `ToolHandlers`, which swiftlint bans.
    private enum AllBlockedPayloadKey: String, CodingKey {
        case item, reason, blockedItems
    }
}

// swiftlint:enable type_body_length
