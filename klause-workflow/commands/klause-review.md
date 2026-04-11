---
description: Placeholder — review a PR for an In Review ticket (KLA-76)
argument-hint: [linear-ticket-id]
---

# /klause-review — placeholder

**Status:** stub. The real design lives in [KLA-76](https://linear.app/selfishfish/issue/KLA-76).

## Planned contract

**Invoked when:** the meister loop pulls a queue item whose linked Linear ticket is in `In Review`.

**Input:** the queue item (Linear ticket reference + PR URL if available).

**Output:** a PR review — comments, approvals, or change requests — plus a Linear state transition to `Testing` or `Done` depending on what's found.

**Behavior (high level):**

- May wrap `pr-review-toolkit:code-reviewer` or do an in-house review
- Reads the diff, checks against the spec, looks for bugs and convention violations
- Posts the review on the PR
- When done, calls `completeItem(itemId, <next-state>)`

## What to do if invoked today

This command is not implemented yet. If the meister loop reaches an In Review item, explain the situation to the user and wait for direction. The real prompt will be added under KLA-76.
