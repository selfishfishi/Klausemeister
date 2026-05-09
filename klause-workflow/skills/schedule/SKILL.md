---
name: schedule
description: Use when the user wants to schedule a Linear project's tickets across worktree queues, distribute work based on dependencies, or says "schedule this project" / "assign tickets to worktrees" / "plan the work" / "save this schedule". Takes a Linear project, builds a dependency-aware assignment plan, then lets the user save the plan, enqueue it immediately, or cancel.
---

# /schedule

Schedule a Linear project's tickets across available Klausemeister worktree queues using dependency-aware load balancing.

## Usage

```
/schedule <project-name> [--name <schedule-name>] [--worktrees <names>] [--all]
```

- `--name <schedule-name>` — override the default schedule name (`<project> · <timestamp>`).
- `--worktrees <names>` — non-interactive subset (comma-separated worktree names, e.g. `--worktrees alpha,beta`). Skips the worktree-selection prompt.
- `--all` — non-interactive, include every worktree in the current repo. Reverts to the pre-selection legacy behavior. Skips the prompt.

If neither `--worktrees` nor `--all` is given, the skill prompts interactively (Step 1.5).

## Step 1: Gather data

### Fetch project issues from Linear

Use the Linear MCP to get all issues in the project:

1. Call `list_projects` to find the project by name. If not found, stop with an error.
2. Call `list_issues` with the project ID. Include relations to get `blocks`/`blockedBy`.
3. Filter out issues that are in `Done` or `Canceled` state.

### Fetch worktree capacity from Klausemeister

Call `listWorktrees` (Klausemeister MCP) to get all tracked worktrees with their current queue state. The response includes `repoId` and `gitWorktreePath` per entry.

**Filter to the current repo.** Klausemeister tracks worktrees across multiple repos and they often share names (`alpha`, `beta`, ...). Scheduling a Klause-team ticket onto another repo's `epsilon` would be silently wrong. To scope:

1. Resolve the current repo root: `git rev-parse --show-toplevel`. If the result contains `/.worktrees/<name>` strip back to the parent — that is the canonical repo root.
2. Keep only worktree entries whose `gitWorktreePath` is inside the canonical repo root (i.e. `gitWorktreePath` starts with `<repo-root>/` or equals `<repo-root>`). This catches both the main checkout and any `.worktrees/*` siblings.
3. If no worktrees match, stop: "No Klausemeister worktrees in this repo (`<repo-root>`). Create one before scheduling."

If `listWorktrees` itself returns nothing, stop: "No worktrees found in Klausemeister."

### Identify already-queued issues

From the `listWorktrees` response, collect all `issueLinearId` values across all inbox, processing, and outbox items. These issues are already scheduled and should be excluded.

## Step 1.5: Choose target worktrees

A schedule should only touch the swimlanes the user wants it on. The user may be actively driving unrelated work in some worktrees and not want those queues clobbered. Before running the algorithm, narrow the worktree list to the user's chosen subset.

### Mode resolution

Pick exactly one mode based on the flags:

- **`--all`** — skip this step; pass every matched worktree to the algorithm. This is the pre-selection legacy behavior.
- **`--worktrees alpha,beta`** — non-interactive. Split the value on commas (trim whitespace). Match each entry against worktree `name` (case-sensitive). If any entry doesn't match a worktree in the matched set, **stop with an error** listing the unknown names; do not silently drop. If the resulting set is empty, also stop.
- **Neither flag** — interactive mode. Continue below.

### Interactive prompt

Render the matched worktrees as a numbered checklist, with a per-row state hint:

- `idle` — no `processing` item.
- `running` — has a `processing` item; show the identifier (e.g. `processing KLA-99`).
- `inbox: N` — current inbox count.

Pre-select the **idle** worktrees (`[x]`) and leave busy ones unchecked (`[ ]`). If **every** worktree is busy, pre-select all of them instead and explain.

