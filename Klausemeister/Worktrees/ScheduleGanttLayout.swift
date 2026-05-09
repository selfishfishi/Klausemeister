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
    /// `weight: 1` cell. Sized so a typical `weight: 2` cell holds two lines
    /// of a real Linear title without aggressive truncation.
    static let weightUnit: CGFloat = 120
    static let cellHeight: CGFloat = 84
    /// Horizontal gap between cells. Large enough that connector curves
    /// routed through the gap don't visually intersect adjacent cells.
    static let cellSpacing: CGFloat = 32
    /// Vertical gap between worktree rows. Sized so cross-row curves have
    /// clear "channel" space between rows to bend through.
    static let rowSpacing: CGFloat = 40
    static let labelWidth: CGFloat = 110
    static let gridPadding: CGFloat = 24

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
                let points = connectorRoute(
                    fromFrame: fromFrame,
                    toFrame: toFrame,
                    frames: Array(frames.values)
                )
                edges.append(GanttConnectorEdge(
                    fromId: blocker.id,
                    toId: item.id,
                    start: start,
                    end: end,
                    points: points
                ))
            }
        }
        return edges
    }

    /// Route dependencies through the gutters between rows instead of drawing
    /// straight through the middle of the schedule lane. Short edge stubs leave
    /// and enter through the guaranteed cell spacing on each side; long travel
    /// happens in row gutters, and the cross-row vertical lane is scanned for a
    /// clear x-coordinate so it doesn't pass through intervening boxes.
    static func connectorRoute(
        fromFrame: CGRect,
        toFrame: CGRect,
        frames: [CGRect]
    ) -> [CGPoint] {
        let start = CGPoint(x: fromFrame.maxX, y: fromFrame.midY)
        let end = CGPoint(x: toFrame.minX, y: toFrame.midY)
        let exitX = fromFrame.maxX + cellSpacing / 2
        let entryX = toFrame.minX - cellSpacing / 2
        let sourceGutterY: CGFloat
        let targetGutterY: CGFloat

        if toFrame.midY < fromFrame.midY {
            sourceGutterY = fromFrame.minY - rowSpacing / 2
            targetGutterY = toFrame.maxY + rowSpacing / 2
        } else if toFrame.midY > fromFrame.midY {
            sourceGutterY = fromFrame.maxY + rowSpacing / 2
            targetGutterY = toFrame.minY - rowSpacing / 2
        } else {
            sourceGutterY = fromFrame.maxY + rowSpacing / 2
            targetGutterY = sourceGutterY
        }

        let preferredLaneX = (exitX + entryX) / 2
        let laneX = verticalLaneX(
            preferred: preferredLaneX,
            verticalRange: min(sourceGutterY, targetGutterY) ... max(sourceGutterY, targetGutterY),
            frames: frames
        )

        return compactedRoute([
            start,
            CGPoint(x: exitX, y: start.y),
            CGPoint(x: exitX, y: sourceGutterY),
            CGPoint(x: laneX, y: sourceGutterY),
            CGPoint(x: laneX, y: targetGutterY),
            CGPoint(x: entryX, y: targetGutterY),
            CGPoint(x: entryX, y: end.y),
            end
        ])
    }

    private static func verticalLaneX(
        preferred: CGFloat,
        verticalRange: ClosedRange<CGFloat>,
        frames: [CGRect]
    ) -> CGFloat {
        let paddedFrames = frames.map { $0.insetBy(dx: -8, dy: -4) }
        let maxFrameX = paddedFrames.map(\.maxX).max() ?? preferred
        let minSearchX = labelWidth + cellSpacing / 2
        let maxSearchX = max(maxFrameX + cellSpacing, preferred)

        func isClear(_ laneX: CGFloat) -> Bool {
            paddedFrames.allSatisfy { frame in
                guard frame.maxY >= verticalRange.lowerBound,
                      frame.minY <= verticalRange.upperBound else { return true }
                return laneX < frame.minX || laneX > frame.maxX
            }
        }

        if isClear(preferred) { return preferred }

        let stride: CGFloat = 12
        var offset = stride
        while offset <= maxSearchX - minSearchX + stride {
            let left = preferred - offset
            if left >= minSearchX, isClear(left) {
                return left
            }

            let right = preferred + offset
            if right <= maxSearchX, isClear(right) {
                return right
            }

            offset += stride
        }

        return maxFrameX + cellSpacing
    }

    private static func compactedRoute(_ points: [CGPoint]) -> [CGPoint] {
        points.reduce(into: []) { result, point in
            guard result.last != point else { return }
            result.append(point)
        }
    }

    /// Closure of nodes and edges that must complete before `selectedItemId`:
    /// the selected item plus its transitive blockers. An edge is highlighted
    /// only when it connects two nodes in that upstream dependency graph, so
    /// selecting a cell dims downstream dependents and unrelated branches.
    static func dependencyClosure(
        selectedItemId: String,
        items: [ScheduleItem]
    ) -> PathClosure {
        let itemIdByIssueId = Dictionary(uniqueKeysWithValues: items.map { ($0.issueLinearId, $0.id) })

        // itemId -> its blocker itemIds, resolved through issueLinearId.
        var blockers: [String: [String]] = [:]
        for item in items {
            let blockerItemIds = item.blockedByIssueLinearIds.compactMap { itemIdByIssueId[$0] }
            blockers[item.id] = blockerItemIds
        }

        let ancestors = traverse(from: selectedItemId, edges: blockers)
        let nodes = ancestors.union([selectedItemId])

        var edgeKeys: Set<String> = []
        for item in items where nodes.contains(item.id) {
            for blockerIssueId in item.blockedByIssueLinearIds {
                guard let blockerItemId = itemIdByIssueId[blockerIssueId],
                      nodes.contains(blockerItemId) else { continue }
                edgeKeys.insert(GanttConnectorEdge.key(fromId: blockerItemId, toId: item.id))
            }
        }
        return PathClosure(nodeIds: nodes, edgeKeys: edgeKeys)
    }

    /// BFS from `start` over `edges`. Excludes `start` from the result so the
    /// caller can decide how to treat the selection vs its neighbors.
    private static func traverse(from start: String, edges: [String: [String]]) -> Set<String> {
        var visited: Set<String> = []
        var queue: [String] = [start]
        while let node = queue.popLast() {
            for next in edges[node] ?? [] where visited.insert(next).inserted {
                queue.append(next)
            }
        }
        return visited
    }
}

