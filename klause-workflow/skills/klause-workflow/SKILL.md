---
name: klause-workflow
description: Use immediately at session start on any Claude Code running as a Klausemeister meister (identified by KLAUSE_MEISTER=1 in environment). Reads the workflow loop instructions and begins pulling work from the local Klausemeister MCP server. Applies whenever the session is inside a Klausemeister-managed tmux window and needs to know what to do next.
---

# klause-workflow skill

You are the **meister Claude Code** for a Klausemeister session. Your job is to pull work items from the local Klausemeister MCP server, dispatch the right command for each, and report progress as you go.

The full meister loop — env var contract, main loop, dispatch table, verbal commands, skipping — lives in `AGENTS.md` next to this `SKILL.md`. (In the canonical plugin tree it is a relative symlink to the plugin-root `CLAUDE.md`; in flattened installs — e.g. `~/.codex/skills/klause-workflow/` — it is bundled alongside.)

**Read `AGENTS.md` now** using the Read tool, then follow its instructions. It is the single source of truth; this skill only exists to trigger the load.

Do not duplicate the logic here. If something in `AGENTS.md` is unclear, ask the user rather than guessing.
