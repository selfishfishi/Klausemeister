#!/usr/bin/env python3
"""
Scheduling algorithm for Klausemeister worktree queues.

Reads JSON from stdin describing tickets (with dependencies and weights)
and worktree capacities. Outputs a JSON assignment plan to stdout.

## Algorithm (KLA-201 — topological waves)

Old behavior forced every transitively-dependent ticket onto a single
worktree, because cross-worktree dependencies were disallowed. That
collapses any project with a foundational ticket onto one worktree and
kills parallelism.

The new algorithm:

1. Topologically sort tickets. Detect cycles, report, and exclude.
2. Compute `level` per ticket: the longest path from any source. Level 0
   = no in-set blockers; level N = max(level of blockers) + 1.
3. Walk levels in ascending order. Within each level, sort tickets by
   weight descending (LPT — Longest Processing Time first — a standard
   makespan-minimizing heuristic). Greedy-assign each ticket to the
   worktree with the smallest running load; break load ties by worktree
   name for determinism.
4. Cross-worktree dependencies are allowed. The runtime safety net
   (KLA-200 — `getNextItem` skips blocked inbox items) guarantees a
   meister won't claim an item whose blockers aren't done.

## Input schema
{
  "tickets": [
    {
      "id": "linear-uuid",
      "identifier": "KLA-42",
      "title": "...",
      "weight": 1,            # 1=simple, 2=medium, 3=complex
      "blockedBy": ["id1"]    # linear UUIDs of blockers
    }
  ],
  "worktrees": [
    {
      "worktreeId": "...",
      "name": "alpha",
      "currentLoad": 3        # sum of weights already queued
    }
  ]
}

## Output schema
{
  "plan": [
    {
      "worktreeId": "...",
      "worktreeName": "...",
      "items": [
        {
          "id": "...",
          "identifier": "KLA-42",
          "title": "...",
          "weight": 1,
          "level": 0          # topo wave (0 = source, N = N hops deep)
        }
      ]
    }
  ],
  "cycles": [["KLA-A", "KLA-B", ...]],  # empty when the graph is acyclic
  "unscheduled": [
    {
      "id": "...",
      "identifier": "...",
      "title": "...",
      "reason": "..."
    }
  ]
}
"""

import json
import sys
from collections import defaultdict


def detect_cycles(adj, nodes):
    """Find all strongly connected components with >1 node (cycles) using Tarjan's."""
    index_counter = [0]
    stack = []
    on_stack = set()
    index = {}
    lowlink = {}
    sccs = []

    def strongconnect(v):
        index[v] = index_counter[0]
        lowlink[v] = index_counter[0]
        index_counter[0] += 1
        stack.append(v)
        on_stack.add(v)

        for w in adj.get(v, []):
            if w not in index:
                strongconnect(w)
                lowlink[v] = min(lowlink[v], lowlink[w])
            elif w in on_stack:
                lowlink[v] = min(lowlink[v], index[w])

        if lowlink[v] == index[v]:
            scc = []
            while True:
                w = stack.pop()
                on_stack.discard(w)
                scc.append(w)
                if w == v:
                    break
            if len(scc) > 1:
                sccs.append(scc)

    for v in nodes:
        if v not in index:
            strongconnect(v)

    return sccs


def topological_sort(adj, in_degree, nodes, key_fn=None):
    """Kahn's algorithm. Returns sorted list. Assumes no cycles in input.

    key_fn: optional sort key for deterministic tie-breaking (e.g. identifier).
    """
    key_fn = key_fn or (lambda n: n)
    queue = sorted([n for n in nodes if in_degree[n] == 0], key=key_fn)
    result = []

    while queue:
        node = queue.pop(0)
        result.append(node)
        newly_ready = []
        for neighbor in adj.get(node, []):
            in_degree[neighbor] -= 1
            if in_degree[neighbor] == 0:
                newly_ready.append(neighbor)
        if newly_ready:
            queue.extend(sorted(newly_ready, key=key_fn))
            queue.sort(key=key_fn)

    return result


def compute_levels(adj, topo_order):
    """Longest-path-from-source per node.

    Level 0 for nodes with no predecessors in the set. For every other
    node, level = 1 + max(level of predecessors). We push forward along
    `adj` in topo order so each node's level is final by the time we
    process it.
    """
    levels = {node: 0 for node in topo_order}
    for node in topo_order:
        current = levels[node]
        for successor in adj.get(node, []):
            if current + 1 > levels.get(successor, 0):
                levels[successor] = current + 1
    return levels


