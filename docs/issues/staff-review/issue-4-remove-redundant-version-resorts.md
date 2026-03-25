## Title
Remove redundant version re-sorts in outdated and constraint analyzers

## Problem
`RemoteVersionCatalog.stableVersions(for:)` returns sorted versions, but analyzers re-sort again (for example `versions.sorted().last`).

## Impact
- Repeated unnecessary work across dependency sets.
- Avoidable overhead in larger lockfiles.

## Proposed solution
1. Treat catalog output as ascending and use `versions.last` directly in consumers.
2. Document ordering contract on `stableVersions(for:)`.
3. Add tests that lock ordering assumptions.

## Acceptance criteria
- [ ] Remove redundant sorting in analyzer consumers.
- [ ] Add/adjust tests asserting ascending order contract.
- [ ] No behavior regressions in existing analyzer tests.
