## Title
Filter peeled git refs at the GitClient remoteTags boundary

## Problem
`GitClient.remoteTags(for:)` currently returns raw `git ls-remote --tags` refs, including peeled entries ending in `^{}`. That leaks git internals to higher-level consumers and forces downstream cleanup.

## Impact
- Support-layer abstraction leak.
- Higher-level version parsing must know about git peeled-ref syntax.
- Future consumers can mis-handle annotated-tag repositories if they forget to strip `^{}`.

## Proposed solution
1. Filter out refs ending in `^{}` directly in `GitClient.remoteTags(for:)`.
2. Keep higher-level version normalization tolerant of `^{}` as defense in depth.
3. Add tests covering annotated-tag output.

## Acceptance criteria
- [ ] `remoteTags(for:)` never returns refs ending in `^{}`.
- [ ] Version parsing still works for repositories using annotated tags.
- [ ] Existing outdated-check behavior remains unchanged.
