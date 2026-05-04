# Story 05: CLI and Reporter Surface

Branch: `codex/feature/v0.2.0-cli-reporters`

## Objective

Expose workspace analysis and graph output through the CLI while preserving the existing single-target report path. The CLI should support three analysis modes, render aggregate workspace reports cleanly, and emit a graph view that can later be upgraded when richer core graph helpers arrive.

## Owned Files

- `Sources/DependencyTrackerCLI/**`
- `Sources/DependencyTrackerCore/Reporters/**`
- `Tests/DependencyTrackerCLITests/**`
- `Tests/DependencyTrackerCoreTests/WorkspaceReporterTests.swift`

## CLI Contract

- `doctor` and `report` accept `--analysis-mode auto|monorepo|single-target`.
- `single-target` preserves the current one-report behavior.
- `auto` is the opt-in workspace-aware mode for directory-style inputs.
- `monorepo` forces workspace-aware behavior.
- `graph` is a new subcommand with `--format mermaid|dot|json`.
- Exit codes stay simple: `0` for clean/info-only runs, `1` for warnings/errors, `65` for invalid input paths.

## Reporter Changes

- Keep the existing `DependencyReport` renderers stable.
- Add `WorkspaceReport` rendering for table, markdown, JSON, Xcode diagnostics, and JUnit.
- Workspace renderers should surface:
  - root path
  - analysis mode
  - discovered manifest count
  - context count
  - partial failures
  - per-context single-target output
- Keep the rendering policy in reporters, not in CLI commands.
- Do not introduce a second report architecture for single-target runs.

## Verification

- `swift test`
- CLI smoke checks for:
  - `doctor` in single-target mode
  - `report` in single-target mode
  - `report` in workspace mode
  - `graph --format mermaid`
  - `graph --format dot`
  - `graph --format json`
- Reporter tests for:
  - `DependencyReport` output unchanged
  - `WorkspaceReport` markdown/table/JSON rendering
  - graph renderer output structure

## Integration Notes

- This story depends on the workspace engine and aggregate report types already introduced in the base 0.2.0 contract layer.
- Graph output stays adapter-based at the CLI boundary. The command renders the core workspace graph model, including dependency nodes and edge provenance when enrichment is enabled, without changing the command surface.
