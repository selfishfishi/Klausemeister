# klause-workflow — meister loop

These are the instructions for the **meister agent** (Claude Code or Codex) in a Klausemeister session. Read them once at session start and follow the loop.

> Codex sessions read this file as `AGENTS.md` (a symlink to `CLAUDE.md`). Both filenames resolve to the same content — single source of truth.

## 1. Identify yourself

On startup, check the environment:

| Variable | Meaning | If missing |
|---|---|---|
| `KLAUSE_MEISTER` | Must be `1`. Marks this process as the meister. | You are **not** the meister — do not run the loop. Behave as a normal Claude Code session. |
| `KLAUSE_WORKTREE_ID` | The Klausemeister worktree ID this session is bound to. | Abort the loop, tell the user the env is misconfigured. |

The plugin's `.mcp.json` wires the `klausemeister` MCP client to a stdio shim (`klause-mcp-shim`) that bridges to a Unix socket hosted by Klausemeister. You should see the `klausemeister` server's tools available: `getNextItem`, `completeItem`, `reportProgress`, `reportActivity`, `getStatus`.

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

### 2.1 `reportProgress` — step boundaries

Call `reportProgress` at **ceremonial moments**: pickup, command transition, block, completion. This text persists for minutes and serves as the long-lived "what ticket is this session on" label in Klausemeister's UI (swimlane header, processing card). Terse present-tense descriptions: `"klause-define — exploring codebase"`, `"klause-review — reading diff"`, `"waiting for user confirmation"`.

### 2.2 `reportActivity` — live narration

Call `reportActivity` **densely**, in recap style, so the sidebar ticker reads like a live feed of what you're doing right now. No `issueLinearId` — activity is session-scoped, not ticket-scoped, so it's appropriate even while idle or between tickets. The UI shows the last `reportActivity` as a scrolling ticker for ~30 seconds, then falls back to the static status label; a stale activity line does not linger.

Emit one:

- **Before any tool call expected to take more than a few seconds** (bash commands, big reads, builds, test runs).
- **Whenever your focus shifts** — new file, new subtask, new question, new search.
- **In recap shape when helpful**: `"goal: fix KLA-XXX · just read WorktreeFeature.swift · next: trace reducer"`.
- **During idle waits**: `"idle — waiting for user feedback on KLA-XXX"`.

Good examples:

```
reportActivity("reading SidebarView.swift")
reportActivity("running xcodebuild (~45s)")
reportActivity("parsing 23 grep matches for reportProgress")
reportActivity("summarizing diff before opening PR")
reportActivity("goal: review KLA-140 · just opened PR · next: wait for CI")
```

Avoid empty filler (`"thinking…"`, `"working…"`) — if there's nothing concrete to say, don't call it. The ticker going quiet is a valid signal: the dot stays green, the static label takes over.

### 2.3 `reportActivity("recap: ...")` — session summary

After a `/compact` or whenever the conversation context is summarised, emit a **recap** via `reportActivity` with the literal prefix `recap: `:

```
reportActivity("recap: shipped KLA-134-137, iterated on swimlane polish, fixing marquee ticker")
```

The `recap:` prefix tells Klausemeister to store the text persistently (no 60s TTL) and display it as a sticky headline in the swimlane marquee until the next recap or session disconnect. Keep it to one sentence — it scrolls as a ticker.

## 3. Dispatch table

| Pulled Linear state | Command | Next state on success |
|---|---|---|
| `Backlog` | `/klause-define` | `Todo` |
| `Todo` | `/klause-execute` | `In Progress` |
| `In Progress` | `/klause-open-pr` | `Testing` (or `Done` if no code changes — see below) |
| `In Review` | `/klause-open-pr` | `Testing` (or `Done` if no code changes) |
| `Testing` | `/klause-babysit` | `Done` (Completed) |
| *(any other state)* | No `klause-*` command exists yet. Do the work directly — use `/feature-dev` or plain conversation. | Whatever state the work advanced to. |

