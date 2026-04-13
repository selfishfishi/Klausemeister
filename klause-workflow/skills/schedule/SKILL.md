---
name: schedule
description: Use when the user wants to schedule a Linear project's tickets across worktree queues, distribute work based on dependencies, or says "schedule this project" / "assign tickets to worktrees" / "plan the work". Takes a Linear project, builds a dependency-aware assignment plan, and enqueues after approval.
---

# /schedule

Schedule a Linear project's tickets across available Klausemeister worktree queues using dependency-aware load balancing.

## Usage

```
/schedule <project-name>
```

## Step 1: Gather data

### Fetch project issues from Linear

Use the Linear MCP to get all issues in the project:

1. Call `list_projects` to find the project by name. If not found, stop with an error.
2. Call `list_issues` with the project ID. Include relations to get `blocks`/`blockedBy`.
3. Filter out issues that are in `Done` or `Canceled` state.

### Fetch worktree capacity from Klausemeister

Call `listWorktrees` (Klausemeister MCP) to get all tracked worktrees with their current queue state.

If no worktrees are available, stop: "No worktrees found in Klausemeister."

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

Ask: **"Approve this plan? (yes/no)"**

Do NOT proceed without explicit user approval.

## Step 5: Enqueue

On approval, enqueue each ticket in plan order using the Klausemeister MCP:

For each worktree in the plan, for each item in order:
1. Call `enqueueItem` with `issueLinearId` and `targetWorktreeId`
2. If it fails, report the error and continue with the next item

After all enqueue calls complete, report:
- How many tickets were enqueued successfully
- Any failures
- The updated queue state (call `listWorktrees` again to confirm)

## Error handling

- **Linear MCP unavailable**: Stop with "Linear MCP is not connected. Cannot fetch project data."
- **Klausemeister MCP unavailable**: Stop with "Klausemeister MCP is not connected. Cannot query worktrees."
- **No schedulable tickets**: Report "All tickets in project are either done or already queued."
- **Script fails**: Report the stderr output from the Python script.
