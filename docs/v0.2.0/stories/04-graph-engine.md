# Story 04: Graph Engine and Provenance

Branch: `codex/feature/v0.2.0-graph-engine`

## Objective

Build graph models and graph-aware risk analysis without overstating certainty.

## Owned Files

- `Sources/DependencyTrackerCore/Graph/**`
- `Sources/DependencyTrackerCore/Graph/TransitivePinAuditor.swift`
- `Sources/DependencyTrackerCore/Graph/BlastRadiusAnalyzer.swift`
- `Tests/DependencyTrackerCoreTests/GraphEngineTests.swift`
- `Tests/DependencyTrackerCoreTests/Fixtures/Graph/**`

## Deliverables

- Graph models with node metadata, edge provenance, and graph certainty levels.
- Graph assembly helpers that treat `Package.resolved` as resolved-context evidence and require manifest or Xcode project data for declaration-proven edges.
- Transitive pin auditing gated by enriched dependency-edge data.
- Blast-radius analysis gated by shared dependency identities across workspace contexts.
- Tests for metadata-only, partially enriched, and declaration-proven graphs.

## Rules

- No CLI or AppKit work in this story.
- No target-level claims from weak provenance.
- Keep graph algorithms small and collection-based; no external graph library.

## Verification

- `swift test --filter GraphEngineTests`
- `swift test`
