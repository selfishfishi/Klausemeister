import ComposableArchitecture
import Foundation
import Testing
@testable import Klausemeister

// MARK: - Fixtures

private let teamId = "team-1"
private let worktreeId = "wt-1"

private let issue = LinearIssue(
    id: "issue-1",
    identifier: "KLA-70",
    title: "MCP server",
    status: "Backlog",
    statusId: "state-backlog",
    statusType: "backlog",
    teamId: teamId,
    projectName: "Klause",
    labels: [],
    description: "Build the in-process MCP server",
    url: "https://linear.app/x/issue/KLA-70",
    updatedAt: "2026-04-06"
)

private let inProgressState = LinearWorkflowState(
    id: "state-in-progress",
    name: "In Progress",
    type: "started",
    position: 2,
    teamId: teamId
)

private let doneState = LinearWorkflowState(
    id: "state-done",
    name: "Done",
    type: "completed",
    position: 5,
    teamId: teamId
)

private let inboxItem = WorktreeQueueItem(
    id: "qi-1",
    worktreeId: worktreeId,
    issueLinearId: issue.id,
    queuePosition: .inbox,
    sortOrder: 0
)

private let processingItem = WorktreeQueueItem(
    id: "qi-2",
    worktreeId: worktreeId,
    issueLinearId: "issue-other",
    queuePosition: .processing,
    sortOrder: 0
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
        $0.stateMappingClient.fetchForTeam = { _ in [] }
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
    let (stream, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)

    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { wid in
            #expect(wid == worktreeId)
            return [inboxItem]
        }
        $0.worktreeClient.moveToProcessingByIssueId = { issueId, wid in
            movedToProcessing = (issueId, wid)
        }
        $0.databaseClient.fetchImportedIssue = { id in
            #expect(id == issue.id)
            return issue
        }
        $0.databaseClient.fetchWorkflowStates = { [inProgressState, doneState] }
        $0.stateMappingClient.fetchForTeam = { _ in [] }
        $0.linearAPIClient.updateIssueStatus = { issueId, stateId in
            linearUpdate = (issueId, stateId)
        }
    } operation: {
        try await ToolHandlers.getNextItem(
            worktreeId: worktreeId,
            eventContinuation: continuation
        )
    }
    continuation.finish()

    #expect(!result.isError)
    #expect(movedToProcessing?.issueId == issue.id)
    #expect(movedToProcessing?.worktreeId == worktreeId)
    #expect(linearUpdate?.issueId == issue.id)
    #expect(linearUpdate?.statusId == inProgressState.id)
    #expect(result.text.contains("\"identifier\":\"KLA-70\""))

    var events: [MCPServerEvent] = []
    for await event in stream {
        events.append(event)
    }
    #expect(events.contains(.itemMovedToProcessing(
        worktreeId: worktreeId, issueLinearId: issue.id
    )))
}

@Test func `getNextItem returns null item when inbox is empty`() async throws {
    let (_, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)
    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { _ in [processingItem] }
    } operation: {
        try await ToolHandlers.getNextItem(
            worktreeId: worktreeId,
            eventContinuation: continuation
        )
    }

    #expect(!result.isError)
    #expect(result.text == #"{"item":null}"#)
}

@Test func `getNextItem reports failure when imported issue is missing`() async throws {
    let (_, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)
    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { _ in [inboxItem] }
        $0.databaseClient.fetchImportedIssue = { _ in nil }
    } operation: {
        try await ToolHandlers.getNextItem(
            worktreeId: worktreeId,
            eventContinuation: continuation
        )
    }

    #expect(result.isError)
    #expect(result.text.contains("not found in local cache"))
}

// MARK: - completeItem

@Test func `completeItem moves to outbox and updates Linear by name`() async throws {
    var movedToOutbox: (issueId: String, worktreeId: String)?
    var linearUpdate: (issueId: String, statusId: String)?
    let (stream, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)

    let result = try await withDependencies {
        $0.databaseClient.fetchImportedIssue = { _ in issue }
        $0.databaseClient.fetchWorkflowStates = { [inProgressState, doneState] }
        $0.worktreeClient.moveToOutboxByIssueId = { issueId, wid in
            movedToOutbox = (issueId, wid)
        }
        $0.linearAPIClient.updateIssueStatus = { issueId, stateId in
            linearUpdate = (issueId, stateId)
        }
    } operation: {
        try await ToolHandlers.completeItem(
            issueLinearId: issue.id,
            worktreeId: worktreeId,
            nextLinearState: "Done",
            eventContinuation: continuation
        )
    }
    continuation.finish()

    #expect(!result.isError)
    #expect(movedToOutbox?.issueId == issue.id)
    #expect(movedToOutbox?.worktreeId == worktreeId)
    #expect(linearUpdate?.statusId == doneState.id)

    var events: [MCPServerEvent] = []
    for await event in stream {
        events.append(event)
    }
    #expect(events.contains(.itemMovedToOutbox(
        worktreeId: worktreeId, issueLinearId: issue.id
    )))
}

@Test func `completeItem fails when state name does not exist`() async throws {
    let (_, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)
    let result = try await withDependencies {
        $0.databaseClient.fetchImportedIssue = { _ in issue }
        $0.databaseClient.fetchWorkflowStates = { [inProgressState] }
    } operation: {
        try await ToolHandlers.completeItem(
            issueLinearId: issue.id,
            worktreeId: worktreeId,
            nextLinearState: "Nonexistent",
            eventContinuation: continuation
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

// MARK: - reportActivity

@Test func `reportActivity yields event and succeeds`() async throws {
    let (stream, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)

    let result = try await ToolHandlers.reportActivity(
        worktreeId: worktreeId,
        statusText: "reading WorktreeFeature.swift",
        eventContinuation: continuation
    )
    continuation.finish()

    #expect(!result.isError)

    var events: [MCPServerEvent] = []
    for await event in stream {
        events.append(event)
    }
    #expect(events == [.activityReported(worktreeId: worktreeId, text: "reading WorktreeFeature.swift")])
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
