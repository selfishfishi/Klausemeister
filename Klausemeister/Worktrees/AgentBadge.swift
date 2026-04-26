// Klausemeister/Worktrees/AgentBadge.swift
import SwiftUI

/// Compact text capsule labelling which agent runs as a worktree's meister.
/// Sits in worktree row headers (sidebar, swimlane) so the user can tell at
/// a glance whether a worktree is wired to Claude Code or Codex.
struct AgentBadge: View {
    let agent: MeisterAgent

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.fill.quaternary, in: Capsule())
            .help("Agent: \(label) — change via right-click on this row")
    }

    private var label: String {
        switch agent {
        case .claude: "CLAUDE"
        case .codex: "CODEX"
        }
    }
}
