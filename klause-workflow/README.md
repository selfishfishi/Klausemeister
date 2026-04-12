# klause-workflow

A Claude Code plugin loaded by the **meister Claude Code** in every Klausemeister session. It provides:

- An MCP client wired to the local Klausemeister MCP server via a stdio shim (`klause-mcp-shim`) bridging to a Unix socket hosted by Klausemeister
- Slash commands: `/klause-define`, `/klause-pull`, `/klause-execute`, `/klause-review`, `/klause-open-pr`, `/klause-babysit` (implemented), `/klause-verify` (placeholder)
- A meister-loop skill that auto-triggers when the session is a Klausemeister meister (env `KLAUSE_MEISTER=1`)
- An `/open-pr` skill that runs the full PR lifecycle — detect format/lint tools, commit, rebase, push, create PR, poll via `/loop`, merge

The canonical meister-loop instructions live in [`CLAUDE.md`](CLAUDE.md) at the plugin root.

## Status

**Scaffold only.** Slash command bodies are placeholders. The real command designs and the Klausemeister-side MCP server are separate tickets — see [Related tickets](#related-tickets).

## Layout

```
klause-workflow/
├── .claude-plugin/plugin.json      # manifest
├── .mcp.json                       # MCP client config (stdio → klause-mcp-shim)
├── commands/
│   ├── klause-define.md            # Backlog → Todo (KLA-97)
│   ├── klause-execute.md           # Todo → In Progress + feature-dev (KLA-98)
│   ├── klause-pull.md              # Inbox → Processing + branch (KLA-102)
│   ├── klause-babysit.md           # Testing → Done + merge PR (KLA-101)
│   ├── klause-open-pr.md           # (In Progress|In Review) → Testing + PR (KLA-100)
│   ├── klause-review.md            # In Progress → In Review + review (KLA-99)
│   └── klause-verify.md            # placeholder → KLA-77
├── skills/
│   ├── klause-workflow/SKILL.md    # meister-loop autoloader
│   └── open-pr/SKILL.md            # /open-pr full PR lifecycle
├── CLAUDE.md                       # meister loop instructions (source of truth)
└── README.md
```

## Environment contract

The plugin expects these env vars on the meister Claude Code process. Klausemeister sets them when it spawns the meister (see [KLA-74](https://linear.app/selfishfish/issue/KLA-74)):

| Variable | Value | Used by |
|---|---|---|
| `KLAUSE_MEISTER` | `1` | Meister-loop skill (to decide whether to run the loop); shim identity check |
| `KLAUSE_WORKTREE_ID` | worktree ID | Passed to `getNextItem`, `getStatus`; shim routes tool calls to the right queue |

Sessions without `KLAUSE_MEISTER=1` can still install the plugin — the meister-loop skill simply won't fire, and the shim will refuse to connect.

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

## How the meister loop runs

1. Klausemeister spawns the meister Claude Code inside the session's tmux window 0 with `KLAUSE_MEISTER=1` and `KLAUSE_WORKTREE_ID=<id>`.
2. The `klause-workflow` skill loads at session start and directs the session to read `CLAUDE.md`.
3. The loop calls `getNextItem`, dispatches by Linear state, and calls `completeItem` when work is done. See [`CLAUDE.md`](CLAUDE.md) for the full contract.

## Related tickets

- [KLA-70](https://linear.app/selfishfish/issue/KLA-70) — Klausemeister local MCP server
- [KLA-71](https://linear.app/selfishfish/issue/KLA-71) — tmux session lifecycle
- [KLA-72](https://linear.app/selfishfish/issue/KLA-72) — this scaffold
- [KLA-74](https://linear.app/selfishfish/issue/KLA-74) — meister spawn + env vars
- [KLA-75](https://linear.app/selfishfish/issue/KLA-75) — `/klause-define`
- [KLA-76](https://linear.app/selfishfish/issue/KLA-76) — `/klause-review`
- [KLA-77](https://linear.app/selfishfish/issue/KLA-77) — `/klause-verify`
- [KLA-78](https://linear.app/selfishfish/issue/KLA-78) — Sessions sidebar rebuild
- [KLA-80](https://linear.app/selfishfish/issue/KLA-80) — `reportProgress` wired into the UI
