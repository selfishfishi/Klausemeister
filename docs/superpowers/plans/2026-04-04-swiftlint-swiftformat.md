# SwiftLint + SwiftFormat Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add SwiftLint and SwiftFormat to Klausemeister — config files at the project root, a SwiftLint Xcode build phase, a Makefile with `lint`/`format` targets, and a Code quality section in CLAUDE.md.

**Architecture:** Three new files (`.swiftlint.yml`, `.swiftformat`, `Makefile`) at the project root; one edit to `Klausemeister.xcodeproj/project.pbxproj` to add a `PBXShellScriptBuildPhase`; one edit to `CLAUDE.md`. No new Swift code — this is pure configuration.

**Tech Stack:** SwiftLint (Homebrew), SwiftFormat (Homebrew), Make, Xcode project.pbxproj

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `.swiftlint.yml` | SwiftLint rules and exclusions |
| Create | `.swiftformat` | SwiftFormat style options |
| Create | `Makefile` | `lint` and `format` dev targets |
| Modify | `Klausemeister.xcodeproj/project.pbxproj` | Add SwiftLint build phase to target |
| Modify | `CLAUDE.md` | Add "Code quality" section |

---

## Prerequisites

Before starting, verify both tools are installed:

```bash
which swiftlint && swiftlint --version
which swiftformat && swiftformat --version
```

If either is missing:

```bash
brew install swiftlint swiftformat
```

---

## Task 1: Create feature branch off main

**Files:** none (git operation)

- [ ] **Step 1: Create and switch to implementation branch**

```bash
cd /Users/alifathalian/github/selfishfishi/Klausemeister
git checkout main
git pull
git checkout -b a/kla-41-set-up-swiftlint-and-swiftformat
```

Expected: `Switched to a new branch 'a/kla-41-set-up-swiftlint-and-swiftformat'`

---

## Task 2: Create `.swiftlint.yml`

**Files:**
- Create: `.swiftlint.yml`

- [ ] **Step 1: Create the file**

Create `.swiftlint.yml` at the project root with this exact content:

```yaml
line_length:
  warning: 150
  error: 250

file_length:
  warning: 500
  error: 1000

function_body_length:
  warning: 50
  error: 100

disabled_rules:
  - trailing_whitespace
  - opening_brace
  - blanket_disable_command
  - multiple_closures_with_trailing_closure

opt_in_rules:
  - closure_spacing
  - modifier_order
  - overridden_super_call

excluded:
  - .build
  - Klausemeister.xcodeproj
  - Klausemeister/Assets.xcassets
```

- [ ] **Step 2: Verify SwiftLint can parse the config**

```bash
swiftlint lint --config .swiftlint.yml --quiet 2>&1 | head -20
```

Expected: lint output (warnings or clean) — no "error: configuration" lines.

- [ ] **Step 3: Commit**

```bash
git add .swiftlint.yml
git commit -m "Add .swiftlint.yml (KLA-41)"
```

---

## Task 3: Create `.swiftformat`

**Files:**
- Create: `.swiftformat`

- [ ] **Step 1: Create the file**

Create `.swiftformat` at the project root with this exact content:

```
--indent 4
--maxwidth 150
--allman false
--commas inline
--importgrouping testable-last
--wraparguments before-first
--wrapparameters before-first
--wrapcollections before-first
--swiftversion 6.2
--exclude .build,Klausemeister.xcodeproj
```

- [ ] **Step 2: Verify SwiftFormat can parse the config**

```bash
swiftformat --config .swiftformat --dryrun Klausemeister/KlausemeisterApp.swift 2>&1
```

Expected: output ending with `1 file(s) would have been formatted` or `1 file(s) skipped (no changes)` — no "error: unknown option" lines.

- [ ] **Step 3: Commit**

```bash
git add .swiftformat
git commit -m "Add .swiftformat (KLA-41)"
```

---

## Task 4: Create `Makefile`

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create the file**

Create `Makefile` at the project root. **Indentation must use real tab characters**, not spaces:

```makefile
.PHONY: lint format

lint:
	swiftlint lint --strict

format:
	swiftformat .
```

(The line `	swiftlint lint --strict` and `	swiftformat .` must begin with a tab, not spaces.)

- [ ] **Step 2: Verify `make format` runs**

```bash
make format 2>&1 | tail -5
```

Expected: SwiftFormat output like `5 files formatted.` or `5 files skipped (no changes).`

- [ ] **Step 3: Verify `make lint` runs**

```bash
make lint 2>&1 | tail -10
```

