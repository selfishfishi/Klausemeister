---
description: Wait for PR CI checks to pass, then merge and transition to Done
argument-hint: ""
---

# /klause-babysit

Wait for a PR to become mergeable, merge it, and transition the ticket to Done (Completed).

## Precondition

The ticket must be in **Testing** kanban state, the worktree must be in **Processing**, and a **PR must exist** on the current branch.

Check by calling `getProductState`:
- If `state.kanban` is not `"testing"` — refuse and explain.
- If `state.queue` is not `"processing"` — refuse.

Then verify a PR exists:
```bash
gh pr view --json number,state 2>/dev/null
```
- If no PR exists or the PR is not `OPEN` — refuse and tell the user to run `/klause-open-pr` first.

## Behavior

1. **Ask the user.** Prompt: "Do you want to skip CI checks and merge immediately, or wait for checks to pass?"

2. **If skip (immediate merge):**
   a. Merge the PR: `gh pr merge --squash --delete-branch`
   b. Call `transition(command: "babysit")` to advance Testing → Completed and update Linear.
   c. Report completion: PR merged, ticket moved to Done.

3. **If babysit (wait for CI):**
   a. Call `reportProgress(issueLinearId, "klause-babysit — waiting for CI checks")`.
   b. Poll CI status using `/loop`:
      - Check `gh pr checks` for all checks passing
      - Check `gh pr view --json mergeable` for mergeability
      - When all checks pass and PR is mergeable, notify the user: "PR is ready to merge."
   c. Ask the user for final confirmation to merge.
   d. Merge the PR: `gh pr merge --squash --delete-branch`
   e. Call `transition(command: "babysit")` to advance Testing → Completed and update Linear.
   f. Report completion.

## Error handling

- If `gh pr merge` fails — report the error (merge conflicts, required reviews, etc.). Do not transition.
- If `transition("babysit")` fails after merge — report the error but note the PR was merged successfully.
- If CI checks fail — report which checks failed and ask the user what to do (fix and retry, or force merge).