Display format:

```
Available worktrees in <repo-name>:
  [x] 1. alpha    idle      inbox: 0
  [x] 2. beta     idle      inbox: 0
  [ ] 3. gamma    running   processing KLA-99, inbox: 3
  [x] 4. delta    idle      inbox: 1

Pre-selected: idle worktrees (1, 2, 4).

Which worktrees should this schedule target?
  - "all"              include every worktree
  - "idle"             accept the default (pre-selected set)
  - "1,2,4"            indices (comma-separated)
  - "alpha,beta"       names (comma-separated)
  - "cancel"           stop, save nothing
```

Wait for an explicit response. Parsing rules:

- `"all"` (case-insensitive) → every matched worktree.
- `"idle"` (case-insensitive) → the default pre-selected set.
- `"cancel"` (case-insensitive) → stop immediately, no MCP calls, report `Cancelled — nothing changed.`
- Comma-separated tokens → for each token, try to parse as an integer index (1-based) into the displayed list; if that fails, match against worktree `name`. Unknown tokens → re-prompt with the unknown names called out; do not proceed.
- Empty / whitespace-only response → re-prompt; do not save an empty schedule.

After resolving the selection, **confirm** before running the algorithm:

```
Targeting 2 worktrees: alpha, beta. Generating plan...
```

### Outcome

The selection result is a filtered worktrees list. Use this filtered list for **Step 2** (algorithm input) and **Step 3** (algorithm run). The previously matched but unselected worktrees are dropped entirely from the algorithm's view — no items are assigned to them, and they're not shown in the resulting plan or load distribution.

The unselected worktrees retain whatever queue state they already had — this skill writes nothing to them.

## Step 2: Prepare algorithm input

Build the input JSON for the scheduling script using the **filtered worktrees list** from Step 1.5 (not the full matched set):

```json
{
  "tickets": [
    {
      "id": "<linear UUID or KLA-XXX identifier>",
      "identifier": "<KLA-123>",
      "title": "<issue title>",
      "weight": <1|2|3>,
      "blockedBy": ["<linear UUID or KLA-XXX identifier>", ...]
    }
  ],
  "worktrees": [
    {
      "worktreeId": "<klausemeister worktree ID>",
      "name": "<worktree name>",
      "currentLoad": <sum of weights already in inbox>
    }
  ]
}
```

`id` and `blockedBy` entries can be either Linear UUIDs or human identifiers
(e.g. `KLA-220`) — `saveSchedule` resolves both via `imported_issues`. The
algorithm itself only cares about identity, so passing the `KLA-XXX` strings
straight from `list_issues` is fine; no UUID-substitution dance required.

**Weight mapping** from Linear estimate or complexity label:
- `simple` label or estimate <= 1 -> weight 1
- `medium` label or estimate 2-3 -> weight 2
- `complex` label or estimate >= 4 -> weight 3
- No label or estimate -> weight 2 (default)

**currentLoad**: Sum the weights of all inbox items for each worktree. Use the same weight mapping — look up each inbox item's issue in the Linear data to determine its weight.

**blockedBy**: Only include blocker IDs that are in the schedulable set (non-done issues in this project). External blockers are ignored by the algorithm.

## Step 3: Run the scheduling algorithm

Run the Python script with the prepared JSON piped to stdin:

```bash
echo '<input JSON>' | python3 klause-workflow/scripts/schedule.py
```

The script path is relative to the repo root. Parse the JSON output.

