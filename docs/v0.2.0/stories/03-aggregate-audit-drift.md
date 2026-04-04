# Story 03: Aggregate Audit and Drift

Branch: `codex/feature/v0.2.0-aggregate-audit-drift`

## Objective

Compose per-context audits into one workspace report and separate declared drift from resolved drift.

## Owned Files

- `Sources/DependencyTrackerCore/Analyzers/CrossManifestConstraintDriftAnalyzer.swift`
- `Sources/DependencyTrackerCore/Analyzers/CrossContextResolvedDriftAnalyzer.swift`
- `Sources/DependencyTrackerCore/Engine/WorkspaceReportAssembler.swift`
- `Tests/DependencyTrackerCoreTests/AggregateAuditDriftTests.swift`

## Deliverables

- Declared drift analyzer for requirement divergence across manifests.
- Resolved drift analyzer for divergence across different resolution contexts only.
- Workspace report assembly helper that merges context reports, aggregate findings, and partial failures.
- Explicit severity rules for declared drift and resolved drift.
- Tests for one-context, multi-context, mixed-success, and partial-failure scenarios.

## Rules

- Reuse existing `Finding` severity and actionable semantics.
- Do not modify CLI or AppKit code in this story.
- Leave final engine integration simple and obvious for the main thread.

## Verification

- `swift test --filter AggregateAuditDriftTests`
- `swift test`
