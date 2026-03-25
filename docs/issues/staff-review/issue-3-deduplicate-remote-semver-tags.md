## Title
Deduplicate semantic versions parsed from `git ls-remote --tags`

## Problem
`git ls-remote --tags` may return both annotated tags and peeled refs (`^{}`). Current parsing can normalize both into identical semantic versions and keep duplicates.

## Impact
- Unnecessary sorting and processing overhead.
- Risk of noisy downstream analytics/count-based reporting.

## Proposed solution
1. Deduplicate parsed semantic versions (for example via `Set<Version>`).
2. Optionally ignore peeled refs early for cleaner tag parsing.
3. Keep final output deterministically sorted ascending.

## Acceptance criteria
- [ ] Add test fixture containing duplicated tag refs and verify unique semantic versions.
- [ ] Outdated and declared-constraint analyzers keep existing functional behavior.
- [ ] Version catalog output ordering remains deterministic.
