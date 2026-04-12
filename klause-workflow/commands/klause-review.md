---
description: Optional code review — prompts before transitioning to In Review
argument-hint: [linear-ticket-id]
---

# /klause-review

Optionally review the current work before opening a PR. This is a manual-only command — `/klause:next` skips it and goes straight to `/klause:open-pr`.

## Precondition

The ticket must be in **In Progress** kanban state AND the worktree must be in **Processing**.

Check by calling `getProductState`:
- If `state.kanban` is not `"inProgress"` — refuse and explain which state the ticket is in.
- If `state.queue` is not `"processing"` — refuse.

## Behavior

1. **Ask the user.** Prompt: "Do you want to run a code review before opening a PR?" Wait for confirmation.

2. **If the user says no:** do nothing. Tell them they can proceed with `/klause:open-pr` directly.

3. **If the user says yes:**

   a. **Transition to In Review.** Call `transition(command: "review")`. This validates the state machine and updates the Linear issue status.

   b. **Report progress.** Call `reportProgress(issueLinearId, "klause-review — reviewing branch diff")`.

   c. **Run the review.** Invoke `/pr-review-toolkit:review-pr` to review the diff between the current branch and main. If the skill is not available, perform the review directly:
      - Read the diff (`git diff main...HEAD`)
      - Check for bugs, logic errors, convention violations
      - Report findings to the user

   d. **Report completion.** Summarize the review findings. The ticket stays in **In Review** — the user makes any fixes manually, then proceeds to `/klause:open-pr`.

## Error handling

- If `transition("review")` fails — report the error message (includes valid commands for the current state).
- If `/pr-review-toolkit:review-pr` is not available — fall back to a direct diff review.
