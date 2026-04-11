---
name: define
description: Interactive spec definition for Linear tickets. Takes a vague ticket and refines it into a complete, structured specification through targeted questions and iterative drafting.
disable-model-invocation: true
argument-hint: [ticket-id]
---

# /define

Take a Linear ticket and interactively refine it into a complete specification that an agent or engineer can pick up and implement autonomously. You produce the WHAT and WHY — never the HOW.

**Core principle: structure, don't invent.** Your job is to formalize what the human tells you, surface gaps in what they said, and ask about ambiguities. Never propose requirements the human didn't express. Never suggest implementation approaches.

## Phase 1: Fetch

1. Fetch the Linear ticket via MCP: `get_issue` with the ticket identifier from `$ARGUMENTS`
2. Read `CLAUDE.md` to understand project architecture and conventions
3. Fetch ticket comments via `list_comments` — they often contain context the description doesn't

If the ticket has no description (title only), say so and plan for an extended Clarify phase (5-7 questions instead of 3-5). If the Linear MCP is unavailable, ask the user to paste the ticket details manually and skip the Publish phase at the end.

Present a brief summary: ticket title, current status, what the description covers, and what's missing.

## Phase 2: Clarify

Identify the 3-5 most important gaps and ask targeted questions. Do NOT dump a checklist. Ask conversational questions that reveal hidden assumptions.

**Question priority (go deep, not wide):**

1. **Usage context**: "When you imagine someone actually using this, what's the scenario? What just happened before? What do they do after?"
2. **Pain point**: "What's the actual pain point driving this?"
3. **Existing behavior**: "How does the system handle this today? What workarounds exist?"
4. **Boundary probing**: "What's the simplest version that would still be useful? What would make it NOT useful?"
5. **Failure modes**: "What happens when X goes wrong? When Y is empty? When Z is unavailable?"
6. **Exclusions**: "What is this feature NOT? What should an implementing agent explicitly avoid building?"

**When to stop asking:** When answers shift from "oh, I never thought about that" to "yeah, that's for later." Two rounds of questions maximum before drafting. Don't over-interview.

Wait for the user's answers before proceeding.

## Phase 3: Draft and Review

Generate the spec using the template below. Incorporate everything from the ticket description AND the user's answers. Keep it under 150 lines — if it's longer, the scope is too big (suggest splitting).

Write the spec in the user's voice, not yours. You are a scribe, not an author.

### Spec Template

```markdown
## Objective
[One sentence: what this does and why it matters]

## Context
[2-3 sentences: current state, pain point, how this fits into the product]

## User Stories
- As a [role], I want [capability] so that [benefit]

## Functional Requirements
1. [Numbered, testable requirements — each one a discrete unit]

## Non-Functional Requirements
- [Performance, platform, accessibility, security constraints]

## Dependencies
- [What must exist or be true before this can be built]
- [Other tickets, merged PRs, or external services required]

## Constraints
- [General design/architecture constraints that bound the solution space]
- [NOT implementation details — no specific files, types, or code patterns]

## Boundaries
- ALWAYS: [Things the implementing agent can do autonomously]
- ASK FIRST: [Decisions requiring human sign-off]
- NEVER: [Categorically off-limits actions]

## Acceptance Criteria
- [ ] Given [context], when [action], then [expected result]
- [ ] [Use concrete values, not vague descriptions]
- [ ] [Include negative criteria: "MUST NOT do X"]
- [ ] [Include verification commands where applicable]

## Edge Cases
- What happens when [boundary condition]?
- What happens if [failure mode]?
- What happens when [empty/null/missing state]?

## Out of Scope
- [Explicitly excluded items — this is the highest-leverage section]
- [Adjacent features an eager agent might try to include]
- [Future work that is deliberately deferred]

## Open Questions
- [Anything unresolved that needs human decision before implementation]
```

After generating the draft, include a brief **adversarial note** — flag 2-3 things an implementing agent might get wrong based on this spec. Frame as: "An agent reading this spec might..." This surfaces ambiguities in what's already written. Do not introduce new failure modes or requirements the user hasn't mentioned — instead, point out where existing requirements are vague or could be misinterpreted.

Present the draft and adversarial notes together. Do NOT proceed until the user responds.

## Phase 4: Refine

Incorporate the user's feedback. If they flag new gaps, ask targeted follow-ups — don't re-interview from scratch. Iterate until the user explicitly approves.

**Signs the spec is ready:**
- Every acceptance criterion is testable by an agent without asking questions
- The Out of Scope section is non-empty
- The Boundaries section has at least one NEVER item
- An engineer reading only this spec would know the full scope

## Phase 5: Publish

When the user approves, update the Linear ticket description with the final spec via MCP: `save_issue` with the ticket's `id` and the spec as `description`. If the original ticket description had useful context (links, screenshots) not captured in the spec, confirm with the user before overwriting.

Confirm to the user with the ticket URL.

Do NOT move the ticket to a different state — that's the user's decision.

## Rules

- **Never suggest implementation details.** No file paths, no function names, no architectural prescriptions. General constraints ("must not block the main thread") are fine; specific solutions ("use a background actor") are not.
- **Never invent requirements.** If the user didn't say it and the ticket doesn't say it, don't add it. Ask instead.
- **Keep it short.** A spec longer than 150 lines is a scope problem. Suggest splitting.
- **Acceptance criteria are contracts.** "Handles errors gracefully" is not a criterion. "Returns an error toast with the Linear API error message when sync fails" is.
- **Out of Scope is mandatory.** If the user can't articulate what this doesn't cover, the boundary isn't clean enough.
- **Point to patterns, not prose.** If a constraint references existing system behavior, name the feature or component, not a paragraph describing it.
