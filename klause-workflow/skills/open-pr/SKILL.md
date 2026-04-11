---
name: open-pr
description: Use when the user wants to open a pull request, submit work for review, merge a branch, or says "open a PR" / "submit this" / "let's merge" / "ship it" / "push this up". Handles the full PR lifecycle automatically — detects and runs project linters and formatters from CLAUDE.md or Makefile, commits changes following project conventions, rebases on the target branch, resolves simple conflicts, pushes with --force-with-lease, creates the PR via gh, then hands off to the /loop skill to poll for mergeability and merge when ready. Always use this skill when the user asks to create a PR for the current branch.
---

# /open-pr

Full-lifecycle PR skill: format, lint, commit, rebase, push, create, poll, merge.

## Usage

```
/open-pr [base-branch]
```

- `[base-branch]` — PR target; defaults to the repo's default branch (detected via `git remote show origin | sed -n 's/.*HEAD branch: //p'`, usually `main`)

## Step 1: Preflight

Figure out the state before doing anything.

```bash
git branch --show-current
```

- If the current branch equals the target branch, stop: "Cannot open a PR from the target branch itself."
- Check `gh auth status`. If not authenticated, stop: "Run `gh auth login` first."

Check whether a PR already exists for this branch:

```bash
gh pr view --json number,title,url,state 2>/dev/null
```

If a PR already exists and is `OPEN`, skip everything up through Step 8 and jump to Step 9 (poll/merge). Tell the user: "PR #N already exists — skipping to merge polling." If the existing PR is `CLOSED` or `MERGED`, stop and tell the user — they probably don't want to clobber it.

## Step 2: Detect quality tools

The user's ask is that the skill find the project's lint/format commands rather than guessing. Two sources, in order:

**2a. `CLAUDE.md`** — Read it and look for explicit instructions like "run `make format && make lint` before committing", or named tools (`swiftformat`, `swiftlint`, `eslint`, `prettier`, `ruff`, `rustfmt`, `cargo clippy`, etc.). CLAUDE.md is the most authoritative source because it captures the project's actual conventions — trust it first.

**2b. `Makefile`** — If CLAUDE.md is silent, check for targets:

```bash
test -f Makefile && grep -E '^(format|lint|check|fmt):' Makefile
```

Store whatever you find. If neither source gives you anything, note "no quality tools detected" and skip Steps 3 and 4. Don't try to auto-detect `package.json` / `pyproject.toml` / etc. — that's out of scope and risks running the wrong tool.

## Step 3: Run the formatter

Run the detected format command (e.g. `make format`). Look for the exit code.

If it fails non-zero, stop and show the user. The usual cause is a missing binary (`swiftformat` not installed, `prettier` not in PATH, etc.). Check CLAUDE.md for an install hint and surface it ("try `brew install swiftformat`").

If the formatter modified files, that's fine — they'll be picked up in Step 5.

## Step 4: Run the linter

Run the detected lint command (e.g. `make lint`).

**If lint fails**, the goal is to fix the violations yourself, not dump them on the user:

1. If you haven't already run the formatter this session, run it now and re-lint. Many lint failures are formatting issues that the formatter can auto-resolve.
2. Read the remaining violations. For each, fix the source file directly — unused imports, missing trailing commas, explicit types, etc. are all routinely resolvable by editing the code.
3. Re-run the linter after fixes.
4. If violations remain after two fix-and-retry cycles, stop and ask the user. Do not push PRs with lint errors — that's explicitly against the project's standards.

## Step 5: Commit

### 5a. Assess what changed

Run these in parallel:

```bash
git status
git diff
git diff --staged
git log --oneline -10
```

If the working tree is clean **and** nothing is staged, skip to Step 6 — nothing to commit.

### 5b. Stage files by name

Stage only the files that belong to this work. Do **not** run `git add -A` or `git add .` — that sweeps in untracked files you didn't intend to commit (scratch notes, local config, accidentally-created files). List the files explicitly:

```bash
git add path/to/file1 path/to/file2
```

Refuse to stage anything that looks like a secret (`.env`, `*.pem`, `credentials.*`, files with "secret" / "token" / "key" in the name). If you see one, flag it to the user and skip it.

### 5c. Draft the commit message

Match the project's existing style — read the recent log and imitate it. In this repo, commits use imperative mood and often include the Linear ticket ID in parens: "Add bottom status bar for sync state and copyable errors (KLA-67)".

Extract a ticket ID from the branch name if one exists. Common patterns: `KLA-72`, `a/kla-67-some-description`, `feature/KLA-123-thing`. The ID should appear in the commit subject.