The algorithm distributes tickets across worktrees in **topological waves**
(see [KLA-201](https://linear.app/selfishfish/issue/KLA-201/schedule-algorithm-topo-wave-parallel-distribution-cross-worktree-deps-allowed))
— cross-worktree dependencies are allowed, and each item in the plan carries
its `level: int` (wave index, 0 = no in-set blockers). Runtime safety is
provided by [KLA-200](https://linear.app/selfishfish/issue/KLA-200/schedule-dependency-aware-getnextitem-skip-blocked-inbox-items):
`getNextItem` skips inbox items whose blockers aren't done yet, so a meister
never claims an item whose dependency is still in flight on a different worktree.

## Step 4: Present the plan

If there are **cycles**, report them prominently:

> **Dependency cycles detected** (these tickets cannot be scheduled):
> - KLA-1 -> KLA-2 -> KLA-3 -> KLA-1

Then present the assignment plan as a table:

> **Assignment Plan**
>
> | Worktree | Queue Position | Ticket | Title | Weight |
> |----------|---------------|--------|-------|--------|
> | alpha    | 1             | KLA-42 | ...   | 2      |
> | alpha    | 2             | KLA-43 | ...   | 1      |
> | beta     | 1             | KLA-44 | ...   | 3      |
>
> **Load distribution**: alpha: 3, beta: 3

The plan and load distribution only cover the **selected** worktrees from Step 1.5; unselected worktrees are not shown.

If there are **unscheduled** tickets (beyond cycles), list them with reasons.

If there are **external blockers** (blockers outside this project), note them.

Present the three-way choice:

```
Choose an action:
  save    store this schedule in Klausemeister, do not enqueue
          (find it later as a pill under the repo header in the sidebar)
  run     store and enqueue immediately (today's behavior)
  cancel  discard, do nothing
```

Do NOT proceed without explicit user choice.

## Step 5: Dispatch on user choice

### Schedule name

Before making any MCP calls, determine the schedule name:
- If the user passed `--name <string>` to `/schedule`, use that string.
- Otherwise use the default: `<linear-project-name> · <YYYY-MM-DD HH:mm>` in the user's local timezone.

### On `save`

1. Call `saveSchedule` with the assignment plan. The payload shape is:
   ```json
   {
     "repoId": "<repo id>",
     "name": "<schedule name>",
     "linearProjectId": "<optional linear project id>",
     "items": [
       {
         "worktreeId": "<klausemeister worktree id>",
         "issueLinearId": "<linear UUID or KLA-XXX identifier>",
         "issueIdentifier": "<KLA-123>",
         "issueTitle": "<issue title>",
         "position": <int>,
         "weight": <1|2|3>,
         "blockedByIssueLinearIds": ["<linear UUID or KLA-XXX identifier>", ...]
       }
     ]
   }
   ```
   `issueLinearId` and entries in `blockedByIssueLinearIds` accept either a
   Linear UUID or the human identifier (e.g. `KLA-220`) — pass whichever the
   Linear MCP gave you. No need to enqueue/listWorktrees/dequeue to coerce
   identifiers into UUIDs first.
2. Report: `Saved as schedule "<name>" (<id>). Open it from the sidebar pill under <repo-name> to view the gantt or run it later.`

### On `run`

1. Call `saveSchedule` with the same payload as above; capture the returned `scheduleId`.
2. Call `runSchedule({ scheduleId })`.
3. Report success/failure per item from `runSchedule`'s response.
4. Call `listWorktrees` to confirm the updated queue state and include a summary.

### On `cancel`

Stop immediately. Make no MCP calls and report: `Cancelled — nothing changed.`

## Error handling

- **Linear MCP unavailable**: Stop with "Linear MCP is not connected. Cannot fetch project data."
- **Klausemeister MCP unavailable**: Stop with "Klausemeister MCP is not connected. Cannot query worktrees."
- **No schedulable tickets**: Report "All tickets in project are either done or already queued."
- **Script fails**: Report the stderr output from the Python script.
- **Unknown worktree name in `--worktrees`**: Stop with "Unknown worktree(s): `<names>`. Available: `<list>`." Do not fall back to a partial set.
- **Empty selection in interactive mode**: Re-prompt; do not save an empty schedule.
- **`--worktrees` and `--all` both passed**: Stop with "Pass either `--worktrees` or `--all`, not both."
