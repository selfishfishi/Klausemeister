# klause-workflow

A Claude Code plugin loaded by the **master Claude Code** in every Klausemeister session. It provides:

- An MCP client wired to the local Klausemeister MCP server via `KLAUSE_MCP_URL`
- Three placeholder slash commands (`/klause-spec`, `/klause-review`, `/klause-verify`) that will become the per-state workhorses
- A master-loop skill that auto-triggers when the session is a Klausemeister master (env `KLAUSE_MASTER=1`)

The canonical master-loop instructions live in [`CLAUDE.md`](CLAUDE.md) at the plugin root.

## Status

**Scaffold only.** Slash command bodies are placeholders. The real command designs and the Klausemeister-side MCP server are separate tickets — see [Related tickets](#related-tickets).

## Layout

```
klause-workflow/
├── .claude-plugin/plugin.json      # manifest
├── .mcp.json                       # MCP client config (reads KLAUSE_MCP_URL)
├── commands/
│   ├── klause-spec.md              # placeholder → KLA-75
│   ├── klause-review.md            # placeholder → KLA-76
│   └── klause-verify.md            # placeholder → KLA-77
├── skills/
│   └── klause-workflow/SKILL.md    # master-loop autoloader
├── CLAUDE.md                       # master loop instructions (source of truth)
└── README.md
```

## Environment contract

The plugin expects these env vars on the master Claude Code process. Klausemeister sets them when it spawns the master (see [KLA-74](https://linear.app/selfishfish/issue/KLA-74)):

| Variable | Value | Used by |
|---|---|---|
| `KLAUSE_MASTER` | `1` | Master-loop skill (to decide whether to run the loop) |
| `KLAUSE_WORKTREE_ID` | worktree ID | Passed to `getNextItem`, `getStatus` |
| `KLAUSE_MCP_URL` | MCP server URL | Interpolated into `.mcp.json` as the `klausemeister` server URL |

Sessions without `KLAUSE_MASTER=1` can still install the plugin — the master-loop skill simply won't fire. If `KLAUSE_MCP_URL` is unset, the MCP client will fail to connect; that's expected for non-master sessions.

## Install

### Dev (symlink)

From inside a clone of the Klausemeister repo:

```bash
mkdir -p ~/.claude/plugins
ln -s "$(pwd)/klause-workflow" ~/.claude/plugins/klause-workflow
```

Then launch Claude Code anywhere. The plugin is picked up at session start.

### Via plugin install (once published)

```bash
claude plugin install klause-workflow
```

Not yet published — this is a placeholder for when the plugin ships.

## How the master loop runs

1. Klausemeister spawns the master Claude Code inside the session's tmux window 0 with `KLAUSE_MASTER=1`, `KLAUSE_WORKTREE_ID=<id>`, `KLAUSE_MCP_URL=<url>`.
2. The `klause-workflow` skill loads at session start and directs the session to read `CLAUDE.md`.
3. The loop calls `getNextItem`, dispatches by Linear state, and calls `completeItem` when work is done. See [`CLAUDE.md`](CLAUDE.md) for the full contract.

## Related tickets

- [KLA-70](https://linear.app/selfishfish/issue/KLA-70) — Klausemeister local MCP server
- [KLA-71](https://linear.app/selfishfish/issue/KLA-71) — tmux session lifecycle
- [KLA-72](https://linear.app/selfishfish/issue/KLA-72) — this scaffold
- [KLA-74](https://linear.app/selfishfish/issue/KLA-74) — master spawn + env vars
- [KLA-75](https://linear.app/selfishfish/issue/KLA-75) — `/klause-spec`
- [KLA-76](https://linear.app/selfishfish/issue/KLA-76) — `/klause-review`
- [KLA-77](https://linear.app/selfishfish/issue/KLA-77) — `/klause-verify`
- [KLA-78](https://linear.app/selfishfish/issue/KLA-78) — Sessions sidebar rebuild
- [KLA-80](https://linear.app/selfishfish/issue/KLA-80) — `reportProgress` wired into the UI
