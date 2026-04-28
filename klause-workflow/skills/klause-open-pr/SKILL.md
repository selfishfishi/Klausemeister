---
name: klause-open-pr
description: Use when opening a PR for Klausemeister In Progress or In Review work and transitioning the ticket to Testing. Matches the /klause-open-pr workflow.
---

# klause-open-pr skill

Open a pull request for current Klausemeister work using the same workflow as
the `/klause-open-pr` command.

The canonical workflow lives in this plugin's command spec at
`../../commands/klause-open-pr.md`.

Read that file now, then follow it exactly. It is the source of truth for:

- in-progress or in-review precondition checks
- no-code ticket handling
- delegated `/open-pr` preflight and PR creation
- transition via `transition(command: "openPR")`
- completion reporting

If the command spec is unclear or conflicts with live MCP state, stop and ask
the user rather than guessing.
