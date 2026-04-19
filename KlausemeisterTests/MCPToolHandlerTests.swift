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
    createdAt: "2026-04-01",
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
        $0.worktreeClient.fetchScheduleItemsByIssueLinearIds = { _ in [] }
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
        $0.worktreeClient.fetchScheduleItemsByIssueLinearIds = { _ in [] }
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

// MARK: - getNextItem · dependency-aware (KLA-200)

private func scheduleItem(
    id: String = UUID().uuidString,
    scheduleId: String = "sched-1",
    worktreeId: String = worktreeId,
    issueLinearId: String,
    issueIdentifier: String,
    blockedByIssueLinearIds: [String] = [],
    status: ScheduleItemStatus
) -> ScheduleItemRecord {
    let blockers = (try? JSONEncoder().encode(blockedByIssueLinearIds))
        .flatMap { String(bytes: $0, encoding: .utf8) } ?? "[]"
    return ScheduleItemRecord(
        scheduleItemId: id,
        scheduleId: scheduleId,
        worktreeId: worktreeId,
        issueLinearId: issueLinearId,
        issueIdentifier: issueIdentifier,
        issueTitle: "fixture",
        position: 0,
        weight: 1,
        blockedByIssueLinearIds: blockers,
        status: status.rawValue
    )
}

@Test func `getNextItem skips blocked candidate and claims the unblocked sibling`() async throws {
    let blockedInbox = WorktreeQueueItem(
        id: "qi-A", worktreeId: worktreeId,
        issueLinearId: "issue-A", queuePosition: .inbox, sortOrder: 0
    )
    let unblockedInbox = WorktreeQueueItem(
        id: "qi-B", worktreeId: worktreeId,
        issueLinearId: "issue-B", queuePosition: .inbox, sortOrder: 1
    )
    let issueB = LinearIssue(
        id: "issue-B", identifier: "KLA-B",
        title: "second",
        status: "Todo", statusId: "state-todo", statusType: "unstarted",
        teamId: teamId, projectName: "Klause", labels: [],
        description: nil, url: "https://linear.app/x/KLA-B",
        createdAt: "2026-04-18", updatedAt: "2026-04-18"
    )
    var claimed: String?
    let (_, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)

    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { _ in [blockedInbox, unblockedInbox] }
        $0.worktreeClient.fetchScheduleItemsByIssueLinearIds = { ids in
            // First call: candidates. Only issue-A is in a schedule.
            if Set(ids) == Set(["issue-A", "issue-B"]) {
                return [scheduleItem(
                    issueLinearId: "issue-A",
                    issueIdentifier: "KLA-A",
                    blockedByIssueLinearIds: ["issue-C"],
                    status: .queued
                )]
            }
            // Second call: blocker lookup. issue-C is still queued → blocking.
            if Set(ids) == Set(["issue-C"]) {
                return [scheduleItem(
                    issueLinearId: "issue-C",
                    issueIdentifier: "KLA-C",
                    status: .queued
                )]
            }
            return []
        }
        $0.worktreeClient.moveToProcessingByIssueId = { issueId, _ in
            claimed = issueId
        }
        $0.databaseClient.fetchImportedIssue = { id in
            id == issueB.id ? issueB : nil
        }
        $0.databaseClient.fetchWorkflowStates = { [] }
        $0.stateMappingClient.fetchForTeam = { _ in [] }
        $0.linearAPIClient.updateIssueStatus = { _, _ in }
    } operation: {
        try await ToolHandlers.getNextItem(
            worktreeId: worktreeId,
            eventContinuation: continuation
        )
    }

    #expect(!result.isError)
    #expect(claimed == "issue-B")
    #expect(result.text.contains("\"identifier\":\"KLA-B\""))
}

@Test func `getNextItem returns all-blocked when every candidate waits on a dep`() async throws {
    let pendingInbox = WorktreeQueueItem(
        id: "qi-A", worktreeId: worktreeId,
        issueLinearId: "issue-A", queuePosition: .inbox, sortOrder: 0
    )
    let (_, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)

    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { _ in [pendingInbox] }
        $0.worktreeClient.fetchScheduleItemsByIssueLinearIds = { ids in
            if ids == ["issue-A"] {
                return [scheduleItem(
                    issueLinearId: "issue-A",
                    issueIdentifier: "KLA-A",
                    blockedByIssueLinearIds: ["issue-C"],
                    status: .queued
                )]
            }
            if Set(ids) == Set(["issue-C"]) {
                return [scheduleItem(
                    issueLinearId: "issue-C",
                    issueIdentifier: "KLA-C",
                    status: .queued
                )]
            }
            return []
        }
    } operation: {
        try await ToolHandlers.getNextItem(
            worktreeId: worktreeId,
            eventContinuation: continuation
        )
    }

    #expect(!result.isError)
    #expect(result.text.contains("\"reason\":\"all-blocked\""))
    #expect(result.text.contains("\"blockedBy\":[\"KLA-C\"]"))
    #expect(result.text.contains("\"item\":null"))
}

@Test func `getNextItem claims candidate whose blockers are all done`() async throws {
    let inbox = WorktreeQueueItem(
        id: "qi-A", worktreeId: worktreeId,
        issueLinearId: issue.id, queuePosition: .inbox, sortOrder: 0
    )
    var claimed: String?
    let (_, continuation) = AsyncStream.makeStream(of: MCPServerEvent.self)

    let result = try await withDependencies {
        $0.worktreeClient.fetchQueueItems = { _ in [inbox] }
        $0.worktreeClient.fetchScheduleItemsByIssueLinearIds = { ids in
            if ids == [issue.id] {
                return [scheduleItem(
                    issueLinearId: issue.id,
                    issueIdentifier: issue.identifier,
                    blockedByIssueLinearIds: ["issue-C"],
                    status: .queued
                )]
            }
            if Set(ids) == Set(["issue-C"]) {
                return [scheduleItem(
                    issueLinearId: "issue-C",
                    issueIdentifier: "KLA-C",
                    status: .done
                )]
            }
            return []
        }
        $0.worktreeClient.moveToProcessingByIssueId = { issueId, _ in
            claimed = issueId
        }
        $0.databaseClient.fetchImportedIssue = { _ in issue }
        $0.databaseClient.fetchWorkflowStates = { [] }
        $0.stateMappingClient.fetchForTeam = { _ in [] }
        $0.linearAPIClient.updateIssueStatus = { _, _ in }
    } operation: {
        try await ToolHandlers.getNextItem(
            worktreeId: worktreeId,
            eventContinuation: continuation
        )
    }

    #expect(!result.isError)
    #expect(claimed == issue.id)
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
