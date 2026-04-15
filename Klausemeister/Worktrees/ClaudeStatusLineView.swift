// Klausemeister/Worktrees/ClaudeStatusLineView.swift
import SwiftUI

/// Compact one-line indicator showing the meister's Claude Code session state
/// next to `WorktreeStatusDot` in sidebar rows and swimlane headers. Renders
/// nothing (`EmptyView`) for `.offline`.
///
/// Priority ladder for what the line displays:
/// 1. `activityText` while fresh (≤30s from `activityUpdatedAt`) — shown as
///    a continuously scrolling ticker. Always wins when fresh, any session
///    state, because the meister may narrate while idle too. The ticker's
///    motion pauses via `\.swimlaneAnimating`, but the text stays visible.
/// 2. Otherwise the working/idle/blocked/error label, taking `progressText`
///    for the working case when present.
struct ClaudeStatusLineView: View {
    let state: ClaudeSessionState
    /// Free-form text from the meister's most recent `reportProgress` call.
    /// Wins over the generic label when the session is `.working`. Ignored
    /// for other states (the reducer clears it on non-working transitions).
    var progressText: String?
    /// Ambient narration from the meister's most recent `reportActivity`
    /// call. Shown as a scrolling ticker while fresh.
    var activityText: String?
    /// Timestamp of the last `reportActivity`; paired with `activityText` so
    /// the view can gate freshness.
    var activityUpdatedAt: Date?

    /// How long an activity line is considered live before it hard-cuts
    /// back to the static status label.
    private static let freshness: TimeInterval = 30

    var body: some View {
        if case .offline = state {
            EmptyView()
        } else if let activityText, !activityText.isEmpty, let activityUpdatedAt {
            // Only spin up a TimelineView while there's something to expire.
            // A 1s cadence lets the freshness boundary tick into the view
            // without a reducer-side timer; below that boundary we hard-cut
            // to the static label with a short opacity fade.
            TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                let isFresh = timeline.date.timeIntervalSince(activityUpdatedAt) <= Self.freshness

                Group {
                    if isFresh {
                        TickerText(text: activityText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(height: 12)
                            .id(activityText)
                    } else {
                        staticLabel
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: isFresh)
            }
        } else {
            staticLabel
        }
    }

    private var staticLabel: some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var label: String {
        switch state {
        case let .working(tool):
            // Prefer rich `reportProgress` text when present; fall back to the
            // tool name from the hook; finally fall back to the generic label.
            if let progressText, !progressText.isEmpty {
                return progressText
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