Expected: SwiftLint output. May show warnings/violations — that's fine for now (we fix in Task 7). The command should exit without "swiftlint: command not found".

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "Add Makefile with lint and format targets (KLA-41)"
```

---

## Task 5: Add SwiftLint Xcode build phase

**Files:**
- Modify: `Klausemeister.xcodeproj/project.pbxproj`

The project uses `ENABLE_USER_SCRIPT_SANDBOXING = YES`. To allow SwiftLint to read source files in a sandboxed build phase, the phase must declare `$(SRCROOT)` as an input path.

Two edits are needed:

**Edit A** — Insert a new `PBXShellScriptBuildPhase` section (between `/* End PBXSourcesBuildPhase section */` and `/* Begin XCBuildConfiguration section */`):

- [ ] **Step 1: Insert the build phase object**

In `Klausemeister.xcodeproj/project.pbxproj`, find this exact line:

```
/* End PBXSourcesBuildPhase section */
```

And insert the following block immediately after it (before the blank line that precedes `/* Begin XCBuildConfiguration section */`):

```
/* Begin PBXShellScriptBuildPhase section */
		A8AAAA012F816B35005797B3 /* SwiftLint */ = {
			isa = PBXShellScriptBuildPhase;
			alwaysOutOfDate = 1;
			buildActionMask = 2147483647;
			files = (
			);
			inputFileListPaths = (
			);
			inputPaths = (
				"$(SRCROOT)",
			);
			name = SwiftLint;
			outputFileListPaths = (
			);
			outputPaths = (
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "if which swiftlint > /dev/null; then\n    swiftlint lint\nelse\n    echo \"warning: SwiftLint not installed, run: brew install swiftlint\"\nfi\n";
		};
/* End PBXShellScriptBuildPhase section */
```

**Edit B** — Register the build phase UUID in the target's `buildPhases` array:

- [ ] **Step 2: Add UUID to target buildPhases**

In the same file, find this exact block:

```
			buildPhases = (
				A869EEDC2F816B35005797B3 /* Sources */,
				A869EEDD2F816B35005797B3 /* Frameworks */,
				A869EEDE2F816B35005797B3 /* Resources */,
			);
```

Replace it with:

```
			buildPhases = (
				A869EEDC2F816B35005797B3 /* Sources */,
				A869EEDD2F816B35005797B3 /* Frameworks */,
				A869EEDE2F816B35005797B3 /* Resources */,
				A8AAAA012F816B35005797B3 /* SwiftLint */,
			);
```

- [ ] **Step 3: Verify the file is valid**

```bash
plutil -lint Klausemeister.xcodeproj/project.pbxproj
```

Expected: `Klausemeister.xcodeproj/project.pbxproj: OK`

- [ ] **Step 4: Commit**

```bash
git add Klausemeister.xcodeproj/project.pbxproj
git commit -m "Add SwiftLint Xcode build phase (KLA-41)"
```

---

## Task 6: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add Code quality section**

Append to the end of `CLAUDE.md` (after the last line of `## Swift conventions`). The section uses two inline code snippets and two fenced code blocks:

Section heading: `## Code quality`

Paragraph: `**Before committing or after completing a feature change**, run:`

Fenced bash block:
```
make format && make lint
```

Paragraph: `` `make format` runs SwiftFormat and rewrites files in place. `make lint` runs SwiftLint in strict mode and exits non-zero on any violation. Fix all lint errors before opening a PR. ``

Paragraph: `Both tools must be installed via Homebrew:`

Fenced bash block:
```
brew install swiftlint swiftformat
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Add Code quality section to CLAUDE.md (KLA-41)"
```

---

## Task 7: Verify — run format + lint, fix any violations

**Files:** any Swift files that SwiftFormat rewrites or SwiftLint flags

- [ ] **Step 1: Run formatter**

```bash
make format
```

SwiftFormat will rewrite any files that don't match the config. Check what changed:

```bash
git diff --stat
```

If files were changed, review the diffs. These are cosmetic formatting changes — accept them all:

```bash
git add -p   # review and stage each hunk, or:
git add Klausemeister/
git commit -m "Apply SwiftFormat to existing code (KLA-41)"
```

If no files changed, nothing to commit.

- [ ] **Step 2: Run linter in strict mode**

```bash
make lint
```

- [ ] **Step 3: Fix any violations**

If `make lint` exits non-zero, review each violation. Common issues:

| Violation | Fix |
|-----------|-----|
| `function_body_length` | If legitimate complex function (e.g., `SurfaceView` C-interop), add `// swiftlint:disable:next function_body_length` above the function declaration. |
| `line_length` | SwiftFormat should have already wrapped long lines. If not, wrap manually. |
| `modifier_order` | Reorder modifiers to match Swift convention (e.g., `final override` → `override final` is wrong; correct is `final override`). |
| `closure_spacing` | Add space inside closure braces: `{ x }` not `{x}`. |

After fixes:

```bash
make lint
```

Expected: exit 0, output ending with `Done linting! Found 0 violations, 0 serious in X files.`

- [ ] **Step 4: Commit fixes if any**

```bash
git add Klausemeister/
git commit -m "Fix SwiftLint violations in existing code (KLA-41)"
```

---

## Done

At this point:

- `.swiftlint.yml` and `.swiftformat` are at the project root
- `make format` and `make lint` both pass cleanly
- The Xcode build phase shows SwiftLint warnings inline during builds
- CLAUDE.md documents the workflow

Update the Linear issue KLA-41 to **In Progress** → **In Review** and open a PR targeting `main`.
