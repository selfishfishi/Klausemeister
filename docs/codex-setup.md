# Codex meister setup

This is the runbook for using **OpenAI Codex CLI** as your meister agent in
Klausemeister, plus a troubleshooting guide for the failure modes the
multiagent stack (KLA-211–217) can land in.

> Klausemeister supports two meister agents — **Claude Code** (default) and
> **Codex**. The choice is per worktree, with an app-wide default in the
> `Default Agent` menu. Switching does not require any restart-the-shell
> ceremony; pick a different default and the next worktree you create uses
> the new agent.

## Prerequisites

- **Klausemeister built and launched at least once.** First launch is what
  writes `~/.codex/config.toml`, creates the shim symlink at
  `~/.klausemeister/bin/klause-mcp-shim`, and the status-hook symlink at
  `~/.klausemeister/hooks/klause-status-hook.sh`. Without that, none of
  the Codex hooks fire and no MCP tool calls reach the app.
- **Codex CLI installed** (see below).
- **An OpenAI account** to log in to Codex.
- **`jq` on `PATH`.** The shared status-hook script (`klause-workflow/hooks/klause-status-hook.sh`)
  parses Codex's JSON event payloads with `jq` and silently no-ops when
  it's missing — meaning the meister status dot will be stuck on whatever
  the last good state was. `brew install jq`.

## Install Codex

Either route works; `MeisterClient` resolves the binary in this order
(`Klausemeister/Dependencies/MeisterClient.swift:77`):

1. `~/.codex/bin/codex`
2. `~/.local/bin/codex`
3. `/opt/homebrew/bin/codex`
4. `/usr/local/bin/codex`
5. `~/.npm/bin/codex`

```bash
# npm (recommended — Codex's own install path)
npm i -g @openai/codex

# or Homebrew
brew install --cask codex
```

Then log in:

```bash
codex login
```

This opens a browser to authenticate against your OpenAI account and
stores credentials under `~/.codex/`.

## First launch (auto-config)

