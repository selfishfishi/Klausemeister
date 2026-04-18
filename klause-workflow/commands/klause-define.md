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

Fetch the Linear issue details (title, description, labels, project, `relations.blockedBy`) using the issue identifier from `getProductState`. Call `get_issue` with `includeRelations: true`.

### 1b. Check blockers

Inspect `relations.blockedBy`:

- If empty, proceed.
- If any blocker's `statusType` is not `completed` or `canceled`, **refuse to define**. Report:
  > `<identifier>` is blocked by `<blocker1-id>` (`<blocker1-title>`), `<blocker2-id>` … which are not done yet. Not defining. Defining a blocked ticket risks burning cycles on a spec whose assumptions change once the blocker lands — pause here, finish the blocker first, or skip this ticket.

  Then stop. Do not assess, do not label, do not transition.

### 2. Assess in one pass

In a single assessment, determine **both**:

**A) Definition depth** — how much effort to spend defining the ticket:

| Tier | Signals | What to do |
|---|---|---|
| **Trivial** | Self-explanatory, tiny scope (typo, rename, config, one-line fix). Description is clear and complete. | Skip definition entirely. |
| **Light** | Clear intent but missing scope bounds or acceptance criteria. Small feature, straightforward bug fix. | Add 2-3 bullet points of scope/acceptance criteria. No codebase exploration. |
| **Standard** | Design choices involved, multi-file change, integration points. Description has gaps or ambiguity. | Explore relevant codebase areas, ask clarifying questions, write requirements and design notes. |
| **Heavy** | Architectural, large, cross-cutting. May be too big for one ticket. | Full codebase exploration, multiple rounds of questions, detailed requirements/constraints/references. May suggest splitting into sub-tickets. |

**B) Complexity label** — which execution strategy `/klause-execute` should use.

**When in doubt, go up one tier.** Under-labeling is the failure mode this rubric is tuned against: `medium` silently bypasses feature-dev for work that needed planning. Over-labeling costs a planning pass on work that didn't need one — cheap by comparison.

**Any one signal in the `complex` list forces `complex`, regardless of file count.**

| Label | Triggers (any one) | Execution strategy |
|---|---|---|
| `simple` | Truly one-file. Mechanical. No design decisions. No new types, no new APIs. Work is "replace X with Y" where Y is obvious from the ticket. | Direct execution — just do it, no planning |
| `medium` | Multi-file but mechanical. Clear approach stated in the ticket. No new dependency client, no new reducer, no new TCA action enum case that crosses features. Presentation-only SwiftUI wiring, straightforward data plumbing. | Enter plan mode first, then execute |
| `complex` | **Any one of:** new or substantially modified dependency client (live + test + schema) · new TCA feature or reducer · cross-feature delegate action · state-machine or workflow change (klause-\*, kanban transitions) · C interop / libghostty callback change · work crossing reducer ↔ dependency ↔ persistence boundaries · unresolved design choice the ticket does not answer · multi-repo or multi-skill change (app + plugin). | Run `/feature-dev:feature-dev` for full guided development |

**Worked examples (real KLA tickets):**

* `simple` — [KLA-181](https://linear.app/selfishfish/issue/KLA-181) "Replace blocking GCD dispatch in SocketTransport": one file, well-known pattern (`readabilityHandler` + `terminationHandler`), no new types.
* `medium` — [KLA-188](https://linear.app/selfishfish/issue/KLA-188) "TicketInspectorView presentation": new SwiftUI file, plain value types + closures, no store, clear spec in the ticket.
* `complex` — [KLA-185](https://linear.app/selfishfish/issue/KLA-185) "Send /klause-workflow commands from Meister UI": new dependency client, reverse channel via tmux, crosses reducer / dependency / subprocess layers, design choices in the ticket body.

**Counter-examples (commonly mis-labeled):**

* [KLA-170](https://linear.app/selfishfish/issue/KLA-170) "Implement /klause-babysit + update workflow skills" looks like a skill edit but added a new command, changed the state machine, and touched no-code-ticket detection — **complex**, not medium.
* [KLA-180](https://linear.app/selfishfish/issue/KLA-180) "Scheduling skill: topo sort + queue assignment" is a new skill with an algorithm and a new MCP tool — **complex**, not medium.

**Decision heuristics for definition depth (orthogonal to complexity):**
1. **Description length and detail** — one-liner with clear intent → trivial/light; open questions → standard+
2. **Scope signals** — "refactor", "redesign", "migrate", "replace" → heavier; "fix", "update", "add", "rename" with a specific target → lighter
3. **Existing sub-items** — if acceptance criteria or task lists already present, less definition needed
4. **Codebase touchpoints** — multiple systems or files referenced → heavier definition

Definition depth and complexity usually correlate but aren't identical. "Add dark mode toggle" is light definition (clear what to do) but medium complexity (touches multiple files).

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
