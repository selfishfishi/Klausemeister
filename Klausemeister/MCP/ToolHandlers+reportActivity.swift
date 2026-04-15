// Klausemeister/MCP/ToolHandlers+reportActivity.swift
import Foundation

extension ToolHandlers {
    /// Session-scoped narration ("where I am / what I'm doing right now").
    /// Unlike `reportProgress`, no `issueLinearId` — the meister may narrate
    /// while idle or between tickets. Yields on the same event stream.
    static func reportActivity(
        worktreeId: String,
        statusText: String,
        eventContinuation: AsyncStream<MCPServerEvent>.Continuation
    ) async throws -> ToolResult {
        eventContinuation.yield(.activityReported(
            worktreeId: worktreeId,
            text: statusText
        ))
        return .success(#"{"ok":true}"#)
    }
}
