---
description: Interactively define a project or feature PRD through phased multiple-choice discovery
argument-hint: "\"<project-or-feature-description>\""
---

# /prd

Turn a rough project or feature idea into a clear PRD through phased, multiple-choice discovery. This command defines the **what**, **why**, user journey, edge cases, and creative opportunities before producing the final PRD.

## Usage

```
/prd "<what you want to build, the problem, or why it matters>"
```

If the user invokes `/prd` without enough context, ask for a one-paragraph description before beginning the workflow.

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

Restate the user's initial idea in one short paragraph. Identify whether it is primarily:

- a new product/project
- a feature in an existing product
- a workflow/process improvement
- a research or strategy document
- unclear

Then begin Problem Discovery.

### 2. Problem Discovery

Ask 3-5 multiple-choice questions to understand:

- the core problem or opportunity
- who experiences it
- current pain or workaround
- why it matters now
- whether the proposed idea actually addresses the pain
- what outcome would make the effort worthwhile

Question style:

```markdown
1. Who feels this problem most directly?
   A. [specific user/persona]
   B. [specific user/persona]
   C. [internal/team/system]
   D. Other / explain
```

After asking, stop and wait for the user's answers.

### 3. Problem Confirmation

Summarize the problem in this structure:

```markdown
## Problem Understanding
- User/customer:
- Current situation:
- Pain:
- Why now:
- Desired outcome:
- Risk if ignored:
```

Then ask a multiple-choice confirmation question:

```markdown
Is this problem captured correctly?
A. Yes, continue
B. Mostly, but I want to correct part of it
C. No, reframe the problem
D. Other / explain
```

If the user chooses anything other than "Yes, continue", incorporate the correction and confirm again before continuing.

### 4. Solution And Journey Discovery

Ask up to 10 multiple-choice questions to clarify:

- who the primary user is
- the happy path
- the expected user journey
- the key moments or states
- what good looks like
- must-have vs nice-to-have behavior
- success metrics
- UX expectations, if applicable
- constraints and explicit non-goals
- launch or rollout expectations

Ask only the number of questions needed. For a small feature, 4-6 is usually enough. For a new project, use 7-10.

After asking, stop and wait for the user's answers.

### 5. Journey Confirmation

Summarize the solution and journey in this structure:

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

If the user chooses anything other than "Yes, continue", incorporate the correction and confirm again before continuing.

### 6. Edge Case Discovery

Ask multiple-choice questions about edge cases, failure modes, and unresolved ambiguity. Use as many as needed, but prefer 3-7 unless the project is broad.

Cover:

- empty or missing data
- invalid user actions
- permissions or access
- failure states
- concurrency or stale state
- migration/backward compatibility, if relevant
- safety, privacy, or trust concerns
- what the system must never do

After asking, stop and wait for the user's answers.

### 7. Edge Case Confirmation

Summarize the edge cases:

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

If the user chooses anything other than "Yes, continue", incorporate the correction and confirm again before continuing.

### 8. Creative Pass

Think creatively and challenge the first solution. Produce a concise exploration with:

- better or simpler alternatives to the proposed solution
- outside-the-box ideas that still solve the real problem
- ways to reduce friction
- ways to add delight
- ideas that make the experience feel more intelligent, polished, or personal
- risks of overbuilding

Do not treat these ideas as requirements yet. Present them as options:

```markdown
## Creative Options
1. [Idea] - [why it could help]
2. [Idea] - [why it could help]
3. [Idea] - [why it could help]

Which creative direction should be included in the PRD?
A. Keep the core solution only
B. Include option 1
C. Include options 1 and 2
D. Include a different combination / explain
```

Wait for the user's answer.

### 9. Draft PRD

Create the PRD in this format:

```markdown
# PRD: [Project or Feature Name]

## Summary
[One paragraph]

## Problem
[Who has the problem, what is painful, why now]

## Goals
- [Goal]

## Non-Goals
- [Explicitly out of scope]

## Users
- [Primary and secondary users]

## User Journey
1. [Entry point]
2. [Happy path step]
3. [Completion/success state]

## Requirements
1. [Clear, testable requirement]

## Edge Cases
- [Case and expected behavior]

## Success Metrics
- [Metric or observable outcome]

## Creative Enhancements
- [Only options the user selected]

## Risks And Open Questions
- [Unresolved decision or risk]
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

Revise until the user chooses "Yes, final".

## Output

When final, provide the complete PRD and a short note listing any remaining open questions. If the user supplied a Linear issue or project and asks to publish, update the appropriate Linear description only after explicit approval.
