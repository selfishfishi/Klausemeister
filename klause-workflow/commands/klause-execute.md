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

Call `reportActivity("klause-execute — reading complexity label")`. Fetch the Linear issue and check its labels for a complexity label (`simple`, `medium`, or `complex`). These are stamped by `/klause-define`.

**If no complexity label is present, refuse by default.** Tickets that entered Todo without passing through `/klause-define` (bug reports, `/klause-schedule` output, manual Linear moves) have historically been silently downgraded to `medium`, bypassing `/feature-dev:feature-dev` for work that needed it.

Print:

> Ticket `<KLA-ID>` has no complexity label. Run `/klause-define` first (preferred — it also assesses definition depth), or re-invoke as `/klause-execute --force-medium` to bypass labeling and run the plan-then-execute strategy anyway.

Then stop. Do not transition, do not begin work.

The `--force-medium` escape hatch is the only supported way to skip labeling. Do not silently default.

### 3. Execute based on complexity

| Label | Strategy |
|---|---|
| `simple` | **Direct execution.** Just do the work — read the ticket, make the changes, commit. No planning phase, no architecture design. Announce: "Simple complexity — executing directly." |
| `medium` | **Plan then execute.** Enter plan mode to design the approach, then implement. Announce: "Medium complexity — planning first." |
| `complex` | **Full guided development.** Invoke `/feature-dev:feature-dev` with the ticket identifier. This handles codebase exploration, clarifying questions, architecture design, implementation, and quality review. Announce: "Complex — running feature-dev." Throughout, narrate densely via `reportActivity` — e.g. `"feature-dev — exploring similar features"`, `"feature-dev — drafting architecture"`, `"feature-dev — implementing state layer"`. |
| *(no label)* | **Refuse.** See step 2. Do not default. |
| `--force-medium` flag | **Plan then execute** (same as `medium`). Announce: "Labeling bypassed via --force-medium — planning first." |

Call `reportProgress` with the routing decision so the Meister UI reflects it, e.g. `reportProgress(issueLinearId, "klause-execute — KLA-200 labeled complex → feature-dev")`.

### 4. Report completion

After execution finishes, confirm to the user that the work is done and the ticket is In Progress.

## Error handling

- If `transition("execute")` fails — report the error. The message includes valid commands for the current state.
- If `/feature-dev:feature-dev` is not available (for complex tickets) — fall back to plan-then-execute and tell the user.
