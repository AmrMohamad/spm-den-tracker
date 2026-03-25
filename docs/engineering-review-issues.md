# Staff SWE Engineering Review — Proposed Issues

Date: 2026-03-25  
Scope reviewed: `DependencyTrackerCore` command execution, git integration, and version-resolution pipeline.

---

## Issue 1 — Path Prefix Check Can Produce Wrong Git-Relative Paths

- **Area:** `GitClient.relativePath(for:repositoryRoot:)`
- **Severity:** High (correctness bug)
- **Source:** `Sources/DependencyTrackerCore/Support/GitClient.swift`

### Why this matters

`relativePath` currently checks `file.hasPrefix(root)` using raw strings. This can produce false positives when directory names share a prefix (for example, `/repo` and `/repo-old`). In those cases, the method can compute an invalid relative path and pass incorrect arguments to git commands (`ls-files`, `check-ignore`), causing flaky or wrong tracking/ignore results.

### Suggested fix

Use URL path component semantics rather than plain string prefix matching. A robust option is:

1. Standardize both URLs.
2. Compare path components to ensure the repository root is an actual ancestor directory.
3. Use `fileURL.path(percentEncoded:)` + component slicing to build relative paths.
4. Fall back to absolute path only when truly outside root.

### Acceptance criteria

- [ ] A test verifies that `repositoryRoot=/tmp/repo` and `file=/tmp/repo-old/Package.resolved` does **not** get treated as inside root.
- [ ] Existing tracked/untracked behavior remains unchanged for normal in-repo files.

---

## Issue 2 — Timeout Conversion Can Overflow/Trap for Invalid Values

- **Area:** `ProcessRunner.timeoutNanoseconds(for:)`
- **Severity:** High (stability bug)
- **Source:** `Sources/DependencyTrackerCore/Support/ProcessRunner.swift`

### Why this matters

`timeoutNanoseconds(for:)` converts a `TimeInterval` to `UInt64` directly. If timeout is negative, NaN, or very large, conversion can trap or produce undefined behavior. That turns configuration/input mistakes into process crashes.

### Suggested fix

- Validate timeout before conversion (`isFinite && timeout > 0`).
- Throw a domain error (for example `DependencyTrackerError.invalidTimeout`) for invalid values.
- Clamp overly large timeouts to `UInt64.max` nanoseconds (or reject with explicit error).

### Acceptance criteria

- [ ] Unit tests cover negative, zero, NaN, and very large timeout inputs.
- [ ] Invalid timeout values return a controlled error, not a crash.

---

## Issue 3 — Remote Tag Parsing Can Emit Duplicate Semantic Versions

- **Area:** `RemoteVersionCatalog.stableVersions(for:)` / `GitClient.remoteTags(for:)`
- **Severity:** Medium (performance + noisy analytics)
- **Source:** `Sources/DependencyTrackerCore/Support/RemoteVersionCatalog.swift`, `Sources/DependencyTrackerCore/Support/GitClient.swift`

### Why this matters

`git ls-remote --tags` often returns both annotated tag refs and peeled refs (`^{} ` variants). Current parsing normalizes both to the same semantic version and stores duplicates. This adds unnecessary sorting work and can skew downstream counts/telemetry if introduced later.

### Suggested fix

- Filter peeled refs (`^{}`) at the `GitClient.remoteTags(for:)` boundary.
- Deduplicate parsed versions with `Set<Version>` before sorting as defense in depth.

### Acceptance criteria

- [ ] A unit test with duplicate tag refs yields unique version outputs.
- [ ] Outdated and constraint checks preserve current functional behavior.

---

## Issue 4 — Outdated Checker Re-sorts Already Sorted Version Lists

- **Area:** `OutdatedChecker.evaluate(_:)`
- **Severity:** Medium (efficiency)
- **Source:** `Sources/DependencyTrackerCore/Analyzers/OutdatedChecker.swift`

### Why this matters

`RemoteVersionCatalog.stableVersions(for:)` already returns sorted versions, but `OutdatedChecker` sorts again (`versions.sorted().last`). Across many dependencies this is avoidable repeated work.

