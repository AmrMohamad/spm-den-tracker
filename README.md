# SPM Dependency Tracker

SPM Dependency Tracker audits the dependency lock state of Xcode projects and workspace roots that use Swift Package Manager.
It is built for the practical failure modes teams hit in CI and shared development environments:

- `Package.resolved` missing, untracked, or accidentally ignored
- lockfiles written with older schema versions
- dependencies pinned to branches, revisions, or local paths instead of reproducible versions
- declared package requirements drifting from the resolved versions in source control
- upstream stable releases existing beyond the current resolved version
- repository roots that need recursive manifest discovery and aggregate reporting

The repository currently ships three deliverables:

- `DependencyTrackerCore`: the reusable analysis engine and report formatters
- `spm-dep-tracker`: the command-line tool for local workflows and CI
- `DependencyTrackerApp`: a macOS AppKit app for interactive inspection and export

For AI-assisted workflows, the repo also includes local skill definitions for Codex and Claude Code so agents can use the CLI with the same input rules, command selection, and exit-code expectations documented in the source tree.

## What The Audit Covers

For a given Xcode project, repository root, or `Package.resolved`, the engine assembles one dependency report or one aggregate workspace report with:

- resolved-file tracking status: `tracked`, `untracked`, `gitignored`, or `missing`
- `Package.resolved` schema version and compatibility classification
- per-dependency pin strategy risk for versions, branches, revisions, and local paths
- declared package requirements discovered from the package manifest or Xcode project
- constraint drift analysis between declared rules, resolved versions, and the latest allowed version
- outdated checks against the latest stable upstream semantic version tags
- workspace discovery, resolution-context grouping, and partial-failure visibility for repository-root analysis
- graph output with bounded certainty labels so the tool can distinguish metadata-only, partially enriched, and complete graph data

The result is shared across every output surface in the repo: terminal table, Markdown, JSON, Xcode-style diagnostics, JUnit XML, graph output, and the macOS UI.

## Supported Inputs

`doctor`, `report`, and `graph` accept these input forms:

- a direct `.xcodeproj` path
- a directory that contains exactly one immediate `.xcodeproj`
- a direct `Package.resolved` path
- a repository root when `--analysis-mode monorepo` is enabled

`check-tracking` keeps the original v1 contract:

- a direct `.xcodeproj` path
- a directory that contains exactly one immediate `.xcodeproj`
- a direct `Package.resolved` path

If a directory contains more than one immediate `.xcodeproj`, the path is treated as ambiguous and the command fails intentionally.

## Analysis Modes

The workspace feature adds three explicit analysis modes:

- `single-target`: preserve the current one-project or one-lockfile behavior
- `monorepo`: recursively discover auditable manifests beneath a repository root
- `auto`: choose the narrowest safe mode from the input shape

Use `--analysis-mode single-target` to force the old behavior and `--analysis-mode monorepo` to force recursive discovery.

## Workspace Output

Workspace reports add:

- discovered manifests and their ownership keys
- per-context reports for each resolution context
- workspace-level aggregate findings
- partial failures that did not block the entire run

Graph output is labeled by certainty:

- `metadataOnly`: the graph only knows node metadata from `Package.resolved`
- `partiallyEnriched`: some edges came from stronger sources, but not all of the graph is fully proven
- `complete`: the graph has enough edge provenance to support graph-aware analysis with confidence

`Package.resolved` alone does not provide graph topology. It provides resolved node metadata; topology comes from manifests, workspace structure, or dependency-enrichment sources.

## Requirements

- macOS 14 or newer
- Swift 6.2 toolchain
- Xcode for AppKit app builds

The Swift package declares `swift-tools-version: 6.2` and targets `macOS(.v14)`.

## Quick Start

Build the CLI:

```bash
swift build
```

Inspect a project:

```bash
swift run spm-dep-tracker doctor /path/to/MyApp.xcodeproj
```

Inspect a repository root:

```bash
swift run spm-dep-tracker doctor /path/to/repo-root --analysis-mode monorepo
swift run spm-dep-tracker report /path/to/repo-root --analysis-mode monorepo --format markdown
swift run spm-dep-tracker graph /path/to/repo-root --analysis-mode monorepo --format mermaid
```

Generate Markdown for a pull request or engineering note:

```bash
swift run spm-dep-tracker report /path/to/MyApp.xcodeproj --format markdown
```

Emit CI-friendly diagnostics:

```bash
swift run spm-dep-tracker report /path/to/MyApp.xcodeproj --format xcode
swift run spm-dep-tracker report /path/to/MyApp.xcodeproj --format junit --output ./build/dependency-audit.xml
```

Verify only whether the lockfile is tracked by git:

```bash
swift run spm-dep-tracker check-tracking /path/to/MyApp.xcodeproj
```

Graph the dependency topology:

