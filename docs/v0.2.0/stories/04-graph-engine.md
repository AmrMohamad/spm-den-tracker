# Story 04: Graph Engine and Provenance

Branch: `codex/feature/v0.2.0-graph-engine`

## Objective

Build graph models and graph-aware risk analysis without overstating certainty.

## Owned Files

- `Sources/DependencyTrackerCore/Graph/**`
- `Sources/DependencyTrackerCore/Analyzers/TransitivePinAuditor.swift`
- `Sources/DependencyTrackerCore/Analyzers/BlastRadiusAnalyzer.swift`
- `Tests/DependencyTrackerCoreTests/GraphEngineTests.swift`
- `Tests/DependencyTrackerCoreTests/Fixtures/Graph/**`

## Deliverables

- Graph models with node metadata, edge provenance, and graph certainty levels.
- Graph assembly helpers that treat `Package.resolved` as node metadata, not edge truth.
- Transitive pin auditing gated by proven topology.
- Blast-radius analysis gated by trustworthy edges.
- Tests for metadata-only, partially enriched, and strong-provenance graphs.

## Rules

- No CLI or AppKit work in this story.
- No target-level claims from weak provenance.
- Keep graph algorithms small and collection-based; no external graph library.

## Verification

- `swift test --filter GraphEngineTests`
- `swift test`
