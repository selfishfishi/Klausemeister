// Klausemeister/Worktrees/ScheduleGanttView.swift
import SwiftUI

/// Full-window overlay visualizing a `Schedule` as a per-worktree gantt grid.
/// Pure presentation — takes plain values + closures, no store dependency.
/// Status tint and motion live in `ScheduleStatusTint` / `GanttCellView`;
/// connector geometry and Bezier-particle drawing live in
/// `ScheduleGanttLayout`.
struct ScheduleGanttView: View {
    let schedule: Schedule
    /// Worktrees in display order — typically the sidebar order. Items whose
    /// `worktreeId` doesn't match any of these are dropped (the worktree was
    /// removed after the schedule was saved).
    let worktrees: [Worktree]
    let isRunInFlight: Bool
    let onRunTapped: () -> Void
    let onFinishTapped: () -> Void
    let onClose: () -> Void

    @Environment(\.themeColors) private var themeColors
    /// Cell the user has clicked. Drives the path-highlight overlay; `nil`
    /// means everything renders normally. Lives in @State because selection
    /// is a transient view-only concern with no business meaning.
    @State private var selectedItemId: String?

    var body: some View {
        let rows = GanttLayout.rows(items: schedule.items, worktrees: worktrees)
        let frames = GanttLayout.frames(rows: rows)
        let totalSize = GanttLayout.totalSize(rows: rows, frames: frames)
        let edges = GanttLayout.connectorEdges(items: schedule.items, frames: frames)
        let pathClosure: PathClosure? = selectedItemId.flatMap { id in
            guard schedule.items.contains(where: { $0.id == id }) else { return nil }
            return GanttLayout.pathClosure(selectedItemId: id, items: schedule.items)
        }

        VStack(spacing: 0) {
            GanttHeader(
                schedule: schedule,
                isRunInFlight: isRunInFlight,
                hasRunnable: schedule.items.contains { $0.status == .planned },
                onRunTapped: onRunTapped,
                onFinishTapped: onFinishTapped,
                onClose: onClose
            )

            Divider()
                .background(themeColors.accentColor.opacity(0.15))

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    // Background tap target: clicking anywhere outside a cell
                    // clears the selection so the user can dismiss the
                    // path-highlight without hunting for a target.
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: totalSize.width, height: totalSize.height)
                        .onTapGesture {
                            selectedItemId = nil
                        }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { rowIndex, row in
                        GanttRowLayer(
                            row: row,
                            rowIndex: rowIndex,
                            frames: frames,
                            selectedItemId: selectedItemId,
                            pathClosure: pathClosure,
                            onCellTapped: { itemId in
                                selectedItemId = (selectedItemId == itemId) ? nil : itemId
                            }
                        )
                    }
                    GanttConnectorOverlay(
                        edges: edges,
                        accentColor: themeColors.accentColor,
                        glowIntensity: themeColors.glowIntensity,
                        highlightedEdgeKeys: pathClosure?.edgeKeys
                    )
                    .frame(width: totalSize.width, height: totalSize.height)
                    .allowsHitTesting(false)
                }
                .frame(width: totalSize.width, height: totalSize.height, alignment: .topLeading)
                .padding(GanttLayout.gridPadding)
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
    let onFinishTapped: () -> Void
    let onClose: () -> Void

    @Environment(\.themeColors) private var themeColors
    @State private var isConfirmingFinish = false

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
                isConfirmingFinish = true
            } label: {
                Label("Finish", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(isRunInFlight)
            .help("Remove this schedule regardless of remaining items")
            .confirmationDialog(
                "Finish \"\(schedule.name)\"?",
                isPresented: $isConfirmingFinish,
                titleVisibility: .visible
            ) {
                Button("Finish Schedule", role: .destructive) {
                    onFinishTapped()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let remaining = schedule.items.count { $0.status != .done }
                Text(remaining > 0
                    ? "\(remaining) item\(remaining == 1 ? "" : "s") still open. They stay in their worktree queues; only the schedule is removed."
                    : "All items are done. The schedule will be removed.")
            }

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

/// Status legend + per-status count, rolled into one strip. Each entry shows
/// the same `StatusPip` symbol that appears on the gantt cells, so the
/// header doubles as the color/icon key. Zero-count statuses still appear
/// (greyed) so the legend is stable as items move through statuses.
private struct StatusSummary: View {
    let items: [ScheduleItem]

    private let order: [ScheduleItemStatus] = [.planned, .queued, .inProgress, .done]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(order, id: \.self) { status in
                let count = items.count(where: { $0.status == status })
                LegendEntry(status: status, count: count)
            }
        }
    }
}

private struct LegendEntry: View {
    let status: ScheduleItemStatus
    let count: Int

    var body: some View {
        let tint = status.tint
        let isEmpty = count == 0
        HStack(spacing: 5) {
            StatusPip(status: status, tint: isEmpty ? .secondary : tint)
                .opacity(isEmpty ? 0.4 : 1.0)
            Text("\(count)")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(isEmpty ? .secondary : .primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var label: String {
        switch status {
        case .planned: "planned"
        case .queued: "queued"
        case .inProgress: "in progress"
        case .done: "done"
        }
    }
}

// MARK: - Row layer

/// One worktree row: a leftmost label plus all `ScheduleItem` cells laid out
/// at frames computed by `GanttLayout`. Each item's frame is positioned
/// absolutely inside the parent ZStack, which lets the connector canvas
/// read the same frames without anchor preferences.
private struct GanttRowLayer: View {
    let row: GanttRow
    let rowIndex: Int
    let frames: [String: CGRect]
    let selectedItemId: String?
    let pathClosure: PathClosure?
    let onCellTapped: (String) -> Void

    @Environment(\.themeColors) private var themeColors

    var body: some View {
        let labelFrame = GanttLayout.labelFrame(rowIndex: rowIndex)
        let tints = themeColors.swimlaneRowTints
        // Index-based palette pick keeps the same worktree on the same tint
        // across launches (String.hashValue is randomized per process).
        let rowTint = tints[rowIndex % max(1, tints.count)]

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowTint.opacity(0.04))
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(rowTint.opacity(0.4))
                        .frame(width: 2)
                }
                .frame(
                    width: max(0, GanttLayout.rowBackgroundWidth(row: row, frames: frames)),
                    height: GanttLayout.cellHeight
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
                    let isSelected = selectedItemId == item.id
                    let isOnPath = pathClosure?.nodeIds.contains(item.id) ?? false
                    let isDimmed = pathClosure != nil && !isOnPath
                    GanttCellView(
                        item: item,
                        isSelected: isSelected,
                        isOnHighlightedPath: isOnPath,
                        isDimmed: isDimmed
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.origin.x, y: frame.origin.y)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onCellTapped(item.id)
                    }
                }
            }
        }
    }
}
