// Klausemeister/Worktrees/ClaudeStatusLineView.swift
import SwiftUI

/// Compact one-line indicator showing the meister's Claude Code session state
/// next to `WorktreeStatusDot` in sidebar rows and swimlane headers. Driven
/// purely by a `ClaudeSessionState` value; the feature layer owns updates.
/// Renders nothing (`EmptyView`) for `.offline`. The connectivity dot lives
/// on the row as a whole, not inline here.
struct ClaudeStatusLineView: View {
    let state: ClaudeSessionState
    /// Free-form text from the meister's most recent `reportProgress` call.
    /// Wins over the generic label when the session is `.working`. Ignored
    /// for other states (the reducer clears it on non-working transitions).
    var text: String?

    var body: some View {
        if case .offline = state {
            EmptyView()
        } else {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var label: String {
        switch state {
        case let .working(tool):
            // Prefer rich `reportProgress` text when present; fall back to the
            // tool name from the hook; finally fall back to the generic label.
            if let text, !text.isEmpty {
                return text
            }
            return tool ?? "Working…"
        case .idle:
            return "Idle"
        case .blocked:
            return "Needs approval"
        case .error:
            return "Error"
        case .offline:
            return ""
        }
    }
}