```bash
swift run spm-dep-tracker graph /path/to/MyApp.xcodeproj --format mermaid
swift run spm-dep-tracker graph /path/to/repo-root --analysis-mode monorepo --format dot --output ./Reports/dependencies.dot
swift run spm-dep-tracker graph /path/to/repo-root --analysis-mode monorepo --format json --output ./Reports/dependencies.json
```

## Installation

For local installs, use the guided installer:

```bash
./scripts/install_dependency_tracker_app.sh
```

The installer supports three modes:

- `cli`: install only `spm-dep-tracker`
- `app`: install only `DependencyTrackerApp`
- `full`: install both the CLI and the macOS app

Safe defaults:

- CLI defaults to a user-owned install location, typically `~/.local/bin`
- App defaults to `/Applications/DependencyTrackerApp.app`
- existing installs are not overwritten without confirmation unless you pass `--force`

If you keep the default app destination, make sure your shell session has permission to write to `/Applications`.

Useful examples:

```bash
./scripts/install_dependency_tracker_app.sh --mode cli
./scripts/install_dependency_tracker_app.sh --mode full
./scripts/install_dependency_tracker_app.sh --mode full --cli-bin-dir "$HOME/.local/bin"
./scripts/install_dependency_tracker_app.sh --mode app --app-path "/Applications/DependencyTrackerApp.app"
./scripts/install_dependency_tracker_app.sh --mode full --non-interactive --dry-run
```

Run `./scripts/install_dependency_tracker_app.sh --help` for the full installer contract.

### Homebrew

The upstream repo keeps a development/reference formula at [Formula/spm-dep-tracker.rb](Formula/spm-dep-tracker.rb), but the public first-time install path is moving to a dedicated tap repo.

Best-practice install target:

```bash
brew install AmrMohamad/spm-den-tracker/spm-dep-tracker
```

That command requires a dedicated tap repo named `AmrMohamad/homebrew-spm-den-tracker`, because Homebrew resolves `user/repo/formula` taps via the `homebrew-<repo>` naming convention.

Current repository state:

- the checked-in formula here is still `HEAD`-only and is meant for maintainer validation, not the final first-time public install path
- `DependencyTrackerApp` remains outside the formula and continues to use the guided installer
- maintainers can render a stable tap formula with `./scripts/prepare_homebrew_release.sh --version <x.y.z> --formula-out <path>`
- maintainers can sync the dedicated tap repo with `./scripts/sync_homebrew_tap.sh --version <x.y.z>`
- the tag workflow at [release-homebrew.yml](.github/workflows/release-homebrew.yml) publishes the CLI archive and syncs the dedicated tap repo automatically
- the release archive is validated as a universal `arm64` + `x86_64` binary before the workflow publishes it

Until the first stable Homebrew release is published, maintainers can still install the CLI from source with:

```bash
brew install --HEAD AmrMohamad/spm-den-tracker/spm-dep-tracker
```

After the stable release is published, users should prefer:

```bash
brew install AmrMohamad/spm-den-tracker/spm-dep-tracker
```

Bare install by first-time users:

```bash
brew install spm-dep-tracker
```

is a future `homebrew/core` goal, not something a custom tap can provide on a fresh machine.

Release maintenance details live in [release-homebrew.md](docs/release-homebrew.md), and future core-submission prep lives in [homebrew-core-readiness.md](docs/homebrew-core-readiness.md).

#### Tag-Push Automation

Install the tracked git hooks once per clone:

```bash
make setup-hooks
```

After that, pushing a release tag such as `v0.2.0` from either the terminal or Fork runs a local preflight before the tag is sent to GitHub:

- the hook detects pushed `v*` tags only
- release inputs are rendered to temporary paths, not the repo
- successful preflights are cached under `.git/release-preflight-cache/`
- the remote `release-homebrew.yml` workflow still handles the actual GitHub release and tap sync after the tag arrives on GitHub

Creating a tag locally does not trigger anything by itself; the automation boundary is tag push.

Emergency bypasses:

- `git push --no-verify origin v0.2.0`
- `SPM_DEP_TRACKER_SKIP_TAG_PREFLIGHT=1 git push origin v0.2.0`

## CLI Reference

### `doctor`

Runs the full audit and prints the terminal table summary.

```bash
spm-dep-tracker doctor /path/to/MyApp.xcodeproj
spm-dep-tracker doctor /path/to/repo-root
spm-dep-tracker doctor /path/to/Package.resolved --strict-constraints
```

Exit codes:

- `0`: only informational findings
- `1`: warnings or errors were found
- `65`: input path does not exist

### `report`

Runs the same audit pipeline and renders the result in a chosen format.

```bash
spm-dep-tracker report /path/to/MyApp.xcodeproj --format table
spm-dep-tracker report /path/to/MyApp.xcodeproj --format markdown
spm-dep-tracker report /path/to/MyApp.xcodeproj --format json --output ./Reports/dependencies.json
spm-dep-tracker report /path/to/MyApp.xcodeproj --format xcode
spm-dep-tracker report /path/to/MyApp.xcodeproj --format junit --strict-constraints
spm-dep-tracker report /path/to/repo-root --analysis-mode monorepo --format markdown
```

