## Title
Fix false-positive repo root prefix matching in `GitClient.relativePath`

## Problem
`GitClient.relativePath(for:repositoryRoot:)` currently relies on `String.hasPrefix` for path ancestry checks. This can produce false positives when path prefixes overlap (`/tmp/repo` vs `/tmp/repo-old`) and may return invalid git-relative paths.

## Impact
- Incorrect `git ls-files --error-unmatch` behavior.
- Incorrect `git check-ignore -v` behavior.
- Potentially flaky tracking/ignore diagnostics.

## Proposed solution
1. Standardize URLs and compare path components, not raw string prefixes.
2. Ensure repository root is an actual ancestor directory.
3. Produce relative paths by component slicing.
4. Fall back to absolute path only if file truly sits outside repo root.

## Acceptance criteria
- [ ] Add unit test where `root=/tmp/repo`, `file=/tmp/repo-old/Package.resolved` and verify file is treated as outside root.
- [ ] Add positive test for normal in-repo path behavior.
- [ ] Tracking and ignore checks remain unchanged for valid in-repo inputs.
