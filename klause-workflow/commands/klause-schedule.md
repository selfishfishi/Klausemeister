---
description: Schedule a Linear project's tickets across worktree queues using dependency-aware load balancing
argument-hint: "<project-name> [--name <schedule-name>]"
---

# /klause-schedule

Schedule a Linear project's tickets across available Klausemeister worktree queues using a dependency-aware LPT scheduling algorithm.

## Usage

```
/klause-schedule <project-name>
```

## Behavior

This command invokes the `schedule` skill from the klause-workflow plugin. See `klause-workflow/skills/schedule/SKILL.md` for the full procedure. The short version:

1. **Fetch project issues** from Linear (including `blocks`/`blockedBy` relations, estimates, complexity labels). Exclude done/canceled tickets and anything already in a worktree queue.
2. **Query worktree capacity** via the Klausemeister `listWorktrees` MCP tool — get all tracked worktrees with their current inbox/processing/outbox state.
3. **Run the scheduling algorithm** (`klause-workflow/scripts/schedule.py`) — builds a DAG, detects cycles, runs a topological sort, and distributes tickets across worktrees using an LPT (Longest Processing Time) heuristic that respects dependency constraints.
4. **Present the plan** as a table (worktree -> ordered list of tickets with weights). Surface any dependency cycles or unschedulable tickets.
5. **Wait for explicit user choice**: `save` (store the plan without enqueuing), `run` (store and enqueue immediately), or `cancel` (discard).
6. **Dispatch**: on `save`, call `saveSchedule`; on `run`, call `saveSchedule` then `runSchedule`; on `cancel`, stop.

## Scheduling constraints

- A ticket's blockers must be either external (already done) or queued **earlier on the same worktree** — cross-worktree dependencies are not allowed (worktrees execute in parallel with no synchronization).
- Weight mapping: `simple` -> 1, `medium` -> 2, `complex` -> 3, missing -> 2.

## Error handling

- **Linear MCP unavailable**: stop with a clear error.
- **No worktrees in Klausemeister**: stop and tell the user to create worktrees first.
- **All tickets already queued or done**: report "nothing to schedule".
- **Cycles detected**: report them prominently and exclude from the plan.
