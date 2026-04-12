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

2. **Report progress.** Call `reportProgress(issueLinearId, "klause-pull — moving to processing")`.

3. **Transition.** Call `transition(command: "pull")`. This validates the state machine and moves the item from Inbox → Processing.

4. **Create a git branch.** Run these shell commands:
   ```bash
   git fetch origin main
   git checkout -b a/<identifier-slug> origin/main
   ```
   Where `<identifier-slug>` is derived from the ticket:
   - Lowercase the identifier: `KLA-102` → `kla-102`
   - Slugify the title: take the first ~5 words, lowercase, replace non-alphanumeric characters with hyphens, trim trailing hyphens
   - Combine: `a/kla-102-pull-item-from-inbox`

5. **Report completion.** Confirm to the user:
   - Which item was pulled (identifier + title)
   - The branch name that was created
   - That the item is now in processing

## Error handling

- If `transition("pull")` fails — report the error. The error message includes which commands are valid from the current state.
- If `git checkout -b` fails (branch already exists) — tell the user and suggest they check out the existing branch or pick a different name.
