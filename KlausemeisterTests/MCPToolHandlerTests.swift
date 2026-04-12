import ComposableArchitecture
import Foundation
import Testing
@testable import Klausemeister

// MARK: - Fixtures

// NOTE: These fixtures use *Record types directly because DatabaseClient and
// WorktreeClient return records (not domain types) — a pre-existing layer
// violation tracked as KLA-60. Once KLA-60 is resolved, these fixtures
// should be expressed as domain types instead.

private let teamId = "team-1"
private let worktreeId = "wt-1"

private let issueRecord = ImportedIssueRecord(
    linearId: "issue-1",
    identifier: "KLA-70",
    title: "MCP server",
    status: "Backlog",
    statusId: "state-backlog",
    statusType: "backlog",
    teamId: teamId,
    projectName: "Klause",
    labels: "[]",
    description: "Build the in-process MCP server",
    url: "https://linear.app/x/issue/KLA-70",
    updatedAt: "2026-04-06",
    importedAt: "2026-04-06",
    sortOrder: 0,
    isOrphaned: false
)

private let inProgressState = LinearWorkflowStateRecord(
    id: "state-in-progress",
    teamId: teamId,
    name: "In Progress",
    type: "started",
    position: 2,
    fetchedAt: "2026-04-06"
)

private let doneState = LinearWorkflowStateRecord(
    id: "state-done",
    teamId: teamId,
    name: "Done",
    type: "completed",
    position: 5,
    fetchedAt: "2026-04-06"
)

private let inboxItem = WorktreeQueueItemRecord(
    id: "qi-1",
    worktreeId: worktreeId,
    issueLinearId: issueRecord.linearId,
    queuePosition: .inbox,
    sortOrder: 0,
    assignedAt: "2026-04-06",
    completedAt: nil
)

private let processingItem = WorktreeQueueItemRecord(
    id: "qi-2",
    worktreeId: worktreeId,
    issueLinearId: "issue-other",
    queuePosition: .processing,
    sortOrder: 0,
    assignedAt: "2026-04-06",
    completedAt: nil
)

// MARK: - WorkflowStateResolver

@Test func `resolver returns matching state UUID for team`() async throws {
    let stateId = try await withDependencies {
        $0.databaseClient.fetchWorkflowStates = { [inProgressState, doneState] }
    } operation: {
        try await WorkflowStateResolver.resolve(teamId: teamId, stateName: "Done")
    }

    #expect(stateId == "state-done")
}

@Test func `resolver is case insensitive`() async throws {
    let stateId = try await withDependencies {
        $0.databaseClient.fetchWorkflowStates = { [inProgressState, doneState] }
    } operation: {
        try await WorkflowStateResolver.resolve(teamId: teamId, stateName: "in progress")
    }

    #expect(stateId == "state-in-progress")
}

@Test func `resolver returns nil when team has no matching state`() async throws {
    let stateId = try await withDependencies {
        $0.databaseClient.fetchWorkflowStates = { [doneState] }
    } operation: {
        try await WorkflowStateResolver.resolve(teamId: "other-team", stateName: "Done")
    }

    #expect(stateId == nil)
}

// MARK: - getNextItem

@Test func `getNextItem claims inbox item and updates Linear status`() async throws {
    var movedToProcessing: (issueId: String, worktreeId: String)?
    var linearUpdate: (issueId: String, statusId: String)?

    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { wid in
            #expect(wid == worktreeId)
            return [inboxItem]
        }
        $0.worktreeClient.moveToProcessingByIssueId = { issueId, wid in
            movedToProcessing = (issueId, wid)
        }
        $0.databaseClient.fetchImportedIssue = { id in
            #expect(id == issueRecord.linearId)
            return issueRecord
        }
        $0.databaseClient.fetchWorkflowStates = { [inProgressState, doneState] }
        $0.linearAPIClient.updateIssueStatus = { issueId, stateId in
            linearUpdate = (issueId, stateId)
        }
    } operation: {
        try await ToolHandlers.getNextItem(worktreeId: worktreeId)
    }

    #expect(!result.isError)
    #expect(movedToProcessing?.issueId == issueRecord.linearId)
    #expect(movedToProcessing?.worktreeId == worktreeId)
    #expect(linearUpdate?.issueId == issueRecord.linearId)
    #expect(linearUpdate?.statusId == inProgressState.id)
    #expect(result.text.contains("\"identifier\":\"KLA-70\""))
}

