---
description: Pull the next inbox item into processing and create a branch
argument-hint: ""
---

# /klause-pull

Pull the next item from the worktree inbox into the processing slot and create a fresh git branch for the work.

## Precondition

The **processing slot must be empty** and there must be at least one item in the **inbox**.

Check by calling `getProductState`:
- If `state` is `null` — no items at all. Tell the user.
- If `state.queue` is `"processing"` — an item is already being worked on. Refuse and tell the user which item is in processing (`state.identifier`, `state.title`).
- If `state.queue` is `"inbox"` — proceed.

## Behavior

1. **Read the item.** The `getProductState` response includes `identifier` (e.g. `"KLA-102"`), `title`, and `issueLinearId`.

2. **Check blockers.** Call Linear's `get_issue` with `id: <identifier>` and `includeRelations: true`. Inspect `relations.blockedBy`:
   - If the list is empty, proceed.
   - If any blocker's `statusType` is not `completed` or `canceled` (i.e. it's still open), **refuse the pull**. Report to the user:
     > `<identifier>` is blocked by `<blocker1-id>` (`<blocker1-title>`), `<blocker2-id>` … which are not done yet. Not pulling. Unblock the dependency, or skip this ticket (use `completeItem(item.id, item.linearState)` per the meister loop §4) and let `/klause-next` try the next inbox item.

     Then stop. Do not `reportProgress`, do not `transition`, do not create a branch. The ticket stays in the inbox.

     This check protects against the historical failure mode where a scheduled ticket with an unmet Linear `blockedBy` was pulled into processing and silently marched through the state machine without actual work (see KLA-198 incident, 2026-04-18).

3. **Report progress.** Call `reportProgress(issueLinearId, "klause-pull — moving to processing")`.

4. **Transition.** Call `transition(command: "pull")`. This validates the state machine and moves the item from Inbox → Processing.

5. **Create a git branch.** Run these shell commands:
   ```bash
   git fetch origin main
   git checkout -b a/<identifier-slug> origin/main
   ```
   Where `<identifier-slug>` is derived from the ticket:
   - Lowercase the identifier: `KLA-102` → `kla-102`
   - Slugify the title: take the first ~5 words, lowercase, replace non-alphanumeric characters with hyphens, trim trailing hyphens
   - Combine: `a/kla-102-pull-item-from-inbox`

6. **Report completion.** Confirm to the user:
   - Which item was pulled (identifier + title)
   - The branch name that was created
   - That the item is now in processing

## Error handling

- If the blocker check refuses the pull — see step 2 above. The ticket stays in inbox; no state change.
- If `transition("pull")` fails — report the error. The error message includes which commands are valid from the current state.
- If `git checkout -b` fails (branch already exists) — tell the user and suggest they check out the existing branch or pick a different name.
