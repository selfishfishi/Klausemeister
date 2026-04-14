// Klausemeister/Worktrees/GitStatsLineView.swift
import SwiftUI

/// Compact single-line view showing git stats: uncommitted files, +/-
/// additions/deletions, PR status, commits ahead of main. Reused by both
/// the swimlane header and the sidebar worktree row.
struct GitStatsLineView: View {
    let stats: GitStats

    @Environment(\.themeColors) private var themeColors

    private var greenColor: Color {
        themeColors.accentColor
    }

    private var redColor: Color {
        Color(hexString: themeColors.palette[1])
    }

    private var magentaColor: Color {
        Color(hexString: themeColors.palette[5])
    }

    private var blueColor: Color {
        Color(hexString: themeColors.palette[4])
    }

    var body: some View {
        HStack(spacing: 6) {
            if stats.uncommittedFiles > 0 {
                Text("\(stats.uncommittedFiles)")
                    .foregroundStyle(.secondary)
            }

            if stats.additions > 0 {
                Text("+\(stats.additions)")
                    .foregroundStyle(greenColor)
            }

            if stats.deletions > 0 {
                Text("-\(stats.deletions)")
                    .foregroundStyle(redColor)
            }

            if let prInfo = stats.prSummary {
                HStack(spacing: 3) {
                    Text("#\(prInfo.number)")
                    prStateView(prInfo.state)
                }
                .foregroundStyle(prColor(prInfo.state))
            }

            if stats.commitsAhead > 0 {
                Text("\(stats.commitsAhead)↑")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }

    @ViewBuilder
    private func prStateView(_ state: PRState) -> some View {
        switch state {
        case .merged:
            Image(systemName: "arrow.triangle.merge")
        case .open:
            Image(systemName: "arrow.triangle.pull")
        case .closed:
            Text(state.label)
        }
    }

    private func prColor(_ state: PRState) -> Color {
        switch state {
        case .open: blueColor
        case .merged: magentaColor
        case .closed: redColor
        }
    }
}

extension PRState {
    var label: String {
        switch self {
        case .open: "open"
        case .merged: "merged"
        case .closed: "closed"
        }
    }
}
