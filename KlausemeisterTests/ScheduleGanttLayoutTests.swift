import CoreGraphics
import Testing
@testable import Klausemeister

private func scheduleItem(
    id: String,
    issueLinearId: String,
    blockedByIssueLinearIds: [String] = [],
    position: Int = 0,
    worktreeId: String = "worktree-1"
) -> ScheduleItem {
    ScheduleItem(
        id: id,
        scheduleId: "schedule-1",
        worktreeId: worktreeId,
        issueLinearId: issueLinearId,
        issueIdentifier: id,
        issueTitle: id,
        position: position,
        weight: 1,
        blockedByIssueLinearIds: blockedByIssueLinearIds,
        status: .planned
    )
}

@Test func `dependencyClosure includes selected item and transitive blockers only`() {
    let itemA = scheduleItem(id: "A", issueLinearId: "issue-A")
    let itemB = scheduleItem(id: "B", issueLinearId: "issue-B", blockedByIssueLinearIds: ["issue-A"])
    let itemC = scheduleItem(id: "C", issueLinearId: "issue-C", blockedByIssueLinearIds: ["issue-B"])
    let itemD = scheduleItem(id: "D", issueLinearId: "issue-D", blockedByIssueLinearIds: ["issue-A"])

    let closure = GanttLayout.dependencyClosure(
        selectedItemId: "B",
        items: [itemA, itemB, itemC, itemD]
    )

    #expect(closure.nodeIds == Set(["A", "B"]))
    #expect(closure.edgeKeys == Set([GanttConnectorEdge.key(fromId: "A", toId: "B")]))
}

@Test func `dependencyClosure keeps all edges connecting selected dependency graph`() {
    let itemA = scheduleItem(id: "A", issueLinearId: "issue-A")
    let itemB = scheduleItem(id: "B", issueLinearId: "issue-B", blockedByIssueLinearIds: ["issue-A"])
    let itemC = scheduleItem(id: "C", issueLinearId: "issue-C", blockedByIssueLinearIds: ["issue-A"])
    let itemD = scheduleItem(
        id: "D",
        issueLinearId: "issue-D",
        blockedByIssueLinearIds: ["issue-B", "issue-C"]
    )

    let closure = GanttLayout.dependencyClosure(
        selectedItemId: "D",
        items: [itemA, itemB, itemC, itemD]
    )

    #expect(closure.nodeIds == Set(["A", "B", "C", "D"]))
    #expect(closure.edgeKeys == Set([
        GanttConnectorEdge.key(fromId: "A", toId: "B"),
        GanttConnectorEdge.key(fromId: "A", toId: "C"),
        GanttConnectorEdge.key(fromId: "B", toId: "D"),
        GanttConnectorEdge.key(fromId: "C", toId: "D")
    ]))
}

@Test func `connectorEdges route same-row dependencies around intervening boxes`() throws {
    let worktree = Worktree(id: "worktree-1", name: "Delta", gitWorktreePath: "/tmp/delta", sortOrder: 0)
    let itemA = scheduleItem(id: "A", issueLinearId: "issue-A", position: 0)
    let itemMiddle = scheduleItem(id: "M", issueLinearId: "issue-M", position: 1)
    let itemB = scheduleItem(id: "B", issueLinearId: "issue-B", blockedByIssueLinearIds: ["issue-A"], position: 2)
    let rows = GanttLayout.rows(items: [itemA, itemMiddle, itemB], worktrees: [worktree])
    let frames = GanttLayout.frames(rows: rows)

    let edge = GanttLayout.connectorEdges(items: [itemA, itemMiddle, itemB], frames: frames).first

    #expect(edge?.key == GanttConnectorEdge.key(fromId: "A", toId: "B"))
    #expect(try route(edge?.points ?? [], intersects: #require(frames["M"])) == false)
}

@Test func `connectorEdges choose clear vertical lane for cross-row dependencies`() throws {
    let itemA = scheduleItem(id: "A", issueLinearId: "issue-A")
    let itemB = scheduleItem(id: "B", issueLinearId: "issue-B", blockedByIssueLinearIds: ["issue-A"])
    let itemMiddle = scheduleItem(id: "M", issueLinearId: "issue-M")
    let frames = [
        "A": CGRect(x: 142, y: 0, width: 120, height: 84),
        "B": CGRect(x: 600, y: 248, width: 120, height: 84),
        "M": CGRect(x: 350, y: 124, width: 120, height: 84)
    ]

    let edge = GanttLayout.connectorEdges(items: [itemA, itemB, itemMiddle], frames: frames).first

    #expect(edge?.key == GanttConnectorEdge.key(fromId: "A", toId: "B"))
    #expect(try route(edge?.points ?? [], intersects: #require(frames["M"])) == false)
}

private func route(_ points: [CGPoint], intersects frame: CGRect) -> Bool {
    let interior = frame.insetBy(dx: 1, dy: 1)
    return zip(points, points.dropFirst()).contains { start, end in
        segment(start, end, intersects: interior)
    }
}

private func segment(_ start: CGPoint, _ end: CGPoint, intersects frame: CGRect) -> Bool {
    if start.y == end.y {
        let segmentMinX = min(start.x, end.x)
        let segmentMaxX = max(start.x, end.x)
        return frame.minY ... frame.maxY ~= start.y
            && segmentMaxX >= frame.minX
            && segmentMinX <= frame.maxX
    }

    if start.x == end.x {
        let segmentMinY = min(start.y, end.y)
        let segmentMaxY = max(start.y, end.y)
        return frame.minX ... frame.maxX ~= start.x
            && segmentMaxY >= frame.minY
            && segmentMinY <= frame.maxY
    }

    return false
}
