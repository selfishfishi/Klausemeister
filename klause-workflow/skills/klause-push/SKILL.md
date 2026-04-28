---
name: klause-push
description: Use when moving a completed Klausemeister processing item to the outbox. Matches the /klause-push workflow.
---

# klause-push skill

Push a completed Klausemeister processing item to the outbox using the same
workflow as the `/klause-push` command.

The canonical workflow lives in this plugin's command spec at
`../../commands/klause-push.md`.

Read that file now, then follow it exactly. It is the source of truth for:

- completed-state precondition checks
- processing-slot checks
- transition via `transition(command: "push")`
- completion reporting

If the command spec is unclear or conflicts with live MCP state, stop and ask
the user rather than guessing.
