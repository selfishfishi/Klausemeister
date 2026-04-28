---
name: klause-review
description: Use when manually reviewing current Klausemeister In Progress work before opening a PR. Matches the /klause-review workflow.
---

# klause-review skill

Review current Klausemeister work using the same workflow as the
`/klause-review` command.

The canonical workflow lives in this plugin's command spec at
`../../commands/klause-review.md`.

Read that file now, then follow it exactly. It is the source of truth for:

- in-progress precondition checks
- user confirmation
- transition via `transition(command: "review")`
- review-pr skill invocation or direct diff review fallback
- completion reporting

If the command spec is unclear or conflicts with live MCP state, stop and ask
the user rather than guessing.