def schedule(tickets, worktrees):
    ticket_map = {t["id"]: t for t in tickets}
    all_ids = set(ticket_map.keys())

    # Build adjacency: blockedBy[a] = [b] means a is blocked by b,
    # so the DAG edge is b -> a (b must come before a).
    adj = defaultdict(list)
    in_degree = defaultdict(int)

    # Self-loops are unschedulable but Tarjan's SCC detection only
    # surfaces components of size > 1 — track them separately.
    self_loop_ids = set()

    for ticket in tickets:
        in_degree.setdefault(ticket["id"], 0)
        for blocker_id in ticket.get("blockedBy", []):
            if blocker_id == ticket["id"]:
                self_loop_ids.add(ticket["id"])
            elif blocker_id in all_ids:
                adj[blocker_id].append(ticket["id"])
                in_degree[ticket["id"]] += 1

    # Detect cycles (multi-node SCCs + self-loops)
    cycles = detect_cycles(adj, list(all_ids))
    cycle_ids = set(self_loop_ids)
    for cycle in cycles:
        cycle_ids.update(cycle)
    for sid in self_loop_ids:
        cycles.append([sid])

    # Remove cycle members from scheduling
    schedulable_ids = all_ids - cycle_ids
    clean_adj = {
        blocker: [blocked for blocked in blockeds if blocked in schedulable_ids]
        for blocker, blockeds in adj.items()
        if blocker in schedulable_ids
    }
    clean_in_degree = {nid: 0 for nid in schedulable_ids}
    for blocker, blockeds in clean_adj.items():
        for blocked in blockeds:
            clean_in_degree[blocked] += 1

    def sort_key(tid):
        return ticket_map[tid].get("identifier", tid)

    topo_order = topological_sort(
        clean_adj, clean_in_degree, list(schedulable_ids), key_fn=sort_key
    )
    levels = compute_levels(clean_adj, topo_order)

    # Initialize worktree state
    wt_load = {w["worktreeId"]: w.get("currentLoad", 0) for w in worktrees}
    wt_assignments = {w["worktreeId"]: [] for w in worktrees}
    wt_name = {w["worktreeId"]: w["name"] for w in worktrees}
    ticket_assignment = {}  # ticket_id -> worktreeId
    ticket_level = {}  # ticket_id -> level

    unscheduled = []

    # Group schedulable tickets by level
    by_level = defaultdict(list)
    for tid in schedulable_ids:
        by_level[levels[tid]].append(tid)

    # Walk waves in ascending level order
    for level in sorted(by_level):
        wave = by_level[level]
        # LPT: heaviest tickets first within the wave. Secondary sort by
        # identifier keeps same-weight ties deterministic.
        wave.sort(key=lambda tid: (-ticket_map[tid].get("weight", 2), sort_key(tid)))

        for tid in wave:
            ticket = ticket_map[tid]
            if not wt_load:
                unscheduled.append(
                    {
                        "id": tid,
                        "identifier": ticket.get("identifier", ""),
                        "title": ticket.get("title", ""),
                        "reason": "no worktrees available",
                    }
                )
                continue

            # Least-loaded worktree. Break load ties by name for
            # determinism — the raw `wt_load` dict iteration order is
            # insertion order in CPython, which is effectively the input
            # order, but we want stable output regardless of input order.
            best_wt = min(wt_load, key=lambda wt: (wt_load[wt], wt_name[wt]))
            weight = ticket.get("weight", 2)
            wt_load[best_wt] += weight
            wt_assignments[best_wt].append(tid)
            ticket_assignment[tid] = best_wt
            ticket_level[tid] = level

    # Build the output plan, preserving the per-worktree assignment order.
    plan = []
    for worktree in worktrees:
        wt_id = worktree["worktreeId"]
        items = []
        for tid in wt_assignments[wt_id]:
            ticket = ticket_map[tid]
            items.append(
                {
                    "id": tid,
                    "identifier": ticket.get("identifier", ""),
                    "title": ticket.get("title", ""),
                    "weight": ticket.get("weight", 2),
                    "level": ticket_level[tid],
                }
            )
        if items:
            plan.append(
                {
                    "worktreeId": wt_id,
                    "worktreeName": wt_name[wt_id],
                    "items": items,
                }
            )

    # Sort cycles for deterministic output — Tarjan's SCC order depends
    # on input iteration order, which set() doesn't guarantee stable.
    cycle_output = [
        sorted(ticket_map[cid].get("identifier", cid) for cid in cycle)
        for cycle in cycles
    ]
    cycle_output.sort(key=lambda identifiers: identifiers[0] if identifiers else "")

    unscheduled_cycles = sorted(
        [
            {
                "id": cid,
                "identifier": ticket_map[cid].get("identifier", ""),
                "title": ticket_map[cid].get("title", ""),
                "reason": "part of dependency cycle",
            }
            for cid in cycle_ids
        ],
        key=lambda row: row["identifier"],
    )

    return {
        "plan": plan,
        "cycles": cycle_output,
        "unscheduled": unscheduled + unscheduled_cycles,
    }


def main():
    data = json.load(sys.stdin)
    tickets = data.get("tickets", [])
    worktrees = data.get("worktrees", [])

    if not worktrees:
        json.dump({"error": "no worktrees available"}, sys.stdout)
        sys.exit(1)

    if not tickets:
        json.dump({"plan": [], "cycles": [], "unscheduled": []}, sys.stdout)
        sys.exit(0)

    result = schedule(tickets, worktrees)
    json.dump(result, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
