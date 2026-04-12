---
description: Run feature-dev on a Todo ticket, transitioning it to In Progress
argument-hint: [linear-ticket-id]
---

# /klause-execute

Execute work on a Todo ticket by transitioning it to In Progress and invoking `/feature-dev:feature-dev`.

## Precondition

The ticket must be in **Todo** kanban state AND the worktree must be in **Processing** (a branch already exists from `/klause-pull`).

Check by calling `getProductState`:
- If `state` is `null` — no items in queue. Tell the user.
- If `state.kanban` is not `"todo"` — refuse and explain which state the ticket is in.
- If `state.queue` is not `"processing"` — refuse. The user needs to run `/klause-pull` first to create a branch and move the item into processing.

## Behavior

1. **Report progress.** Call `reportProgress(issueLinearId, "klause-execute — transitioning to In Progress")`.

2. **Transition to In Progress.** Call `transition(command: "execute")`. This validates the state machine and updates the Linear issue status.

3. **Invoke feature-dev.** Run `/feature-dev:feature-dev` with the ticket identifier (e.g. `KLA-98`) as the argument. This skill handles the full feature development lifecycle:
   - Codebase exploration
   - Clarifying questions
   - Architecture design
   - Implementation
   - Quality review

4. **Report completion.** After feature-dev finishes, confirm to the user that the ticket is now In Progress and the work is done.

## Error handling

- If `transition("execute")` fails — report the error. The message includes valid commands for the current state.
- If `/feature-dev:feature-dev` is not available — tell the user to install the `feature-dev` plugin: `claude plugin install feature-dev`.
