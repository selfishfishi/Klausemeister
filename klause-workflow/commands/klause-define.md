---
description: Assess a Backlog ticket, define it if needed, label complexity, transition to Todo
argument-hint: [linear-ticket-id]
---

# /klause-define

Assess a Backlog ticket's complexity, apply the appropriate level of definition, stamp a complexity label, and transition to Todo.

## Precondition

The ticket must be in **Backlog** kanban state. If not, refuse with a clear message explaining which state the ticket is in and that `/klause-define` only operates on Backlog items.

Check the current state by calling `getProductState`. If `state.kanban` is not `"backlog"`, stop.

## Behavior

### 1. Read the ticket

Fetch the Linear issue details (title, description, labels, project) using the issue identifier from `getProductState`.

### 2. Assess in one pass

In a single assessment, determine **both**:

**A) Definition depth** — how much effort to spend defining the ticket:

| Tier | Signals | What to do |
|---|---|---|
| **Trivial** | Self-explanatory, tiny scope (typo, rename, config, one-line fix). Description is clear and complete. | Skip definition entirely. |
| **Light** | Clear intent but missing scope bounds or acceptance criteria. Small feature, straightforward bug fix. | Add 2-3 bullet points of scope/acceptance criteria. No codebase exploration. |
| **Standard** | Design choices involved, multi-file change, integration points. Description has gaps or ambiguity. | Explore relevant codebase areas, ask clarifying questions, write requirements and design notes. |
| **Heavy** | Architectural, large, cross-cutting. May be too big for one ticket. | Full codebase exploration, multiple rounds of questions, detailed requirements/constraints/references. May suggest splitting into sub-tickets. |

**B) Complexity label** — which execution strategy `/klause:execute` should use:

| Label | When | Execution strategy |
|---|---|---|
| `simple` | One-file changes, config, typos, renames, clear single-step work | Direct execution — just do it, no planning |
| `medium` | Multi-file but scoped, clear approach, no major design decisions | Enter plan mode first, then execute |
| `complex` | Design choices, architectural, cross-cutting, multiple systems | Run `/feature-dev:feature-dev` for full guided development |

**Decision heuristics:**
1. **Description length and detail** — one-liner with clear intent → trivial/simple; open questions → standard+/medium+
2. **Scope signals** — "refactor", "redesign", "migrate", "replace" → heavier; "fix", "update", "add", "rename" with a specific target → lighter
3. **Existing sub-items** — if acceptance criteria or task lists already present, less definition needed
4. **Codebase touchpoints** — multiple systems or files referenced in the description → heavier complexity

Note: definition depth and complexity usually correlate but aren't identical. "Add dark mode toggle" is light definition (clear what to do) but medium complexity (touches multiple files).

### 3. Apply definition

Based on the assessed tier:
- **Trivial**: skip to step 4.
- **Light**: add 2-3 scope/acceptance bullet points to the Linear ticket description.
- **Standard**: explore the codebase, ask the user clarifying questions, update the description with requirements, scope, and design notes. Call `reportProgress(issueLinearId, "klause-define — <current step>")` during each sub-step.
- **Heavy**: full exploration, multiple rounds of questions, detailed writeup. May suggest spinning out sub-tickets.

### 4. Stamp the complexity label

Apply the assessed complexity label to the Linear issue. Use the Linear MCP to add the label (`simple`, `medium`, or `complex`).

### 5. Transition to Todo

Call `transition(command: "define")` to advance the product state from Backlog to Todo.

### 6. Report completion

Tell the user:
- What definition tier was applied and why
- What complexity label was stamped
- That the ticket is now in Todo

Example: "Assessed as **light** definition (clear intent, just needed scope bounds) and **medium** complexity (touches 3 files). Added acceptance criteria. Labeled `medium` — execute will enter plan mode. Moved to Todo."

## Error handling

- If `getProductState` returns `{"state": null}` — no items in queue. Tell the user.
- If `transition("define")` returns an error — the state machine rejected the transition. Report the error message.