@Test func `getNextItem returns null item when inbox is empty`() async throws {
    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { _ in [processingItem] }
    } operation: {
        try await ToolHandlers.getNextItem(worktreeId: worktreeId)
    }

    #expect(!result.isError)
    #expect(result.text == #"{"item":null}"#)
}

@Test func `getNextItem reports failure when imported issue is missing`() async throws {
    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { _ in [inboxItem] }
        $0.databaseClient.fetchImportedIssue = { _ in nil }
    } operation: {
        try await ToolHandlers.getNextItem(worktreeId: worktreeId)
    }

    #expect(result.isError)
    #expect(result.text.contains("not found in local cache"))
}

// MARK: - completeItem

@Test func `completeItem moves to outbox and updates Linear by name`() async throws {
    var movedToOutbox: (issueId: String, worktreeId: String)?
    var linearUpdate: (issueId: String, statusId: String)?

    let result = try await withDependencies {
        $0.databaseClient.fetchImportedIssue = { _ in issueRecord }
        $0.databaseClient.fetchWorkflowStates = { [inProgressState, doneState] }
        $0.worktreeClient.moveToOutboxByIssueId = { issueId, wid in
            movedToOutbox = (issueId, wid)
        }
        $0.linearAPIClient.updateIssueStatus = { issueId, stateId in
            linearUpdate = (issueId, stateId)
        }
    } operation: {
        try await ToolHandlers.completeItem(
            issueLinearId: issueRecord.linearId,
            worktreeId: worktreeId,
            nextLinearState: "Done"
        )
    }

    #expect(!result.isError)
    #expect(movedToOutbox?.issueId == issueRecord.linearId)
    #expect(movedToOutbox?.worktreeId == worktreeId)
    #expect(linearUpdate?.statusId == doneState.id)
}

@Test func `completeItem fails when state name does not exist`() async throws {
    let result = try await withDependencies {
        $0.databaseClient.fetchImportedIssue = { _ in issueRecord }
        $0.databaseClient.fetchWorkflowStates = { [inProgressState] }
    } operation: {
        try await ToolHandlers.completeItem(
            issueLinearId: issueRecord.linearId,
            worktreeId: worktreeId,
            nextLinearState: "Nonexistent"
        )
    }

    #expect(result.isError)
    #expect(result.text.contains("Nonexistent"))
}

// MARK: - reportProgress

@Test func `reportProgress yields event and succeeds`() async throws {
    let (stream, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)

    let result = try await ToolHandlers.reportProgress(
        issueLinearId: "issue-1",
        worktreeId: worktreeId,
        statusText: "halfway through",
        eventContinuation: continuation
    )
    continuation.finish()

    #expect(!result.isError)

    var events: [MCPServerEvent] = []
    for await event in stream {
        events.append(event)
    }
    #expect(events == [.progressReported(worktreeId: worktreeId, itemId: "issue-1", statusText: "halfway through")])
}

// MARK: - getStatus

@Test func `getStatus returns counts and processing item`() async throws {
    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { _ in [inboxItem, processingItem] }
    } operation: {
        try await ToolHandlers.getStatus(worktreeId: worktreeId)
    }

    #expect(!result.isError)
    #expect(result.text.contains("\"inboxCount\":1"))
    #expect(result.text.contains("\"outboxCount\":0"))
    #expect(result.text.contains("\"processingIssueLinearId\":\"issue-other\""))
}
