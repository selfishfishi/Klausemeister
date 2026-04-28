---
name: klause-babysit
description: Use when waiting for a Klausemeister ticket's PR checks, merging the PR, and moving the ticket to Done. Matches the /klause-babysit workflow.
---

# klause-babysit skill

Babysit a Klausemeister Testing ticket using the same workflow as the
`/klause-babysit` command.

The canonical workflow lives in this plugin's command spec at
`../../commands/klause-babysit.md`.

Read that file now, then follow it exactly. It is the source of truth for:

- testing-state precondition checks
- PR existence checks
- CI waiting or immediate merge behavior
- transition via `transition(command: "babysit")`
- completion reporting

If the command spec is unclear or conflicts with live MCP state, stop and ask
the user rather than guessing.
