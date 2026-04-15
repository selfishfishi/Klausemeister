---
description: Open a PR with pre-flight checks, transitioning to Testing
argument-hint: ""
---

# /klause-open-pr

Run pre-flight checks, open a pull request, and transition the ticket to Testing.

## Precondition

The ticket must be in **In Progress** or **In Review** kanban state AND the worktree must be in **Processing**.

Check by calling `getProductState`:
- If `state.kanban` is not `"inProgress"` and not `"inReview"` — refuse and explain.
- If `state.queue` is not `"processing"` — refuse.

## Behavior

1. **Report progress.** Call `reportProgress(issueLinearId, "klause-open-pr — running pre-flight checks")`.

2. **Check for code changes.** Call `reportActivity("klause-open-pr — checking for commits on this branch")`. Run `git log origin/main..HEAD --oneline` to see if there are any commits on this branch.

   **If no commits exist** (empty branch — typical for audit/research tickets):
   - Tell the user: "No code changes on this branch — completing without PR."
   - Call `transition(command: "complete")` to go directly from In Progress to Completed.
   - Report: "Ticket completed without PR. Run `/klause-next` (or `/klause-push`) to free the processing slot."
   - **Stop here.** Do not proceed to step 3.

3. **Run pre-flight checks.** Call `reportActivity("klause-open-pr — running make format && make lint")` before the heavy work. Invoke `/open-pr` which handles the full lifecycle:
   - Detects quality tools from CLAUDE.md / Makefile (format, lint)
   - Runs formatter (`make format`)
   - Runs linter (`make lint --strict`)
   - Builds the project if a build command is detected
   - Commits any uncommitted changes
   - Rebases on the target branch
   - Pushes and creates the PR via `gh pr create`

   The `/open-pr` skill already reads CLAUDE.md to discover project-specific commands. Let it handle the details.

4. **If pre-flight or PR creation fails:** report the errors to the user. Do NOT transition. The ticket stays in its current state so the user can fix the issues and retry.

5. **On successful PR creation:** call `transition(command: "openPR")` to advance the product state to Testing. This validates the transition and updates the Linear issue status.

6. **Report completion.** Confirm:
   - The PR URL
   - That the ticket has been moved to Testing
   - The user can now run `/klause-babysit` to wait for CI and merge

## Error handling

- If `/open-pr` fails (lint errors, build failures) — do not transition. Report the errors.
- If `transition("openPR")` fails after PR creation — report the error but note the PR was created successfully. The user may need to transition manually.
