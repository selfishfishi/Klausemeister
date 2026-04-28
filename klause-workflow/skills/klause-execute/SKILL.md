---
name: klause-execute
description: Use when executing a Klausemeister Todo ticket, routing implementation by its simple/medium/complex label, and moving it to In Progress. Matches the /klause-execute workflow.
---

# klause-execute skill

Execute a Klausemeister Todo ticket using the same workflow as the
`/klause-execute` command.

The canonical workflow lives in this plugin's command spec at
`../../commands/klause-execute.md`.

Read that file now, then follow it exactly. It is the source of truth for:

- precondition checks
- blocker handling
- transition via `transition(command: "execute")`
- complexity-label routing
- direct, plan-first, or feature-dev implementation paths
- completion reporting

If the command spec is unclear or conflicts with live MCP state, stop and ask
the user rather than guessing.
