## Title
Bound declared-constraint remote lookup concurrency

## Problem
`DeclaredConstraintAnalyzer.analyze(pins:declared:)` launches one remote lookup task per declared dependency without any concurrency cap. Large manifests can therefore trigger a burst of simultaneous `git ls-remote --tags` operations.

## Impact
- Avoidable subprocess and network spikes.
- Inconsistent resource profile between outdated checks and declared-constraint checks.
- Greater risk of flaky behavior on large dependency sets.

## Proposed solution
1. Add a `concurrentFetchLimit` to `DeclaredConstraintAnalyzer`.
2. Reuse the bounded task-group scheduling pattern already present in `OutdatedChecker`.
3. Drive both analyzers from `TrackerConfiguration.concurrentFetchLimit`.

## Acceptance criteria
- [ ] Declared-constraint analysis honors the configured concurrency limit.
- [ ] Result ordering stays deterministic.
- [ ] Drift/finding behavior remains unchanged.
