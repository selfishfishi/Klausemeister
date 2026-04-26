# klause-workflow

A workflow plugin loaded by the **meister agent** (Claude Code or Codex) in every Klausemeister session. It provides:

- An MCP client wired to the local Klausemeister MCP server via a stdio shim (`klause-mcp-shim`) bridging to a Unix socket hosted by Klausemeister
- Slash commands: `/klause-next` (meta-dispatcher), `/klause-define`, `/klause-pull`, `/klause-execute`, `/klause-review`, `/klause-open-pr`, `/klause-babysit`, `/klause-push` (implemented), `/klause-verify` (placeholder)
- A meister-loop skill that auto-triggers when the session is a Klausemeister meister (env `KLAUSE_MEISTER=1`)
- An `/open-pr` skill that runs the full PR lifecycle — detect format/lint tools, commit, rebase, push, create PR, poll via `/loop`, merge

The canonical meister-loop instructions live in [`CLAUDE.md`](CLAUDE.md) at the plugin root. `AGENTS.md` is a symlink to the same file so Codex meisters read the identical instructions — single source of truth, no drift.

## Status

**Scaffold only.** Slash command bodies are placeholders. The real command designs and the Klausemeister-side MCP server are separate tickets — see [Related tickets](#related-tickets).

## Layout

```
klause-workflow/
├── .claude-plugin/plugin.json      # Claude plugin manifest
├── .codex-plugin/plugin.json       # Codex plugin manifest
├── .mcp.json                       # MCP client config (stdio → klause-mcp-shim) — shared
├── commands/                       # Claude slash commands (Codex dispatch is KLA-216)
│   ├── klause-define.md            # Backlog → Todo (KLA-97)
│   ├── klause-execute.md           # Todo → In Progress + feature-dev (KLA-98)
│   ├── klause-next.md              # Meta-dispatcher — invokes next command (KLA-104)
│   ├── klause-pull.md              # Inbox → Processing + branch (KLA-102)
│   ├── klause-babysit.md           # Testing → Done + merge PR (KLA-101)
│   ├── klause-open-pr.md           # (In Progress|In Review) → Testing + PR (KLA-100)
│   ├── klause-push.md              # Completed/Processing → Completed/Outbox (KLA-103)
│   ├── klause-review.md            # In Progress → In Review + review (KLA-99)
│   └── klause-verify.md            # placeholder → KLA-77
├── hooks/                          # Claude hooks (Codex hook install is KLA-217)
├── skills/                         # discovered by Claude (via plugin) and Codex (via plugin or .agents/skills/ symlink)
│   ├── klause-workflow/SKILL.md    # meister-loop autoloader
│   ├── open-pr/SKILL.md            # /open-pr full PR lifecycle
│   └── schedule/SKILL.md
├── CLAUDE.md                       # meister loop instructions (source of truth)
├── AGENTS.md                       # symlink → CLAUDE.md (Codex reads this)
└── README.md
```

At the repo root, two cross-agent paths point back into this plugin:

```
.agents/skills        # symlink → klause-workflow/skills (Codex repo-scope discovery)
.agents/plugins/marketplace.json   # Codex marketplace entry for klause-workflow
.claude-plugin/marketplace.json    # Claude marketplace entry for klause-workflow
```

## Environment contract

The plugin expects these env vars on the meister Claude Code process. Klausemeister sets them when it spawns the meister (see [KLA-74](https://linear.app/selfishfish/issue/KLA-74)):

| Variable | Value | Used by |
|---|---|---|
| `KLAUSE_MEISTER` | `1` | Meister-loop skill (to decide whether to run the loop); shim identity check |
| `KLAUSE_WORKTREE_ID` | worktree ID | Passed to `getNextItem`, `getStatus`; shim routes tool calls to the right queue |

Sessions without `KLAUSE_MEISTER=1` can still install the plugin — the meister-loop skill simply won't fire, and the shim will refuse to connect.

## Install

### Claude Code

**Dev (symlink):** From inside a clone of the Klausemeister repo:

```bash
mkdir -p ~/.claude/plugins
ln -s "$(pwd)/klause-workflow" ~/.claude/plugins/klause-workflow
```

Then launch Claude Code anywhere. The plugin is picked up at session start.

**Via marketplace:** Already wired — the repo-root `.claude-plugin/marketplace.json` registers `klause-workflow`. Open a Claude Code session in the repo and the plugin loads automatically.

### Codex

**Dev (symlink):** From inside a clone of the Klausemeister repo:

```bash
mkdir -p ~/.agents/skills
ln -s "$(pwd)/klause-workflow/skills/klause-workflow" ~/.agents/skills/klause-workflow
ln -s "$(pwd)/klause-workflow/skills/open-pr"        ~/.agents/skills/open-pr
ln -s "$(pwd)/klause-workflow/skills/schedule"       ~/.agents/skills/schedule
```

Codex picks them up automatically (no restart needed for skill discovery).

**Via marketplace:** The repo-root `.agents/plugins/marketplace.json` registers `klause-workflow` for Codex. Open a Codex session in the repo and the plugin is available for install.

**In-repo (no install):** When you launch Codex inside the Klausemeister repo, it walks `.agents/skills/` from your CWD up to the repo root and finds the symlink at `<repo>/.agents/skills` → `klause-workflow/skills/`. Skills are visible without any user-scope install.

## How the meister loop runs

1. Klausemeister spawns the meister agent (Claude Code or Codex) inside the session's tmux window 0 with `KLAUSE_MEISTER=1` and `KLAUSE_WORKTREE_ID=<id>`.
2. The `klause-workflow` skill loads at session start and directs the session to read `CLAUDE.md` (or `AGENTS.md`, which is a symlink to the same file).
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
