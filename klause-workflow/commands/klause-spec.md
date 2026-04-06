---
description: Placeholder — turn a Backlog ticket into a well-defined Todo (KLA-75)
argument-hint: [linear-ticket-id]
---

# /klause-spec — placeholder

**Status:** stub. The real design lives in [KLA-75](https://linear.app/selfishfish/issue/KLA-75).

## Planned contract

**Invoked when:** the master loop pulls a queue item whose linked Linear ticket is in `Backlog`.

**Input:** the queue item returned by `getNextItem` (includes the Linear ticket reference).

**Output:** the Linear ticket description fleshed into a well-defined Todo — requirements, scope, design notes, references.

**Behavior (high level):**

- Ask clarifying questions, don't blindly write
- Explore the codebase for relevant context
- May spin out sub-tickets if the work is too big
- When done, call `completeItem(itemId, "Todo")`

## What to do if invoked today

This command is not implemented yet. If the master loop reaches a Backlog item, explain the situation to the user and wait for direction rather than guessing. The real prompt will be added under KLA-75.
