---
name: spm-dep-tracker-cli
description: Use the spm-dep-tracker command-line tool in this repository to audit Xcode-managed Swift Package dependencies and Package.resolved health. Trigger when an agent needs to inspect an .xcodeproj, a repo directory containing exactly one .xcodeproj, or a direct Package.resolved path; run doctor, report, or check-tracking; choose table, markdown, json, xcode, or junit output; explain exit codes; or prepare CI-friendly dependency audit commands.
user-invocable: true
allowed-tools: Bash, Read, Glob
argument-hint: [project-path]
---

# SPM Dependency Tracker CLI

## Overview

Use this skill to run and interpret the repository's CLI without rediscovering command behavior from source each time. Prefer the smallest command that answers the user's request, then report the relevant exit-code semantics with the result.

## Workflow

1. Work from the repository root at `/Users/amrmohamad/Developer/spm-den-tracker`.
2. Prefer `swift run spm-dep-tracker ...` for ad-hoc use.
3. Prefer `.build/release/spm-dep-tracker ...` only after a deliberate `swift build -c release` when repeated invocations matter.
4. Accept only these input forms:
   - direct `.xcodeproj` path
   - directory containing exactly one immediate `.xcodeproj`
   - direct `Package.resolved` path
5. Stop and request an explicit project path if a directory contains multiple immediate `.xcodeproj` bundles.
6. Use `doctor` for interactive terminal diagnosis, `report` for exported output, and `check-tracking` for a narrow git-tracking gate.
7. Add `--strict-constraints` only when declared-constraint drift should count as an actionable failure.
8. Read `${CLAUDE_SKILL_DIR}/references/cli-cookbook.md` when the user needs concrete command recipes, output-format selection, build/test commands, or installation guidance.

## Command Selection

### `doctor`

Use for human-readable diagnosis in the terminal.

- Command pattern: `swift run spm-dep-tracker doctor <path> [--strict-constraints]`
- Exit codes:
  - `0` for informational findings only
  - `1` for warnings or errors
  - `65` for an invalid input path

### `report`

Use when the user needs persisted or machine-readable output.

- Command pattern: `swift run spm-dep-tracker report <path> --format <table|markdown|json|xcode|junit> [--output <file>] [--strict-constraints]`
- Prefer `markdown` for PRs and notes, `json` for tooling, `xcode` for compiler-style CI logs, and `junit` for test-report ingestion.
- Exit codes:
  - `0` for informational findings only
  - `1` for warnings or errors
  - `65` for an invalid input path

### `check-tracking`

Use for the narrow question "is `Package.resolved` tracked by git?"

- Command pattern: `swift run spm-dep-tracker check-tracking <path>`
- Interpret the one-line result as one of `tracked`, `untracked`, `gitignored`, or `missing`.
- Exit codes:
  - `0` when the file is tracked
  - `2` when the file is missing, untracked, or ignored
  - `65` for an invalid input path

## Guardrails

- Do not claim a directory input is valid until you verify it contains exactly one immediate `.xcodeproj`.
- Do not use `--strict-constraints` unless the user wants constraint drift to affect failures or CI status.
- Do not run the full audit when the user only needs lockfile tracking state.
- Quote file-system paths that may contain spaces.
- Use the bundled installer commands from the reference file instead of inventing manual install steps.