Keep the message tight: one subject line (imperative, under ~72 chars) plus a short body explaining *why*, not *what*. The diff already shows what.

### 5d. Commit with a HEREDOC

```bash
git commit -m "$(cat <<'EOF'
Subject line goes here

Short body explaining why, if useful.

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

If a pre-commit hook fails, **fix the underlying issue and make a new commit** — don't `--amend` (the commit that failed never happened, so amending would rewrite the previous commit). Don't use `--no-verify` unless the user explicitly asks.

## Step 6: Rebase on target

```bash
git fetch origin <target>
git rebase origin/<target>
```

`<target>` is the arg or the default branch.

**On conflict**:

1. List conflicting files: `git diff --name-only --diff-filter=U`
2. For each file, read it and judge the conflict:
   - **Simple** (non-overlapping hunks, whitespace, clearly mechanical): resolve it, `git add <file>`
   - **Complex** (overlapping logic, semantic ambiguity, renamed APIs): show the conflict markers to the user and ask. Semantic conflicts are where you destroy data if you guess — don't guess.
3. `git rebase --continue` after each resolved file.
4. If the user says abort: `git rebase --abort` and stop.

## Step 7: Push

```bash
git push --force-with-lease origin HEAD
```

`--force-with-lease` is the right choice after a rebase — it overwrites your own rewritten history but refuses to clobber a concurrent push from someone else. Plain `--force` is dangerous; don't use it.

If the branch has no upstream yet (first push), use:

```bash
git push -u origin HEAD
```

If the push fails for any other reason, surface the error and stop.

## Step 8: Create the PR

### 8a. Gather material for title and body

```bash
git log origin/<target>..HEAD --oneline
git diff origin/<target>...HEAD --stat
```

**Title**: Under ~70 chars, imperative mood, include the ticket ID if the branch has one. If the branch has a single commit, the commit subject is usually a good title. If it has many, summarize.

**Body**: Use the project's convention:

```
## Summary
- bullet 1
- bullet 2

## Test plan
- [ ] step 1
- [ ] step 2

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 8b. Create it

```bash
gh pr create --base <target> --title "<title>" --body "$(cat <<'EOF'
## Summary
- ...

## Test plan
- [ ] ...

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Capture the PR number and URL from the output for the next step and the summary.

## Step 9: Poll for mergeability and merge

Hand off to the `/loop` skill to poll every 2 minutes. CI on this project is generally fast; 10 minutes (the `/loop` default) is too slow to feel interactive.

Invoke `/loop` with a self-contained prompt — `/loop` re-runs the prompt from scratch each tick, so it must include the PR number, the check command, the merge command, and the stop conditions:

```
/loop 2m Check PR #<number> mergeability. Run: gh pr view <number> --json mergeable,mergeStateStatus,state. If state is MERGED, stop and report success. If mergeStateStatus is CLEAN, run: gh pr merge <number> --merge, then stop and report the merge. If mergeStateStatus is BLOCKED or BEHIND or DIRTY, report the current status and keep looping. If state is CLOSED (not merged), stop and report. If any check run has conclusion FAILURE or TIMED_OUT, stop and report which checks failed.
```

Once `/loop` is running, the `/open-pr` invocation is done — control has been handed off.

If the user ran `/open-pr` on a branch where they don't want auto-merge, they should say so up front and you should skip Step 9. If they didn't say, proceed.

## Report format

Before handing off to `/loop`, print a compact summary:

```
open-pr summary
───────────────
Format:  ✓ make format
Lint:    ✓ make lint (clean)
Commit:  ✓ abc1234 — <subject>
Rebase:  ✓ on origin/main (clean)
Push:    ✓ origin/<branch> (--force-with-lease)
PR:      ✓ #<number> — <title>
         <url>
Merge:   ⏳ polling via /loop (2m interval)
```

Use `⏭` for skipped steps (`Format: ⏭ no formatter detected`) and `—` for steps that had nothing to do (`Commit: — working tree clean`).

## Notes

- The skill assumes `gh` is installed and authenticated. If not, it stops at Step 1.
- Inside a git worktree, all `git` commands operate on the worktree's HEAD. Never `cd` out to the parent repo — worktree commands land on the wrong working tree.
- If the branch has no commits ahead of the target, stop at Step 1 with "nothing to PR — branch is up to date with <target>".
- This repo uses merge commits (look at `git log --oneline` for "Merge pull request" lines), so `gh pr merge --merge` is the right strategy. If you're in a different project that squash-merges, override by reading the project's convention.
