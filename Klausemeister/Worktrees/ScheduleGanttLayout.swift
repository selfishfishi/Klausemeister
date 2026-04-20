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

    /// Total horizontal extent of one row including label, cells, and
    /// inter-cell spacing. Matches the rightmost cell's `maxX` (no trailing
    /// stray spacing) so the row background band lines up cleanly with the
    /// last cell's right edge.
    static func totalRowWidth(items: [ScheduleItem]) -> CGFloat {
        let cellsWidth = items.reduce(CGFloat(0)) { acc, item in
            acc + cellWidth(weight: item.weight)
        }
        let spacings = CGFloat(items.count) * cellSpacing
        return labelWidth + cellsWidth + spacings
    }

    static func totalSize(rows: [GanttRow]) -> CGSize {
        let widest = rows.map { totalRowWidth(items: $0.items) }.max() ?? 0
        let height = max(0, CGFloat(rows.count)) * (cellHeight + rowSpacing)
        return CGSize(width: max(widest, 200), height: max(height, cellHeight))
    }

    /// Per-item top-left frame in the grid coordinate space (origin at the
    /// top-left of the first row, inside the grid padding inset).
    static func frames(rows: [GanttRow]) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        for (rowIndex, row) in rows.enumerated() {
            let originY = CGFloat(rowIndex) * (cellHeight + rowSpacing)
            var originX = labelWidth + cellSpacing
            for item in row.items {
                let width = cellWidth(weight: item.weight)
                result[item.id] = CGRect(x: originX, y: originY, width: width, height: cellHeight)
                originX += width + cellSpacing
            }
        }
        return result
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
