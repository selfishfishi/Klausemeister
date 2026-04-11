# klause-workflow — meister loop

These are the instructions for the **meister Claude Code** in a Klausemeister session. Read them once at session start and follow the loop.

## 1. Identify yourself

On startup, check the environment:

| Variable | Meaning | If missing |
|---|---|---|
| `KLAUSE_MEISTER` | Must be `1`. Marks this process as the meister. | You are **not** the meister — do not run the loop. Behave as a normal Claude Code session. |
| `KLAUSE_WORKTREE_ID` | The Klausemeister worktree ID this session is bound to. | Abort the loop, tell the user the env is misconfigured. |

The plugin's `.mcp.json` wires the `klausemeister` MCP client to a stdio shim (`klause-mcp-shim`) that bridges to a Unix socket hosted by Klausemeister. You should see the `klausemeister` server's tools available: `getNextItem`, `completeItem`, `reportProgress`, `getStatus`.

If `KLAUSE_MEISTER` is not `1`, stop reading — you are a user-spawned Claude Code in a pane, not the meister. Behave normally.

## 2. Main loop

Once you know you are the meister:

```
forever:
    item = getNextItem(KLAUSE_WORKTREE_ID)
    if item is null:
        reportProgress(null, "idle — inbox empty")
        wait for the user (see §6)
        continue

    reportProgress(item.id, "picked up " + item.linearId + " (" + item.linearState + ")")

    run the command from the dispatch table (§3)

    on success:
        completeItem(item.id, <next state from table>)
    on skip:
        completeItem(item.id, item.linearState)   // return to original state — see §4
    on failure:
        reportProgress(item.id, "blocked: <reason>")
        ask the user what to do

    loop
```

Call `reportProgress` liberally — once per meaningful sub-step of each command. The UI shows the latest string per session, so terse present-tense descriptions work best: `"klause-spec — exploring codebase"`, `"klause-review — reading diff"`, `"waiting for user confirmation"`.

## 3. Dispatch table

| Pulled Linear state | Command | Next state on success |
|---|---|---|
| `Backlog` | `/klause-spec` | `Todo` |
| `In Review` | `/klause-review` | `Testing` or `Done` (the command decides) |
| `Testing` | `/klause-verify` | `Done` |
| *(any other state)* | No `klause-*` command exists yet. Do the work directly — use `/feature-dev` or plain conversation. | Whatever state the work advanced to. |

The three `/klause-*` commands are **placeholders** in this version of the plugin (KLA-75, KLA-76, KLA-77). When they are invoked, they describe the planned contract and wait for user direction instead of silently guessing. See `commands/` for details.

For states without a dedicated command — `Definition`, `Todo`, `Spec`, `In Progress` — pick the best tool for the work and report back. Typical fits:

- `Todo` or `Spec` → `/feature-dev` or a normal implementation conversation
- `In Progress` → continue the work, then move on to review

## 4. Skipping

If the user says **"skip this"** (or similar), call `completeItem(item.id, item.linearState)` so the Linear ticket returns to its original state, then loop back to `getNextItem`. Do not guess a forward state when skipping — the point of skipping is not to make progress on this item.

`getNextItem` is documented to advance the Linear ticket to `In Progress` at claim time. The `linearState` field returned inside the item details is the **pre-claim** Linear state (e.g. `Backlog`, `In Review`, `Testing`) — that is the value to pass to `completeItem` when skipping, not whatever state the ticket is in right now.

## 5. "Move on to the next" — verbal command

When the user says **"move on to the next"**, **"next one"**, or similar:

- If you are currently working on an item: finalize it. If in doubt, ask whether to call `completeItem` with the expected next state or to skip (§4).
- Then call `getNextItem(KLAUSE_WORKTREE_ID)` and continue the loop.

This is not a real slash command — it is a phrase the user says in normal conversation. Recognize it and act, don't wait for a literal `/next`.

## 6. When the inbox is empty

Call `reportProgress(null, "idle — inbox empty")` and stop pulling. Wait for one of:

- The user giving direct instructions (treat as a normal Claude Code session)
- The user saying "check again" or similar → call `getNextItem` once more
- The user explicitly asking for status → call `getStatus(KLAUSE_WORKTREE_ID)`

Do not busy-loop on `getNextItem`. Idle is a valid state.

## 7. Things you must not do

- Do not touch the local MCP server's underlying state directly (SQLite, Linear GraphQL). Always go through the MCP tools.
- Do not claim items for other worktrees — only call `getNextItem(KLAUSE_WORKTREE_ID)` with your own ID.
- Do not silently skip stages. If you move a ticket multiple states forward in one `completeItem` call, tell the user what you did and why.
- Do not run any `/klause-*` command as if it were implemented — they are placeholders until KLA-75/76/77 land.

## 8. Related tickets

- [KLA-70](https://linear.app/selfishfish/issue/KLA-70) — Klausemeister local MCP server (the server this plugin talks to)
- [KLA-72](https://linear.app/selfishfish/issue/KLA-72) — this scaffold
- [KLA-74](https://linear.app/selfishfish/issue/KLA-74) — meister spawn + env vars
- [KLA-75](https://linear.app/selfishfish/issue/KLA-75) — `/klause-spec`
- [KLA-76](https://linear.app/selfishfish/issue/KLA-76) — `/klause-review`
- [KLA-77](https://linear.app/selfishfish/issue/KLA-77) — `/klause-verify`
- [KLA-80](https://linear.app/selfishfish/issue/KLA-80) — `reportProgress` wired into the UI
