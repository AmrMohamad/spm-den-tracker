# Story 01: Foundation Contracts

Branch: `codex/feature/v0.2.0-foundation-contracts`

## Objective

Stabilize the shared contract layer for aggregate workspace analysis so every later story can build on concrete types instead of assumptions.

## Owned Files

- `Sources/DependencyTrackerCore/Engine/AnalysisMode.swift`
- `Sources/DependencyTrackerCore/Engine/TrackerConfiguration.swift`
- `Sources/DependencyTrackerCore/Engine/WorkspaceAuditEngine.swift`
- `Sources/DependencyTrackerCore/Models/WorkspaceReport.swift`
- `Tests/DependencyTrackerCoreTests/FoundationContractsTests.swift`

## Deliverables

- `AnalysisMode` supports `auto`, `singleTarget`, and `monorepo`.
- `TrackerConfiguration` includes discovery and aggregate-analysis defaults.
- `WorkspaceReport` models aggregate output, partial failures, discovered manifests, and context reports.
- `WorkspaceAuditEngine` exists as the aggregate entry point and can wrap the current single-target engine.
- Tests cover default configuration, actionable aggregate status, and baseline single-target wrapping.

## Rules

- Do not change CLI behavior in this story.
- Keep `TrackerEngine.analyze(projectPath:)` compatible.
- Prefer concrete structs and enums.

## Verification

- `swift test --filter FoundationContractsTests`
- `swift test`
