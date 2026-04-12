---
description: Turn a Backlog ticket into a well-defined Todo
argument-hint: [linear-ticket-id]
---

# /klause-define

Define a Backlog ticket so it is ready for implementation, then transition it to Todo.

## Precondition

The ticket must be in **Backlog** kanban state. If not, refuse with a clear message explaining which state the ticket is in and that `/klause-define` only operates on Backlog items.

Check the current state by calling `getProductState`. If `state.kanban` is not `"backlog"`, stop.

## Behavior

1. **Read the ticket.** Fetch the Linear issue details (title, description, labels, project).

2. **Assess whether it is already well-defined.** A ticket is well-defined when it has:
   - A clear problem statement or goal
   - Acceptance criteria or scope boundaries
   - Enough context to start implementation without guessing

3. **If already well-defined:** skip the define step and go straight to the transition (step 5).

4. **If it needs definition:**
   - Explore the codebase for relevant context
   - Ask the user clarifying questions — do not guess
   - Update the Linear ticket description with: requirements, scope, design notes, references
   - May suggest spinning out sub-tickets if the work is too large
   - Call `reportProgress(issueLinearId, "klause-define — <current step>")` during each sub-step

5. **Transition to Todo.** Call `transition(command: "define")` to advance the product state from Backlog to Todo. This validates the transition and updates Linear.

6. **Report completion.** Confirm to the user that the ticket has been moved to Todo.

## Error handling

- If `getProductState` returns `{"state": null}` — no items in queue. Tell the user.
- If `transition("define")` returns an error — the state machine rejected the transition. Report the error message (it includes valid commands).
