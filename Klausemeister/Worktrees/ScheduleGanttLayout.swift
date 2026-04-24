// Klausemeister/Worktrees/ScheduleGanttLayout.swift
import SwiftUI

/// One row of the gantt: a worktree plus its assigned items, sorted by
/// `position`. Items whose `worktreeId` doesn't match any visible worktree
/// are excluded by `GanttLayout.rows(...)`.
struct GanttRow: Identifiable, Equatable {
    let worktree: Worktree
    let items: [ScheduleItem]

    var id: String {
        worktree.id
    }
}

/// Stateless namespace owning gantt geometry: cell frames, label frames,
/// total content size, and the connector edges derived from
/// `blockedByIssueLinearIds`. Everything is deterministic given the inputs,
/// so the row layer and connector overlay both consume the same frames
/// without anchor preferences.
enum GanttLayout {
    /// Width per unit of `weight`. A `weight: 3` cell is 3× as wide as a
    /// `weight: 1` cell.
    static let weightUnit: CGFloat = 60
    static let cellHeight: CGFloat = 56
    static let cellSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 14
    static let labelWidth: CGFloat = 100
    static let gridPadding: CGFloat = 18

    static func rows(items: [ScheduleItem], worktrees: [Worktree]) -> [GanttRow] {
        worktrees.map { worktree in
            let rowItems = items
                .filter { $0.worktreeId == worktree.id }
                .sorted { $0.position < $1.position }
            return GanttRow(worktree: worktree, items: rowItems)
        }
    }

    static func labelFrame(rowIndex: Int) -> CGRect {
        CGRect(
            x: 0,
            y: CGFloat(rowIndex) * (cellHeight + rowSpacing),
            width: labelWidth,
            height: cellHeight
        )
    }

    static func cellWidth(weight: Int) -> CGFloat {
        max(1, CGFloat(weight)) * weightUnit
    }

    /// Rightmost edge of the last cell in a row given the computed frames.
    /// Drives the row background band so it extends to cover any gaps
    /// introduced by dependency-driven shifts (items pushed right to start
    /// after a cross-row blocker).
    static func rowBackgroundWidth(row: GanttRow, frames: [String: CGRect]) -> CGFloat {
        let maxX = row.items.compactMap { frames[$0.id]?.maxX }.max() ?? 0
        return max(maxX, labelWidth)
    }

    static func totalSize(rows: [GanttRow], frames: [String: CGRect]) -> CGSize {
        let widest = rows.map { rowBackgroundWidth(row: $0, frames: frames) }.max() ?? 0
        let height = max(0, CGFloat(rows.count)) * (cellHeight + rowSpacing)
        return CGSize(width: max(widest, 200), height: max(height, cellHeight))
    }

    /// Per-item top-left frame in the grid coordinate space.
    ///
    /// Two-phase layout:
    /// 1. **Position pack** — each row is laid out left-to-right by
    ///    `position`, packing cells tightly (current KLA-198 behavior).
    /// 2. **Dependency relaxation** — items whose blockers end further right
    ///    than their current start get pushed right so they start *after*
    ///    their blockers finish. Subsequent items in the same row cascade by
    ///    the same delta so they don't overlap. The pass is repeated until
    ///    stable (transitive chains settle across passes), bounded by item
    ///    count to prevent infinite loops on pathological cyclic inputs.
    ///
    /// Net effect: a row with no cross-row dependencies looks identical to
    /// before. A cross-row chain `A → B → C` (each on a different worktree)
    /// now lays out diagonally like a real gantt rather than stacking in a
    /// single column.
    static func frames(rows: [GanttRow]) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        var rowOrder: [[String]] = []
        var itemRowIndex: [String: Int] = [:]
        var itemByIssueId: [String: String] = [:]

