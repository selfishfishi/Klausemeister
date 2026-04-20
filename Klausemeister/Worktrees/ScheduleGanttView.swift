// Klausemeister/Worktrees/ScheduleGanttView.swift
import SwiftUI

/// Full-window overlay that visualizes a saved `Schedule` as a per-worktree
/// gantt grid. Pure presentation — takes plain values + closures, no store
/// dependency.
///
/// Layout: header strip on top (name, status summary, Run/Close), then a
/// 2-D scrolling grid where each row is a worktree and each cell is a
/// `ScheduleItem` whose width is proportional to its `weight`. Cells render
/// with status-driven tint and motion (planned: dormant; queued: breathing
/// edge; inProgress: rotating comet; done: settled, dimmed). A `Canvas`
/// overlay (`GanttConnectorOverlay`) draws Bezier connectors with flowing
/// particles between `blockedBy` pairs within the schedule.
struct ScheduleGanttView: View {
    /// The schedule being visualized.
    let schedule: Schedule
    /// Worktrees in display order — typically the sidebar order. Items whose
    /// `worktreeId` doesn't match any of these are dropped (the worktree was
    /// removed after the schedule was saved).
    let worktrees: [Worktree]
    /// True while a `runScheduleTapped` effect is in flight for this schedule.
    let isRunInFlight: Bool
    /// Run-Schedule tap callback. Disabled if `isRunInFlight` or no `.planned`
    /// items remain.
    let onRunTapped: () -> Void
    /// Close-button (and outside-click / Escape) callback.
    let onClose: () -> Void

    @Environment(\.themeColors) private var themeColors

    private let layout = GanttLayout()

    var body: some View {
        let rows = layout.rows(items: schedule.items, worktrees: worktrees)
        let frames = layout.frames(rows: rows)
        let totalSize = layout.totalSize(rows: rows)
        let edges = layout.connectorEdges(items: schedule.items, frames: frames)

        VStack(spacing: 0) {
            GanttHeader(
                schedule: schedule,
                isRunInFlight: isRunInFlight,
                hasRunnable: schedule.items.contains { $0.status == .planned },
                onRunTapped: onRunTapped,
                onClose: onClose
            )

            Divider()
                .background(themeColors.accentColor.opacity(0.15))

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    ForEach(rows.indices, id: \.self) { rowIndex in
                        let row = rows[rowIndex]
                        GanttRowLayer(
                            row: row,
                            rowIndex: rowIndex,
                            frames: frames,
                            layout: layout
                        )
                    }
                    GanttConnectorOverlay(
                        edges: edges,
                        accentColor: themeColors.accentColor,
                        glowIntensity: themeColors.glowIntensity
                    )
                    .frame(width: totalSize.width, height: totalSize.height)
                    .allowsHitTesting(false)
                }
                .frame(width: totalSize.width, height: totalSize.height, alignment: .topLeading)
                .padding(layout.gridPadding)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .glassPanel(tint: themeColors.accentColor, cornerRadius: 24)
        .padding(40)
    }
}

// MARK: - Header

private struct GanttHeader: View {
    let schedule: Schedule
    let isRunInFlight: Bool
    let hasRunnable: Bool
    let onRunTapped: () -> Void
    let onClose: () -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.name)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                StatusSummary(items: schedule.items)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            if isRunInFlight {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            Button(action: onRunTapped) {
                Label("Run Schedule", systemImage: "play.fill")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(themeColors.accentColor)
            .disabled(isRunInFlight || !hasRunnable)
            .help(hasRunnable ? "Enqueue all planned items" : "Nothing left to run")

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct StatusSummary: View {
    let items: [ScheduleItem]

    var body: some View {
        let counts = Dictionary(grouping: items, by: \.status).mapValues(\.count)
        let parts: [String] = [
            "\(counts[.inProgress, default: 0]) in progress",
            "\(counts[.queued, default: 0]) queued",
            "\(counts[.planned, default: 0]) planned",
            "\(counts[.done, default: 0]) done"
        ]
        Text(parts.joined(separator: " · "))
    }
}

// MARK: - Row layer

/// One worktree row: a leftmost label plus all `ScheduleItem` cells laid out
/// at frames computed by `GanttLayout`. Each item's frame is positioned
/// absolutely inside the parent ZStack, which lets the connector canvas
/// read the same frames without anchor preferences.
struct GanttRowLayer: View {
    let row: GanttRow
    let rowIndex: Int
    let frames: [String: CGRect]
    let layout: GanttLayout

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        let labelFrame = layout.labelFrame(rowIndex: rowIndex)
        let tints = themeColors.swimlaneRowTints
        let tintIndex = abs(row.worktree.id.hashValue) % max(1, tints.count)
        let rowTint = tints[tintIndex]

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowTint.opacity(0.04))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(rowTint.opacity(0.4))
                        .frame(width: 2)
                }
                .frame(
                    width: max(0, layout.totalRowWidth(items: row.items)),
                    height: layout.cellHeight
                )
                .offset(x: 0, y: labelFrame.origin.y)

            Text(row.worktree.name)
                .font(.callout.weight(.medium))
                .foregroundStyle(rowTint)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .frame(
                    width: labelFrame.width,
                    height: labelFrame.height,
                    alignment: .leading
                )
                .offset(x: labelFrame.origin.x, y: labelFrame.origin.y)

            ForEach(row.items) { item in
                if let frame = frames[item.id] {
                    GanttCellView(item: item)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.origin.x, y: frame.origin.y)
                }
            }
        }
    }
}
