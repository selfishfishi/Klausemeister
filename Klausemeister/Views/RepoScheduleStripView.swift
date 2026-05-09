// Klausemeister/Views/RepoScheduleStripView.swift
import SwiftUI

/// Vertical stack of saved-schedule pills placed as the first child inside
/// each repo's DisclosureGroup in the sidebar (KLA-197). Pure presentation —
/// takes a list of `Schedule` values plus a tap closure and renders nothing
/// when the list is empty so collapsed/empty repos don't grow an empty row.
///
/// The pill shows the schedule name (truncated tail-first) and a thin
/// progress bar indicating `done / total` items. Tapping fires
/// `onScheduleTapped(id)` which `WorktreeFeature` wraps into the
/// `.scheduleTapped` delegate; `AppFeature` currently absorbs that as a
/// no-op until KLA-198 wires the gantt overlay.
struct RepoScheduleStripView: View {
    let schedules: [Schedule]
    let onScheduleTapped: (String) -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        if schedules.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(schedules) { schedule in
                    pill(for: schedule)
                }
            }
            .padding(.horizontal, 4)
            .padding(.leading, 22)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func pill(for schedule: Schedule) -> some View {
        let total = schedule.items.count
        let done = schedule.doneCount
        let fraction = total > 0 ? Double(done) / Double(total) : 0

        Button {
            onScheduleTapped(schedule.id)
        } label: {
            HStack(spacing: 4) {
                Text(displayName(for: schedule))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if total > 0 {
                    ProgressBar(fraction: fraction, tint: themeColors.accentColor)
                        .frame(width: 18, height: 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(themeColors.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(themeColors.accentColor.opacity(0.22), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(displayName(for: schedule)) · \(done)/\(total) done")
    }

    private func displayName(for schedule: Schedule) -> String {
        let name = schedule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasPrefix("agent "),
           let colon = name.firstIndex(of: ":")
        {
            let suffix = name[name.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !suffix.isEmpty { return suffix }
        }
        return name
    }
}

/// Lightweight progress bar — two stacked Capsules, the filled one clipped by
/// its own frame. Deliberately simple so it reads at this tiny size; a real
/// `Gauge` would add too much chrome for a 3pt-tall indicator.
private struct ProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.15))
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: max(0, proxy.size.width * fraction))
            }
        }
    }
}
