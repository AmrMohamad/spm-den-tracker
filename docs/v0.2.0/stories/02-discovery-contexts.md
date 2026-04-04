# Story 02: Discovery and Resolution Contexts

Branch: `codex/feature/v0.2.0-discovery-contexts`

## Objective

Add deterministic workspace discovery and resolution-context grouping for repository-root analysis.

## Owned Files

- `Sources/DependencyTrackerCore/Discovery/**`
- `Tests/DependencyTrackerCoreTests/DiscoveryContextTests.swift`
- `Tests/DependencyTrackerCoreTests/Fixtures/WorkspaceDiscovery/**`

## Deliverables

- Recursive discovery of `.xcodeproj`, `.xcworkspace`, `Package.swift`, and `Package.resolved`.
- Built-in ignore rules and repo-root `.spm-dep-tracker-ignore` augmentation.
- Canonical-path dedupe and ownership keys for equivalent manifest sources.
- Resolution-context grouping keyed by effective resolved-file ownership.
- Tests for nested repos, duplicate ownership, ignore patterns, and depth limits.

## Rules

- Keep discovery pure and deterministic.
- Avoid mutating existing CLI or app code in this story.
- Prefer adding new discovery helpers over expanding `XcodeprojLocator`.

## Verification

- `swift test --filter DiscoveryContextTests`
- `swift test`