The first time you launch the Klausemeister app **after** Codex is
installed, `MCPSocketListener.installSidecars()` (called from
`AppFeature`'s startup) writes the following idempotently — re-running
the app produces identical files:

| Path | Owner | Purpose |
|---|---|---|
| `~/.klausemeister/bin/klause-mcp-shim` | symlink → bundled `klause-mcp-shim` | The stdio bridge both Claude and Codex meisters spawn to reach Klausemeister's in-process MCP server. |
| `~/.klausemeister/hooks/klause-status-hook.sh` | symlink → bundled `klause-status-hook.sh` | The status hook script Codex's `[[hooks.X]]` block invokes. |
| `~/.claude/.mcp.json` `mcpServers.klausemeister` | upserted JSON entry | Claude Code MCP registration (untouched on the Codex side). |
| `~/.codex/config.toml` `[mcp_servers.klausemeister]` | upserted TOML table | Codex MCP registration. |
| `~/.codex/config.toml` `# klausemeister-hooks-managed-block` | sentinel-fenced TOML block | The six `[[hooks.X]]` entries that drive the meister status dot on Codex. |

The Codex hooks block is **canonical** and rewritten verbatim on every
launch — anything you author outside the sentinel comments is preserved.
Same for the MCP table: the upsert only touches the
`[mcp_servers.klausemeister]` section.

> **MCP tools change → rebuild + relaunch.** Per [KLA-221](https://linear.app/selfishfish/issue/KLA-221),
> the MCP tool list is introspected via the running app binary. After
> pulling new tools, you must **rebuild Klausemeister and quit/relaunch**
> before Codex (or Claude) sees them. Worktrees with already-spawned
> meisters see the old tool list until the meister itself is restarted.

## Choose Codex as default agent

In the menu bar: **Default Agent → New worktrees use → Codex**. The
choice is persisted under `UserDefaults["defaultMeisterAgent"]` and
applied to any worktree created afterward
(`Klausemeister/Worktrees/WorktreeFeature.swift:1173`). Existing
worktrees keep their original agent — `MeisterAgent` is stored on the
`worktrees` row (migration v16 per KLA-211).

You can also flip the agent on a per-worktree basis from the worktree
detail pane (KLA-217 picker).

## Smoke runbook

Run this end-to-end after any change to KLA-211–217 territory or after
upgrading Codex CLI. The meister cannot run this from inside a tmux pane
— each step is human-in-the-loop on the actual app.

| # | Step | What to verify |
|---|---|---|
| 1 | `codex --version` succeeds in your shell. | The binary resolves in `MeisterClient`'s search path. |
| 2 | Launch Klausemeister. Open Settings → set Default Agent to **Codex**. | The picker shows ✓ next to Codex. |
| 3 | Schedule or pull a Backlog ticket via the swimlane UI. | A new worktree is created; its row shows the **Codex** badge (`Klausemeister/Worktrees/AgentBadge.swift`). |
| 4 | In the host shell, `cat ~/.codex/config.toml`. | `[mcp_servers.klausemeister]` table present with `command = "/bin/sh"` and `args = ["-c", "exec ~/.klausemeister/bin/klause-mcp-shim"]`. The sentinel-fenced hooks block contains six `[[hooks.X]]` entries (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`), each pointing at `~/.klausemeister/hooks/klause-status-hook.sh`. |
| 5 | Look at the worktree row. | Status dot transitions: launching (gray) → idle (green) once the meister settles. |
| 6 | Press the swimlane **Advance** button. | `tmux send-keys` dispatches `/klause-next` (un-namespaced — Codex form, per `MeisterAgent.slashCommandPrefix`). The meister picks it up and runs the appropriate `/klause-*` skill. |
| 7 | Watch the status dot during work. | working (yellow) → blocked (red, on a permission prompt) → working → idle. The `blocked` state on Codex comes from `PermissionRequest`, not `Notification(permission_prompt)` — see KLA-210 research. |
| 8 | Confirm an MCP tool call lands. | The meister's call to `getProductState` (or any tool) returns real state. If it errors with "tool not registered", you skipped the rebuild-relaunch caveat above. |
| 9 | Run `/klause-open-pr` from the meister; let it push and create a PR. | The ticket reaches **Testing**; the PR appears on GitHub. |

If steps 1–9 all pass, the Codex stack is working. File any defects you
hit as **separate follow-up tickets** — keep this smoke ticket
reviewable.

## Troubleshooting

### `codex` binary not found

**Symptom:** worktree created with Codex agent, but the meister never
spawns; `MeisterClient` throws `agentBinaryNotFound(.codex)` with the
message: *"codex binary not found — install with `npm i -g @openai/codex`
or `brew install --cask codex`"*.

**Fix:** install Codex into one of the resolver paths above (KLA-212).
Verify with `which codex` and check that the result is in the search
list. Note that unlike Claude (which falls back to a bare PATH lookup),
Codex requires an absolute path — this is intentional, so a stale shell
PATH cannot silently spawn the wrong binary.

### `~/.codex/config.toml` missing or incomplete

**Symptom:** Codex starts but doesn't see the `klausemeister` MCP
server. Tool calls fail with "no such MCP server" or the meister hangs
trying to reach a server that isn't registered.

**Causes & fixes:**

1. **Klausemeister was never launched after installing Codex.** First
   launch is what writes the config. Quit and relaunch the app.
2. **The app couldn't write to `~/.codex/`.** Check console logs for
   `klausemeister.mcp.listener` warnings ("Failed to register MCP server
   in `~/.codex/config.toml`"). A read-only home or sandbox restriction
   prevents the write.
3. **Hand-edited config conflicts with the upsert.** `MCPSocketListener`
   only rewrites the `[mcp_servers.klausemeister]` block (per the
   upsert helper at `Klausemeister/MCP/MCPSocketListener.swift:459`).
   If you have a malformed `[mcp_servers.X]` table elsewhere that
   confuses Codex's TOML parser, the whole MCP map can fail to load.
   Comment out other tables, relaunch, and add them back one at a time.

### Hooks not firing / status dot stuck

**Symptom:** the meister's status dot never leaves the launching state,
or it sticks on `working` after the meister goes idle.

**Causes & fixes:**

1. **The status-hook symlink is dangling.** `~/.klausemeister/hooks/klause-status-hook.sh`
   should resolve to a script bundled inside `Klausemeister.app/Contents/Resources`.
   `readlink ~/.klausemeister/hooks/klause-status-hook.sh` should print
   the in-bundle path. If it's missing or points at a stale DerivedData
   build, relaunch the app — `installStatusHookSymlink` recreates the
   link unconditionally on every launch.
2. **The `[[hooks.X]]` block is missing or out of sync.**
   `cat ~/.codex/config.toml` and confirm the
   `# klausemeister-hooks-managed-block:begin` … `:end` sentinels enclose
   six `[[hooks.X]]` tables. Relaunching Klausemeister rewrites the block
   from the canonical template at `MCPSocketListener.swift:425`.
3. **`jq` is not on the meister's PATH.** The status hook script
   silently no-ops without `jq` (it must never break the agent). Run
   `which jq` from inside the worktree's tmux window. `brew install jq`
   if missing.
4. **`KLAUSE_WORKTREE_ID` isn't set in the meister's env.** The hook
   script bails immediately when the var is unset, which is correct for
   non-meister Codex sessions but means an incorrectly spawned meister
   produces no status updates. Verify via `tmux show-environment -g` (or
   inside the meister window) that `KLAUSE_WORKTREE_ID` is present.
5. **`~/.klausemeister/status/<id>.json` exists but the dot ignores it.**
   This is a `MeisterStatusClient` consumer-side issue; check the file's
   `state` field directly, then look at the file watcher in
   `Klausemeister/Dependencies/MeisterStatusClient.swift`.

### Skills not discovered

**Symptom:** the meister boots but doesn't know what `/klause-next`
means, or the meister-loop skill doesn't auto-load at session start.

**Causes & fixes:**

1. **Working directory is not under the Klausemeister repo.** Codex
   walks `.agents/skills/` from CWD up to the repo root (per the
   discovery rules verified in KLA-215). If your meister is running in
   a path outside the repo, the symlink-based discovery doesn't apply.
2. **The `.agents/skills` symlink is broken.** `readlink -f .agents/skills`
   should resolve to `klause-workflow/skills`. If it doesn't, you've got
   a broken checkout (the symlink is tracked as git mode `120000`;
   re-checkout the file or `git checkout -- .agents/skills`).
3. **Plugin install is stale.** If you installed via the marketplace
   path (`~/.codex/plugins/cache/klausemeister/klause-workflow/<version>/`),
   updating the repo doesn't update the cached install — re-run
   `codex plugin install` against the bumped version, or rely on the
   `.agents/skills` repo-walk path which is always live.

### Slash command sent but no-op

**Symptom:** pressing the swimlane Advance button visibly types into the
meister's tmux pane, but the meister doesn't react.

**Cause:** the wrong dispatch prefix was sent. Per KLA-216 and
`MeisterAgent.slashCommandPrefix`:

| Agent | Form sent |
|---|---|
| Claude Code | `/klause-workflow:klause-next` |
| Codex | `/klause-next` (un-namespaced — Codex doesn't bundle plugin slash commands) |

**Fix:** confirm `worktree.agent` is `.codex` for the worktree in
question. The dispatch is computed at the call site in
`SwimlaneAdvanceButton.swift:41` and `SwimlaneBarRow.swift:290`. If you
manually overrode the agent post-spawn, the meister itself may still be
the wrong binary — destroy and recreate the worktree.

### MCP tool list out of date

**Symptom:** the meister tries to call a tool that landed in a recent
Klausemeister change, but Codex reports "no such tool".

**Cause:** Per [KLA-221](https://linear.app/selfishfish/issue/KLA-221),
the MCP tool list is introspected via the running app binary at
session-start. The meister sees whatever tool set the app's
`MCPSocketListener` advertises **at the moment the meister connected**.

**Fix:** rebuild Klausemeister with the new tools, fully quit and
relaunch the app, then restart the affected meister. Worktrees that
already had a meister running before the rebuild see the old tool list
until their meister reconnects.

## Regression check (Claude side)

Before declaring a Codex change shipped, sanity-check that nothing in
KLA-211–217 broke the Claude path. Quick version:

1. Switch Default Agent back to **Claude Code**.
2. Create a fresh worktree from a Backlog ticket. Confirm the row shows
   the **Claude** badge.
3. Verify `~/.claude/.mcp.json` still has the `klausemeister` server.
4. Press Advance. The meister dispatches `/klause-workflow:klause-next`
   (namespaced form), runs a `/klause-*` skill, and the status dot
   behaves as before.
5. Open a PR via `/klause-open-pr`. Confirm it reaches Testing.

If any of those fail, file a regression ticket — don't fix under the
smoke-test ticket.

## Reference: file layout

What landed for the multiagent project, by ticket:

| Ticket | Touchpoint |
|---|---|
| KLA-211 | `Klausemeister/Worktrees/MeisterAgent.swift` (the enum); `Worktree.agent` column (migration v16). |
| KLA-212 | `Klausemeister/Dependencies/MeisterClient.swift` — Codex binary resolver + `--full-auto` spawn. |
| KLA-213 | `Klausemeister/MCP/MCPSocketListener.swift` `registerCodexMCPServer()` — `~/.codex/config.toml` `[mcp_servers.klausemeister]` upsert. |
| KLA-214 | `Klausemeister/MCP/MCPSocketListener.swift` `registerCodexHooks()` + the canonical `[[hooks.X]]` block; shared `klause-workflow/hooks/klause-status-hook.sh` extended with the `PermissionRequest` event. |
| KLA-215 | `klause-workflow/.codex-plugin/plugin.json`, `klause-workflow/AGENTS.md` symlink → `CLAUDE.md`, `.agents/skills` symlink, `.agents/plugins/marketplace.json`. |
| KLA-216 | `Klausemeister/Worktrees/MeisterAgent.swift` `slashCommandPrefix`; call sites at `SwimlaneAdvanceButton.swift:41` and `SwimlaneBarRow.swift:290`. |
| KLA-217 | `Klausemeister/Dependencies/MeisterStatusClient.swift` (renamed); the Default Agent menu in `KlausemeisterApp.swift:138`; the `Klausemeister/Worktrees/AgentBadge.swift` row badge. |
