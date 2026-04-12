# SwiftLint + SwiftFormat Setup — Design Spec

**Linear:** KLA-41  
**Date:** 2026-04-04  
**Status:** Approved

---

## Goal

Add SwiftLint and SwiftFormat to Klausemeister with configs adapted from the Journey app. Ensures consistent code style and catches common issues. Both tools are installed via Homebrew.

---

## Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Installation | Homebrew | Simple, standard for macOS-only dev tool |
| Max line width | 150 everywhere | Avoids heavy reformatting; consistent between formatter and linter |
| Xcode integration | SwiftLint build phase only | Format-on-build causes surprise rewrites during rapid iteration |
| Pre-commit hook | Skip for now | Xcode build phase is sufficient; can add later |
| Makefile targets | `lint` + `format` | Explicit dev-time invocation before committing |

---

## Config: `.swiftlint.yml`

Location: project root.

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
  - trailing_whitespace          # SwiftFormat handles this
  - opening_brace                # SwiftFormat handles this
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

**Notes:**
- No Pods/Carthage excludes — this is a pure SPM project.
- `SurfaceView.swift` (392 lines, heavy C interop) is within file length limits; no special exclusion needed unless specific rules fire during implementation.
- `type_name` exclusions from Journey are dropped — no Journey-specific type names apply here.

---

## Config: `.swiftformat`

Location: project root.

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

---

## Xcode Build Phase

A "Run Script" build phase added to the `Klausemeister` target, after "Compile Sources":

```bash
if which swiftlint > /dev/null; then
    swiftlint lint
else
    echo "warning: SwiftLint not installed — run: brew install swiftlint"
fi
```

- Runs on every build, shows warnings/errors inline in the editor.
- Does **not** use `--strict` (that's reserved for the Makefile lint target).

---

## Makefile

Location: project root.

```makefile
.PHONY: lint format

lint:
	swiftlint lint --strict

format:
	swiftformat .
```

- `make format` — rewrites all Swift files in place.
- `make lint` — strict mode, non-zero exit on any violation.

---

## CLAUDE.md Update

Add a new **"Code quality"** section:

> **Before committing or after completing a feature change**, run:
> ```
> make format && make lint
> ```
> SwiftFormat rewrites files in place. SwiftLint runs in strict mode and will fail on violations. Fix any lint errors before opening a PR.

---

## Out of Scope

- Pre-commit hook (deferred)
- CI integration (no `.github/` infrastructure exists yet)
- SPM plugin installation (Homebrew is sufficient)
