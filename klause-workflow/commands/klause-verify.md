---
description: Placeholder — execute the verification plan for a Testing ticket (KLA-77)
argument-hint: [linear-ticket-id]
---

# /klause-verify — placeholder

**Status:** stub. The real design lives in [KLA-77](https://linear.app/selfishfish/issue/KLA-77).

## Planned contract

**Invoked when:** the meister loop pulls a queue item whose linked Linear ticket is in `Testing`.

**Input:** the queue item, plus any verification plan attached to the ticket from earlier stages.

**Output:** verification results and, on pass, a transition to `Done`.

**Behavior (high level):**

- Often skipped — manual verification is fine
- When run, executes the verification plan (manual + automated checks)
- Reports results back to the user
- On pass, calls `completeItem(itemId, "Done")`

## What to do if invoked today

This command is not implemented yet. If the meister loop reaches a Testing item, explain the situation to the user and wait for direction. The real prompt will be added under KLA-77.
