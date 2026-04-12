---
description: Execute work on a Todo ticket using complexity-appropriate strategy
argument-hint: [linear-ticket-id]
---

# /klause-execute

Execute work on a Todo ticket by transitioning it to In Progress and running the implementation using the strategy determined by the ticket's complexity label.

## Precondition

The ticket must be in **Todo** kanban state AND the worktree must be in **Processing** (a branch already exists from `/klause-pull`).

Check by calling `getProductState`:
- If `state` is `null` — no items in queue. Tell the user.
- If `state.kanban` is not `"todo"` — refuse and explain which state the ticket is in.
- If `state.queue` is not `"processing"` — refuse. The user needs to run `/klause-pull` first.

## Behavior

### 1. Transition to In Progress

Call `reportProgress(issueLinearId, "klause-execute — transitioning to In Progress")`.

Call `transition(command: "execute")`. This validates the state machine and updates the Linear issue status.

### 2. Read the complexity label

Fetch the Linear issue and check its labels for a complexity label (`simple`, `medium`, or `complex`). These are stamped by `/klause-define`.

### 3. Execute based on complexity

| Label | Strategy |
|---|---|
| `simple` | **Direct execution.** Just do the work — read the ticket, make the changes, commit. No planning phase, no architecture design. Announce: "Simple complexity — executing directly." |
| `medium` | **Plan then execute.** Enter plan mode to design the approach, then implement. Announce: "Medium complexity — planning first." |
| `complex` | **Full guided development.** Invoke `/feature-dev:feature-dev` with the ticket identifier. This handles codebase exploration, clarifying questions, architecture design, implementation, and quality review. Announce: "Complex — running feature-dev." |
| *(no label)* | **Default to medium.** If `/klause-define` didn't stamp a label (e.g. older ticket), use the plan-then-execute strategy. Announce: "No complexity label found — defaulting to medium (plan then execute)." |

### 4. Report completion

After execution finishes, confirm to the user that the work is done and the ticket is In Progress.

## Error handling

- If `transition("execute")` fails — report the error. The message includes valid commands for the current state.
- If `/feature-dev:feature-dev` is not available (for complex tickets) — fall back to plan-then-execute and tell the user.