Supported formats:

- `table`
- `markdown`
- `json`
- `xcode`
- `junit`

Exit codes:

- `0`: only informational findings
- `1`: warnings or errors were found
- `65`: input path does not exist

### `graph`

Outputs dependency topology in a graph-friendly format.

```bash
spm-dep-tracker graph /path/to/MyApp.xcodeproj --format mermaid
spm-dep-tracker graph /path/to/repo-root --analysis-mode monorepo --format dot
spm-dep-tracker graph /path/to/repo-root --analysis-mode monorepo --format json
```

Supported formats:

- `mermaid`
- `dot`
- `json`

Exit codes:

- `0`: graph output rendered successfully
- `1`: warnings, errors, or partial-failure findings were produced
- `65`: input path does not exist

### `check-tracking`

Performs only the git-tracking audit for `Package.resolved` and prints a one-line status.

```bash
spm-dep-tracker check-tracking /path/to/MyApp.xcodeproj
spm-dep-tracker check-tracking /path/to/repo-root
spm-dep-tracker check-tracking /path/to/Package.resolved
```

Exit codes:

- `0`: the resolved file is tracked by git
- `2`: the resolved file is missing, untracked, or ignored
- `65`: input path does not exist

## Strict Constraints

`--strict-constraints` promotes declared-constraint findings into actionable failures.

Use it when you want drift between declared requirements and resolved versions to affect:

- CLI exit status
- Xcode-style CI diagnostics
- JUnit failure output

## Output Formats

- `table`: aligned terminal summary plus dependency matrix
- `markdown`: shareable report for pull requests, docs, and issue threads
- `json`: machine-readable export for tooling or dashboards
- `xcode`: compiler-style warning and error lines for Xcode and CI logs
- `junit`: XML suite with actionable findings surfaced as failures
- `mermaid`: graph output for rendered diagrams and PR descriptions
- `dot`: Graphviz-compatible graph output

## Agent Skills

The repository ships repo-local CLI skills for both supported agent layouts:

- Codex: [`.agent/skills/spm-dep-tracker-cli/SKILL.md`](.agent/skills/spm-dep-tracker-cli/SKILL.md)
- Claude Code: [`.claude/skills/spm-dep-tracker-cli/SKILL.md`](.claude/skills/spm-dep-tracker-cli/SKILL.md)

Each skill teaches the agent to:

- work from the repository root
- accept only a direct `.xcodeproj`, a directory with exactly one immediate `.xcodeproj`, or a direct `Package.resolved`
- choose `doctor`, `report`, or `check-tracking` based on the narrowest user need
- use `--strict-constraints` only when declared-constraint drift should affect failures
- surface the correct exit codes when explaining results

Each skill also includes a local CLI cookbook with ready-to-run command examples, output-format guidance, build/test commands, and installer usage:

- Codex cookbook: [`.agent/skills/spm-dep-tracker-cli/references/cli-cookbook.md`](.agent/skills/spm-dep-tracker-cli/references/cli-cookbook.md)
- Claude cookbook: [`.claude/skills/spm-dep-tracker-cli/references/cli-cookbook.md`](.claude/skills/spm-dep-tracker-cli/references/cli-cookbook.md)

## macOS App

`DependencyTrackerApp` is a local AppKit wrapper around the same core engine.

Current app behavior:

- accepts a project path in the window or via file picker
- runs the same dependency audit as the CLI
- shows findings and dependency rows in split tables
- exports the current report as Markdown or JSON

Build the app:

```bash
make app-build
```

Install only the app with the guided installer:

```bash
./scripts/install_dependency_tracker_app.sh --mode app
```

Install both the app and the CLI:

```bash
./scripts/install_dependency_tracker_app.sh --mode full
```

## Development

Useful local commands:

```bash
make build
make test
make run
make app-build
```

Repository structure:

- `Sources/DependencyTrackerCore/`: audit engine, parsers, analyzers, reporters, and support types
- `Sources/DependencyTrackerCLI/`: ArgumentParser-based CLI commands and formatting glue
- `DependencyTrackerApp/`: AppKit app target and view-model layer
- `.agent/skills/spm-dep-tracker-cli/`: Codex skill and cookbook for repo-local CLI usage
- `.claude/skills/spm-dep-tracker-cli/`: Claude Code skill and cookbook for repo-local CLI usage
- `Tests/`: CLI and core regression tests
- `Formula/`: Homebrew formula used for release packaging
- `docs/`: release notes and maintenance docs

## Release Notes

- Homebrew packaging reference: [Formula/spm-dep-tracker.rb](Formula/spm-dep-tracker.rb)
- Release workflow notes: [docs/release-homebrew.md](docs/release-homebrew.md)