### Suggested fix

- Treat catalog output as pre-sorted and use `versions.last` directly.
- Add a short doc comment contract in `RemoteVersionCatalog.stableVersions(for:)` that order is ascending.

### Acceptance criteria

- [ ] Remove redundant sorting in consumers.
- [ ] Add/adjust tests to assert stable ascending order contract.

---

## Issue 5 — `remoteTags` Should Not Leak Peeled Git Refs

- **Area:** `GitClient.remoteTags(for:)`
- **Severity:** Medium (abstraction leak)
- **Source:** `Sources/DependencyTrackerCore/Support/GitClient.swift`

### Why this matters

`git ls-remote --tags` often returns annotated tag refs plus peeled refs (`^{}` entries). Returning those raw strings from the git layer leaks git implementation details to higher-level consumers.

### Suggested fix

- Discard peeled refs in `GitClient.remoteTags(for:)` so only canonical tag refs leave the support layer.

### Acceptance criteria

- [ ] `remoteTags(for:)` no longer returns refs ending in `^{}`.
- [ ] Higher-level version parsing still works for annotated-tag repositories.

---

## Issue 6 — Declared Constraint Analysis Uses Unbounded Remote Lookup Concurrency

- **Area:** `DeclaredConstraintAnalyzer.analyze(pins:declared:)`
- **Severity:** Medium (resource spikes)
- **Source:** `Sources/DependencyTrackerCore/Analyzers/DeclaredConstraintAnalyzer.swift`

### Why this matters

`OutdatedChecker` already caps remote fan-out with `concurrentFetchLimit`, but `DeclaredConstraintAnalyzer` currently launches every lookup immediately. Large manifests can therefore spawn an avoidable burst of concurrent `git ls-remote --tags` operations.

### Suggested fix

- Add a `concurrentFetchLimit` to `DeclaredConstraintAnalyzer`.
- Reuse the existing bounded task-group pattern from `OutdatedChecker`.
- Wire the analyzer to `TrackerConfiguration.concurrentFetchLimit` so both audit stages share the same knob.

### Acceptance criteria

- [ ] Declared-constraint analysis never exceeds the configured concurrency limit.
- [ ] Existing result ordering and drift classifications remain unchanged.

---

## Issue 7 — Add a Domain Error for Invalid Timeout Configuration

- **Area:** `DependencyTrackerError` / `ProcessRunner`
- **Severity:** Low (supporting fix)
- **Source:** `Sources/DependencyTrackerCore/Support/DependencyTrackerError.swift`, `Sources/DependencyTrackerCore/Support/ProcessRunner.swift`

### Why this matters

Hardening timeout conversion requires a controlled domain error for invalid configuration values. Without one, negative, zero, non-finite, or otherwise invalid timeouts cannot fail cleanly.

### Suggested fix

- Add `DependencyTrackerError.invalidTimeout(TimeInterval)`.
- Validate timeout inputs before process launch and throw `invalidTimeout` for non-finite or non-positive values.

### Acceptance criteria

- [ ] Invalid timeout values return `DependencyTrackerError.invalidTimeout`.
- [ ] Invalid timeout inputs do not trap or crash the process runner.

---

## Recommended Prioritization

1. **Issue 1** (correctness in git path interpretation)
2. **Issue 7 -> Issue 2** (add domain error, then harden timeout conversion)
3. **Issue 5 -> Issue 3** (filter peeled refs, then dedupe catalog output)
4. **Issue 4** (remove redundant outdated-check sort)
5. **Issue 6** (bound declared-constraint remote fan-out)

---

## Suggested GitHub Issue Titles

1. `Fix false-positive repo root prefix matching in GitClient.relativePath`
2. `Harden ProcessRunner timeout conversion against invalid TimeInterval values`
3. `Deduplicate semantic versions parsed from git ls-remote --tags output`
4. `Remove redundant version re-sort in OutdatedChecker`
5. `Filter peeled git refs at the GitClient remoteTags boundary`
6. `Bound declared-constraint remote lookup concurrency`
7. `Add invalid timeout domain error for ProcessRunner configuration`