All `/klause-*` commands are implemented and use the `getProductState` / `transition` MCP tools for state validation. `/klause-next` is the meta-dispatcher — it reads the current state and invokes the appropriate command automatically. `/klause-review` is manual-only (skipped by `/klause-next`). `/klause-verify` is still a placeholder (KLA-77). See `commands/` for details.

### No-code tickets (audits, research)

When `/klause-open-pr` detects no commits ahead of main (empty branch), it automatically uses `transition("complete")` to go directly from In Progress to Done, bypassing the PR/babysit flow. The meister just runs `/klause-next` as usual — the detection is handled inside the open-pr skill.

For states without a dedicated command — `Definition`, `Spec`, `In Progress` — pick the best tool for the work and report back. Typical fits:

- `Definition` or `Spec` → normal conversation or `/feature-dev`
- `In Progress` → continue the work, then move on to review

## 4. Skipping

If the user says **"skip this"** (or similar), call `completeItem(item.id, item.linearState)` so the Linear ticket returns to its original state, then loop back to `getNextItem`. Do not guess a forward state when skipping — the point of skipping is not to make progress on this item.

`getNextItem` is documented to advance the Linear ticket to `In Progress` at claim time. The `linearState` field returned inside the item details is the **pre-claim** Linear state (e.g. `Backlog`, `In Review`, `Testing`) — that is the value to pass to `completeItem` when skipping, not whatever state the ticket is in right now.

## 5. "Move on to the next" — verbal command

When the user says **"move on to the next"**, **"next one"**, or similar:

- If you are currently working on an item: finalize it. If in doubt, ask whether to call `completeItem` with the expected next state or to skip (§4).
- Then call `getNextItem(KLAUSE_WORKTREE_ID)` and continue the loop.

This is not a real slash command — it is a phrase the user says in normal conversation. Recognize it and act, don't wait for a literal `/next`.

## 6. When the inbox is empty or all-blocked

`getNextItem` distinguishes two idle shapes:

- **Empty** — `{ "item": null }` — nothing is queued.
  → `reportProgress(null, "idle — inbox empty")`
- **All blocked** — `{ "item": null, "reason": "all-blocked", "blockedItems": [{ "issueLinearId": …, "blockedBy": ["KLA-195", …] }, …] }` — at least one inbox item is waiting on a schedule dependency that isn't `done` yet.
  → `reportProgress(null, "idle — waiting on <blocker identifiers>")` — list the union of `blockedBy` identifiers across `blockedItems` (deduped) so the UI shows exactly which upstream work is gating this worktree.

Then stop pulling. Wait for one of:

- The user giving direct instructions (treat as a normal Claude Code session)
- The user saying "check again" or similar → call `getNextItem` once more
- The user explicitly asking for status → call `getStatus(KLAUSE_WORKTREE_ID)`

Do not busy-loop on `getNextItem`. Idle is a valid state. In the all-blocked case, the plan-ahead is that the blocker's worktree will eventually flip its schedule_item to `done`, at which point a fresh `getNextItem` call will succeed.

## 7. Things you must not do

- Do not touch the local MCP server's underlying state directly (SQLite, Linear GraphQL). Always go through the MCP tools.
- Do not claim items for other worktrees — only call `getNextItem(KLAUSE_WORKTREE_ID)` with your own ID.
- Do not silently skip stages. If you move a ticket multiple states forward in one `completeItem` call, tell the user what you did and why.
- Do not run `/klause-verify` as if implemented — it is a placeholder until KLA-77 lands.

## 8. Related tickets

- [KLA-70](https://linear.app/selfishfish/issue/KLA-70) — Klausemeister local MCP server (the server this plugin talks to)
- [KLA-72](https://linear.app/selfishfish/issue/KLA-72) — this scaffold
- [KLA-74](https://linear.app/selfishfish/issue/KLA-74) — meister spawn + env vars
- [KLA-75](https://linear.app/selfishfish/issue/KLA-75) — `/klause-define`
- [KLA-76](https://linear.app/selfishfish/issue/KLA-76) — `/klause-review`
- [KLA-77](https://linear.app/selfishfish/issue/KLA-77) — `/klause-verify`
- [KLA-80](https://linear.app/selfishfish/issue/KLA-80) — `reportProgress` wired into the UI
