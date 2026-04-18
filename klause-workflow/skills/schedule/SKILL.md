---
name: schedule
description: Use when the user wants to schedule a Linear project's tickets across worktree queues, distribute work based on dependencies, or says "schedule this project" / "assign tickets to worktrees" / "plan the work" / "save this schedule". Takes a Linear project, builds a dependency-aware assignment plan, then lets the user save the plan, enqueue it immediately, or cancel.
---

# /schedule

Schedule a Linear project's tickets across available Klausemeister worktree queues using dependency-aware load balancing.

## Usage

```
/schedule <project-name> [--name <schedule-name>]
```

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

## Step 2: Prepare algorithm input

Build the input JSON for the scheduling script:

```json
{
  "tickets": [
    {
      "id": "<linear UUID>",
      "identifier": "<KLA-123>",
      "title": "<issue title>",
      "weight": <1|2|3>,
      "blockedBy": ["<linear UUID>", ...]
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
     "name": "<schedule name>",
     "assignments": [
       { "issueLinearId": "<UUID>", "targetWorktreeId": "<worktreeId>", "queuePosition": <int> }
     ]
   }
   ```
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