        // Phase 1: pack left-to-right by position.
        for (rowIndex, row) in rows.enumerated() {
            let originY = CGFloat(rowIndex) * (cellHeight + rowSpacing)
            var originX = labelWidth + cellSpacing
            var rowIds: [String] = []
            for item in row.items {
                let width = cellWidth(weight: item.weight)
                result[item.id] = CGRect(x: originX, y: originY, width: width, height: cellHeight)
                itemRowIndex[item.id] = rowIndex
                itemByIssueId[item.issueLinearId] = item.id
                rowIds.append(item.id)
                originX += width + cellSpacing
            }
            rowOrder.append(rowIds)
        }

        // Phase 2: relax dependency constraints. Each pass pushes any item
        // whose blocker ends past its current `minX` rightward, cascading
        // subsequent cells in the same row by the same delta.
        let allItems: [ScheduleItem] = rows.flatMap(\.items)
        let maxPasses = max(1, allItems.count + 1)
        for _ in 0 ..< maxPasses {
            var changed = false
            for item in allItems {
                guard let currentRect = result[item.id] else { continue }
                var requiredX = currentRect.origin.x
                for blockerIssueId in item.blockedByIssueLinearIds {
                    guard let blockerItemId = itemByIssueId[blockerIssueId],
                          let blockerRect = result[blockerItemId] else { continue }
                    requiredX = max(requiredX, blockerRect.maxX + cellSpacing)
                }
                guard requiredX > currentRect.origin.x else { continue }
                let delta = requiredX - currentRect.origin.x
                shiftRowTail(
                    startingAt: item.id,
                    by: delta,
                    rowOrder: rowOrder,
                    itemRowIndex: itemRowIndex,
                    frames: &result
                )
                changed = true
            }
            if !changed { break }
        }
        return result
    }

    /// Shift `itemId` and every subsequent cell in the same row right by
    /// `delta`. Used by `frames(rows:)` during dependency relaxation so
    /// packed rows preserve their non-overlapping invariant when any member
    /// gets pushed.
    private static func shiftRowTail(
        startingAt itemId: String,
        by delta: CGFloat,
        rowOrder: [[String]],
        itemRowIndex: [String: Int],
        frames: inout [String: CGRect]
    ) {
        guard let rowIndex = itemRowIndex[itemId],
              rowOrder.indices.contains(rowIndex),
              let startIndex = rowOrder[rowIndex].firstIndex(of: itemId)
        else {
            if var rect = frames[itemId] {
                rect.origin.x += delta
                frames[itemId] = rect
            }
            return
        }
        for tailId in rowOrder[rowIndex][startIndex...] {
            if var rect = frames[tailId] {
                rect.origin.x += delta
                frames[tailId] = rect
            }
        }
    }

    /// Build connector edges from each item's `blockedByIssueLinearIds`. Both
    /// blocker and blocked must be in `frames` (i.e. visible in the grid);
    /// blockers outside this schedule are ignored.
    static func connectorEdges(
        items: [ScheduleItem],
        frames: [String: CGRect]
    ) -> [GanttConnectorEdge] {
        let byIssueId = Dictionary(grouping: items, by: \.issueLinearId)
            .compactMapValues(\.first)

        var edges: [GanttConnectorEdge] = []
        for item in items {
            guard let toFrame = frames[item.id] else { continue }
            for blockerIssueId in item.blockedByIssueLinearIds {
                guard let blocker = byIssueId[blockerIssueId],
                      let fromFrame = frames[blocker.id] else { continue }
                let start = CGPoint(x: fromFrame.maxX, y: fromFrame.midY)
                let end = CGPoint(x: toFrame.minX, y: toFrame.midY)
                edges.append(GanttConnectorEdge(
                    fromId: blocker.id,
                    toId: item.id,
                    start: start,
                    end: end
                ))
            }
        }
        return edges
    }
}

