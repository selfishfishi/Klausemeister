---
name: klause-schedule
description: Use when scheduling a Linear project's tickets across Klausemeister worktree queues. Matches the /klause-schedule workflow.
---

# klause-schedule skill

Schedule a Linear project's tickets across Klausemeister worktree queues using
the same workflow as the `/klause-schedule` command.

The canonical workflow lives in this plugin's command spec at
`../../commands/klause-schedule.md`.

Read that file now, then follow it exactly. It is the source of truth for:

- project issue fetching
- worktree capacity discovery
- dependency-aware scheduling
- save/run/cancel dispatch
- error handling

The command spec delegates the full procedure to the existing `schedule` skill;
load that skill if directed by the command spec.

If the command spec is unclear or conflicts with live MCP state, stop and ask
the user rather than guessing.
