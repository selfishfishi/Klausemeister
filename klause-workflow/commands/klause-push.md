---
description: Move a completed item from processing to the outbox
argument-hint: ""
---

# /klause-push

Move the completed item from the processing slot to the outbox, freeing the slot for the next `/klause-pull`.

## Precondition

The ticket must be in **Completed** (Done) kanban state AND the worktree must be in **Processing**.

Check by calling `getProductState`:
- If `state` is `null` — no items in queue. Tell the user.
- If `state.kanban` is not `"completed"` — refuse and explain. The ticket must be Done before it can be pushed to outbox.
- If `state.queue` is not `"processing"` — refuse.

## Behavior

1. **Report progress.** Call `reportProgress(issueLinearId, "klause-push — moving to outbox")`.

2. **Transition.** Call `transition(command: "push")`. This validates the state machine and moves the item from Processing → Outbox.

3. **Report completion.** Confirm to the user:
   - Which item was pushed (identifier + title)
   - The processing slot is now free
   - They can run `/klause-pull` to pick up the next inbox item

## Error handling

- If `transition("push")` fails — report the error. The message includes which commands are valid from the current state.
