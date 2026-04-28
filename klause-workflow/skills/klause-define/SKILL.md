---
name: klause-define
description: Use when defining a Klausemeister Backlog ticket, assessing its definition depth, stamping a simple/medium/complex label, and moving it to Todo. Matches the /klause-define workflow.
---

# klause-define skill

Define a Klausemeister Backlog ticket using the same workflow as the
`/klause-define` command.

The canonical workflow lives in this plugin's command spec at
`../../commands/klause-define.md`.

Read that file now, then follow it exactly. It is the source of truth for:

- precondition checks
- blocker handling
- definition-depth assessment
- complexity labeling
- Linear updates
- state transition via `transition(command: "define")`

If the command spec is unclear or conflicts with live MCP state, stop and ask
the user rather than guessing.
