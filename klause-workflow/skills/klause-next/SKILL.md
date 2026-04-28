---
name: klause-next
description: Use when advancing the current Klausemeister item by reading product state and dispatching to the next workflow command. Matches the /klause-next workflow.
---

# klause-next skill

Advance the current Klausemeister item using the same workflow as the
`/klause-next` command.

The canonical workflow lives in this plugin's command spec at
`../../commands/klause-next.md`.

Read that file now, then follow it exactly. It is the source of truth for:

- product-state inspection
- edge-case handling
- dispatch to pull, define, execute, openPR, babysit, or push
- user-facing reporting

If the command spec is unclear or conflicts with live MCP state, stop and ask
the user rather than guessing.
