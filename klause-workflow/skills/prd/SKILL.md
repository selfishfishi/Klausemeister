---
name: prd
description: Use when interactively defining a project or feature PRD from a rough idea, problem statement, or product opportunity. Guides phased multiple-choice discovery for problem framing, user journey, edge cases, creative alternatives, and final PRD drafting. Matches the /prd workflow.
---

# prd skill

Define a project or feature PRD through an interactive, phase-gated product discovery workflow. Use this when the user wants to turn a rough idea, problem, opportunity, or feature description into a PRD.

## Core Rules

- Ask only multiple-choice questions during discovery. Every question must include 2-5 concrete options.
- Include an `Other / explain` option when none of the options can safely cover the space.
- Ask one phase at a time, then stop and wait for the user's answers.
- Do not advance past a confirmation step until the user explicitly confirms or corrects the summary.
- Do not invent requirements. If a requirement, boundary, or user need is unclear, ask.
- Do not jump into implementation details unless the user explicitly asks for technical planning.
- Keep the tone direct and product-focused.

## Workflow

### 1. Intake

Restate the user's initial idea in one short paragraph. Identify whether it is a project, feature, workflow/process improvement, research/strategy document, or unclear. If the user has not provided enough context, ask for a one-paragraph description before beginning.

### 2. Problem Discovery

Ask 3-5 multiple-choice questions to understand the core problem, who has it, the current pain or workaround, why it matters now, whether the proposed idea solves that pain, and what outcome would make the effort worthwhile.

Stop and wait for the user's answers.

### 3. Problem Confirmation

Summarize:

```markdown
## Problem Understanding
- User/customer:
- Current situation:
- Pain:
- Why now:
- Desired outcome:
- Risk if ignored:
```

Then ask:

```markdown
Is this problem captured correctly?
A. Yes, continue
B. Mostly, but I want to correct part of it
C. No, reframe the problem
D. Other / explain
```

If the user chooses anything other than "Yes, continue", incorporate the correction and confirm again.

### 4. Solution And Journey Discovery

Ask up to 10 multiple-choice questions to clarify the primary user, happy path, user journey, key states, what good looks like, must-have vs nice-to-have behavior, success metrics, UX expectations, constraints, non-goals, and launch or rollout expectations.

Ask only the number of questions needed. For a small feature, 4-6 is usually enough. For a new project, use 7-10.

Stop and wait for the user's answers.

### 5. Journey Confirmation

Summarize:

```markdown
## Solution And Journey
- Proposed solution:
- Primary user:
- Entry point:
- Happy path:
- Key states:
- Success criteria:
- Must-haves:
- Nice-to-haves:
- Out of scope:
```

Then ask:

```markdown
Is the solution and user journey captured correctly?
A. Yes, continue
B. Mostly, but adjust the journey
C. The solution is wrong, revisit it
D. Other / explain
```

If the user chooses anything other than "Yes, continue", incorporate the correction and confirm again.

### 6. Edge Case Discovery

Ask multiple-choice questions about edge cases, failure modes, and unresolved ambiguity. Prefer 3-7 unless the project is broad.

Cover empty or missing data, invalid user actions, permissions or access, failure states, concurrency or stale state, migration/backward compatibility if relevant, safety/privacy/trust concerns, and what the system must never do.

Stop and wait for the user's answers.

### 7. Edge Case Confirmation

Summarize:

```markdown
## Edge Cases And Boundaries
- Empty states:
- Failure states:
- Permission/access concerns:
- Safety/trust concerns:
- Must-never behavior:
- Open ambiguity:
```

Then ask:

```markdown
Are these edge cases and boundaries correct?
A. Yes, continue
B. Add or adjust one case
C. This misses a major category
D. Other / explain
```

If the user chooses anything other than "Yes, continue", incorporate the correction and confirm again.

### 8. Creative Pass

Challenge the first solution. Present concise creative options, including better or simpler alternatives, outside-the-box ideas that solve the real problem, friction reducers, delight moments, intelligent/personalized touches, and overbuilding risks.

Do not treat these ideas as requirements yet. Ask which options to include:

```markdown
Which creative direction should be included in the PRD?
A. Keep the core solution only
B. Include option 1
C. Include options 1 and 2
D. Include a different combination / explain
```

Stop and wait for the user's answer.

### 9. Draft PRD

Create the PRD:

```markdown
# PRD: [Project or Feature Name]

## Summary

## Problem

## Goals

## Non-Goals

## Users

## User Journey

## Requirements

## Edge Cases

## Success Metrics

## Creative Enhancements

## Risks And Open Questions
```

Then ask:

```markdown
Is this PRD ready to use?
A. Yes, final
B. Revise the problem
C. Revise the journey/requirements
D. Revise edge cases or creative options
E. Other / explain
```

Revise until the user chooses "Yes, final". When final, provide the complete PRD and note any remaining open questions. If the user supplied a Linear issue or project and asks to publish, update the appropriate Linear description only after explicit approval.