/// One blocker → blocked dependency edge whose endpoints are precomputed cell
/// frames. Drawn by `GanttConnectorOverlay` as a Bezier curve with particles
/// flowing in dependency direction.
struct GanttConnectorEdge: Equatable {
    let fromId: String
    let toId: String
    let start: CGPoint
    let end: CGPoint
}

/// Canvas overlay that draws all schedule connectors plus their particle
/// flow. One `TimelineView` drives the entire canvas — particles for every
/// edge are stepped in lock-step from the same `now`, which keeps the
/// motion coherent across the whole graph rather than jittery per-edge.
struct GanttConnectorOverlay: View {
    let edges: [GanttConnectorEdge]
    let accentColor: Color
    let glowIntensity: Double

    /// Particles per edge.
    private let particleCount = 3
    /// Time for one particle to traverse blocker → blocked, seconds.
    private let traversalPeriod: Double = 2.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: edges.isEmpty)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, _ in
                for edge in edges {
                    drawEdge(edge, context: &context, now: now)
                }
            }
        }
    }

    private func drawEdge(
        _ edge: GanttConnectorEdge,
        context: inout GraphicsContext,
        now: Double
    ) {
        let path = bezier(start: edge.start, end: edge.end)

        context.stroke(
            path,
            with: .color(accentColor.opacity(0.30 * glowIntensity)),
            style: StrokeStyle(lineWidth: 0.75, lineCap: .round)
        )

        var haloContext = context
        haloContext.addFilter(.blur(radius: 1.5))
        haloContext.stroke(
            path,
            with: .color(accentColor.opacity(0.18 * glowIntensity)),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
        )

        let phaseStep = 1.0 / Double(particleCount)
        for index in 0 ..< particleCount {
            let raw = (now / traversalPeriod + Double(index) * phaseStep)
                .truncatingRemainder(dividingBy: 1)
            let progress = raw < 0 ? raw + 1 : raw
            let point = pointOnBezier(start: edge.start, end: edge.end, progress: progress)
            let alpha = particleAlpha(progress: progress)
            let radius = 2.5
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: rect),
                with: .color(accentColor.opacity(alpha * glowIntensity))
            )
        }
    }

    /// Fade particles in at the head and out at the tail so they appear to
    /// emerge from the blocker and dissolve into the blocked, rather than
    /// popping into existence.
    private func particleAlpha(progress: Double) -> Double {
        let fade = 0.15
        let leadIn = min(1.0, progress / fade)
        let leadOut = min(1.0, (1.0 - progress) / fade)
        return min(leadIn, leadOut)
    }

    /// Bezier with control points pulled horizontally by ~40% of dx so the
    /// curve eases out of the source cell horizontally before bending toward
    /// the target — reads as "data flow" rather than a straight diagonal.
    private func bezier(start: CGPoint, end: CGPoint) -> Path {
        let deltaX = end.x - start.x
        let bend = max(40, abs(deltaX) * 0.4)
        let control1 = CGPoint(x: start.x + bend, y: start.y)
        let control2 = CGPoint(x: end.x - bend, y: end.y)
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }

    private func pointOnBezier(start: CGPoint, end: CGPoint, progress: Double) -> CGPoint {
        let deltaX = end.x - start.x
        let bend = max(40, abs(deltaX) * 0.4)
        let control1 = CGPoint(x: start.x + bend, y: start.y)
        let control2 = CGPoint(x: end.x - bend, y: end.y)
        let oneMinusT = 1 - progress
        let coordX = oneMinusT * oneMinusT * oneMinusT * start.x
            + 3 * oneMinusT * oneMinusT * progress * control1.x
            + 3 * oneMinusT * progress * progress * control2.x
            + progress * progress * progress * end.x
        let coordY = oneMinusT * oneMinusT * oneMinusT * start.y
            + 3 * oneMinusT * oneMinusT * progress * control1.y
            + 3 * oneMinusT * progress * progress * control2.y
            + progress * progress * progress * end.y
        return CGPoint(x: coordX, y: coordY)
    }
}
