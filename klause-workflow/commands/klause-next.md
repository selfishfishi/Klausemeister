---
description: Advance the workflow — reads current state and invokes the next command
argument-hint: ""
---

# /klause-next

Meta-dispatcher that reads the current product state and automatically invokes the next command in the workflow.

## Behavior

1. **Read state.** Call `getProductState` to get the current product state.

2. **Handle edge cases:**
   - If `state` is `null` — no items in the queue. Tell the user the inbox is empty.
   - If `state.isComplete` is `true` — the item is done (Completed + Outbox). Tell the user.
   - If `state.nextCommand` is `null` — the state is unrecognized. Report the current state (`state.kanban`, `state.queue`) and suggest manual action.

3. **Map and invoke.** Read `state.nextCommand` and invoke the corresponding command:

   | `nextCommand` | Invokes |
   |---|---|
   | `"pull"` | `/klause-pull` |
   | `"define"` | `/klause-define` |
   | `"execute"` | `/klause-execute` |
   | `"openPR"` | `/klause-open-pr` |
   | `"babysit"` | `/klause-babysit` |
   | `"push"` | `/klause-push` |

   Note: `"review"` never appears in `nextCommand` — it is manual-only via `/klause-review`.

4. **Report.** Before invoking, tell the user what you're about to do: "Current state: (kanban, queue). Running /klause-<command>..."

## No precondition

`/klause-next` works from any state — it delegates precondition checks to the invoked command. If the command rejects (e.g. state mismatch), the error propagates naturally.

## Repeated invocation

The user can call `/klause-next` repeatedly to step through the entire workflow:
```
/klause-next  → pull (inbox → processing)
/klause-next  → define (backlog → todo)
/klause-next  → execute (todo → in progress)
/klause-next  → open-pr (in progress → testing, or → done if no code changes)
/klause-next  → babysit (testing → done)
/klause-next  → push (processing → outbox)
/klause-next  → "done — nothing to do"
```

Note: For no-code tickets (audits, research), `/klause-open-pr` detects the empty branch and uses `transition("complete")` to skip directly to done, bypassing testing/babysit. The `/klause-next` flow then goes straight to push.
