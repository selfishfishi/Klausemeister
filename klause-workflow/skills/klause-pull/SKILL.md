---
name: klause-pull
description: Use when pulling the next Klausemeister inbox item into the processing slot and creating a branch. Matches the /klause-pull workflow.
---

# klause-pull skill

Pull a Klausemeister inbox item into processing using the same workflow as the
`/klause-pull` command.

The canonical workflow lives in this plugin's command spec at
`../../commands/klause-pull.md`.

Read that file now, then follow it exactly. It is the source of truth for:

- queue precondition checks
- blocker handling
- transition via `transition(command: "pull")`
- branch creation
- completion reporting

If the command spec is unclear or conflicts with live MCP state, stop and ask
the user rather than guessing.
