#!/usr/bin/env python3
"""
Scheduling algorithm for Klausemeister worktree queues.

Reads JSON from stdin describing tickets (with dependencies and weights)
and worktree capacities. Outputs a JSON assignment plan to stdout.

Input schema:
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

Output schema:
{
  "plan": [
    {
      "worktreeId": "...",
      "worktreeName": "...",
      "items": [
        {"id": "...", "identifier": "KLA-42", "title": "...", "weight": 1}
      ]
    }
  ],
  "cycles": [["id1", "id2", ...]],    # cycles detected (empty if none)
  "unscheduled": [{"id": "...", "reason": "..."}]
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


def schedule(tickets, worktrees):
    """
    Assign tickets to worktrees using dependency-aware LPT scheduling.

    Algorithm:
    1. Build DAG, detect and remove cycles
    2. Topological sort remaining tickets
    3. For each ticket in topo order, assign to the worktree where:
       a. All its blockers are either already assigned earlier on that same
          worktree, or are not assigned to any worktree (meaning they're
          done/external)
       b. Among valid worktrees, pick the one with the least current load
    """
    ticket_map = {t["id"]: t for t in tickets}
    all_ids = set(ticket_map.keys())

    # Build adjacency list: blockedBy[a] = [b] means a is blocked by b,
    # so b -> a in the DAG (b must come before a).
    adj = defaultdict(list)       # forward edges: blocker -> blocked
    in_degree = defaultdict(int)

    # Track self-loops separately — they are unschedulable but Tarjan's
    # SCC algorithm only detects components of size > 1.
    self_loop_ids = set()

    for t in tickets:
        in_degree.setdefault(t["id"], 0)
        for blocker_id in t.get("blockedBy", []):
            if blocker_id == t["id"]:
                self_loop_ids.add(t["id"])
            elif blocker_id in all_ids:
                adj[blocker_id].append(t["id"])
                in_degree[t["id"]] += 1

    # Detect cycles (multi-node SCCs + self-loops)
    cycles = detect_cycles(adj, list(all_ids))
    cycle_ids = set(self_loop_ids)
    for cycle in cycles:
        cycle_ids.update(cycle)
    for sid in self_loop_ids:
        cycles.append([sid])

    # Remove cycle members from scheduling
    schedulable_ids = all_ids - cycle_ids
    clean_adj = {k: [v for v in vs if v in schedulable_ids]
                 for k, vs in adj.items() if k in schedulable_ids}
    clean_in_degree = {nid: 0 for nid in schedulable_ids}
    for src, dsts in clean_adj.items():
        for dst in dsts:
            clean_in_degree[dst] += 1

    def sort_key(tid):
        return ticket_map[tid].get("identifier", tid)

    topo_order = topological_sort(clean_adj, clean_in_degree, list(schedulable_ids), key_fn=sort_key)

    # Initialize worktree loads and assignment tracking
    wt_load = {w["worktreeId"]: w.get("currentLoad", 0) for w in worktrees}
    wt_assignments = {w["worktreeId"]: [] for w in worktrees}  # ordered list of ticket ids
    wt_name = {w["worktreeId"]: w["name"] for w in worktrees}
    ticket_assignment = {}  # ticket_id -> worktreeId

    unscheduled = []

    for ticket_id in topo_order:
        ticket = ticket_map[ticket_id]
        blockers_in_scope = [b for b in ticket.get("blockedBy", []) if b in all_ids]

        # Find valid worktrees: all in-scope blockers must be assigned
        # earlier on the same worktree.
        valid_wts = []
        for wt_id in wt_load:
            ok = True
            for blocker_id in blockers_in_scope:
                if blocker_id in cycle_ids:
                    # Blocker is in a cycle and unschedulable
                    ok = False
                    break
                if blocker_id not in ticket_assignment:
                    # Blocker not scheduled — it's external/done, OK
                    continue
                blocker_wt = ticket_assignment[blocker_id]
                if blocker_wt != wt_id:
                    # Blocker is on a different worktree — no guarantee
                    # it finishes before this ticket starts on wt_id.
                    # This worktree is not valid for this ticket.
                    ok = False
                    break
                # Blocker is on same worktree — verify it's earlier
                if blocker_id not in wt_assignments[wt_id]:
                    ok = False
                    break
            if ok:
                valid_wts.append(wt_id)

        if not valid_wts:
            unscheduled.append({
                "id": ticket_id,
                "identifier": ticket.get("identifier", ""),
                "title": ticket.get("title", ""),
                "reason": "all blockers in cycles or no valid worktree"
            })
            continue

        # Pick worktree with least load (LPT heuristic)
        best_wt = min(valid_wts, key=lambda wt: wt_load[wt])
        weight = ticket.get("weight", 2)
        wt_load[best_wt] += weight
        wt_assignments[best_wt].append(ticket_id)
        ticket_assignment[ticket_id] = best_wt

    # Build output plan
    plan = []
    for w in worktrees:
        wt_id = w["worktreeId"]
        items = []
        for tid in wt_assignments[wt_id]:
            t = ticket_map[tid]
            items.append({
                "id": tid,
                "identifier": t.get("identifier", ""),
                "title": t.get("title", ""),
                "weight": t.get("weight", 2)
            })
        if items:
            plan.append({
                "worktreeId": wt_id,
                "worktreeName": wt_name[wt_id],
                "items": items
            })

    cycle_output = []
    for cycle in cycles:
        cycle_output.append([ticket_map[cid].get("identifier", cid) for cid in cycle])

    unscheduled_cycles = sorted(
        [
            {
                "id": cid,
                "identifier": ticket_map[cid].get("identifier", ""),
                "title": ticket_map[cid].get("title", ""),
                "reason": "part of dependency cycle"
            }
            for cid in cycle_ids
        ],
        key=lambda x: x["identifier"]
    )

    return {
        "plan": plan,
        "cycles": cycle_output,
        "unscheduled": unscheduled + unscheduled_cycles
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