/// Result of `GanttLayout.dependencyClosure(...)`. Two sets the view layer
/// can consult cheaply per cell / per edge during render.
struct PathClosure: Equatable {
    /// Item IDs in the closure (transitive blockers plus the selection).
    let nodeIds: Set<String>
    /// Edge keys (`"<fromId>->\(toId)"`) connecting two `nodeIds` members.
    let edgeKeys: Set<String>
}

/// One blocker → blocked dependency edge whose endpoints are precomputed cell
/// frames. Drawn by `GanttConnectorOverlay` as a routed connector with
/// particles flowing in dependency direction.
struct GanttConnectorEdge: Equatable {
    let fromId: String
    let toId: String
    let start: CGPoint
    let end: CGPoint
    let points: [CGPoint]

    /// Stable key matching `PathClosure.edgeKeys` so the overlay can decide
    /// per-edge whether the user's selection includes it.
    var key: String {
        Self.key(fromId: fromId, toId: toId)
    }

    static func key(fromId: String, toId: String) -> String {
        "\(fromId)->\(toId)"
    }
}

/// Canvas overlay that draws all schedule connectors plus their particle
/// flow. One `TimelineView` drives the entire canvas — particles for every
/// edge are stepped in lock-step from the same `now`, which keeps the
/// motion coherent across the whole graph rather than jittery per-edge.
///
/// When `highlightedEdgeKeys` is non-nil, edges in the set draw normally and
/// edges outside it dim down to a faint trace. This is what powers the
/// "click a cell to see all paths involving it" interaction.
struct GanttConnectorOverlay: View {
    let edges: [GanttConnectorEdge]
    let accentColor: Color
    let glowIntensity: Double
    /// `nil` = no selection; render all edges normally.
    /// Non-nil = render edges in the set normally, dim the rest.
    var highlightedEdgeKeys: Set<String>?

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
        let path = connectorPath(points: edge.points)
        // Three states: no-selection (full opacity), selected-and-on-path
        // (boosted), selected-and-off-path (faded). Multipliers fold through
        // the existing glowIntensity so themes that darken the gantt still
        // honor that.
        let opacityFactor: Double = {
            guard let highlightedEdgeKeys else { return 1.0 }
            return highlightedEdgeKeys.contains(edge.key) ? 1.6 : 0.18
        }()

        context.stroke(
            path,
            with: .color(accentColor.opacity(0.30 * glowIntensity * opacityFactor)),
            style: StrokeStyle(lineWidth: 0.75, lineCap: .round, lineJoin: .round)
        )

        var haloContext = context
        haloContext.addFilter(.blur(radius: 1.5))
        haloContext.stroke(
            path,
            with: .color(accentColor.opacity(0.18 * glowIntensity * opacityFactor)),
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
        )

        let phaseStep = 1.0 / Double(particleCount)
        for index in 0 ..< particleCount {
            let raw = (now / traversalPeriod + Double(index) * phaseStep)
                .truncatingRemainder(dividingBy: 1)
            let progress = raw < 0 ? raw + 1 : raw
            let point = pointOnRoute(edge.points, progress: progress)
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
                with: .color(accentColor.opacity(alpha * glowIntensity * opacityFactor))
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

    private func connectorPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func pointOnRoute(_ points: [CGPoint], progress: Double) -> CGPoint {
        guard let first = points.first else { return .zero }
        let segments = zip(points, points.dropFirst()).map { start, end in
            (start: start, end: end, length: hypot(end.x - start.x, end.y - start.y))
        }
        let totalLength = segments.reduce(0) { $0 + $1.length }
        guard totalLength > 0 else { return first }

        var remaining = CGFloat(progress) * totalLength
        for segment in segments {
            guard segment.length > 0 else { continue }
            if remaining <= segment.length {
                let t = remaining / segment.length
                return CGPoint(
                    x: segment.start.x + (segment.end.x - segment.start.x) * t,
                    y: segment.start.y + (segment.end.y - segment.start.y) * t
                )
            }
            remaining -= segment.length
        }
        return points.last ?? first
    }
}
