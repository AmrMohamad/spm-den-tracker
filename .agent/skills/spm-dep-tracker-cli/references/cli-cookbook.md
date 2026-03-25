# CLI Cookbook

## Fast Commands

Use these from the repository root:

```bash
swift run spm-dep-tracker doctor "/path/to/MyApp.xcodeproj"
swift run spm-dep-tracker report "/path/to/MyApp.xcodeproj" --format markdown
swift run spm-dep-tracker report "/path/to/MyApp.xcodeproj" --format json --output ./Reports/dependencies.json
swift run spm-dep-tracker report "/path/to/MyApp.xcodeproj" --format xcode
swift run spm-dep-tracker report "/path/to/MyApp.xcodeproj" --format junit --strict-constraints
swift run spm-dep-tracker check-tracking "/path/to/MyApp.xcodeproj"
```

## Input Rules

Accept exactly these forms:

- direct `.xcodeproj` path
- directory containing exactly one immediate `.xcodeproj`
- direct `Package.resolved` path

Treat a directory with multiple immediate `.xcodeproj` bundles as ambiguous and require an explicit project path.

## Output Formats

- `table`: aligned terminal summary
- `markdown`: shareable PR or engineering-note report
- `json`: machine-readable export
- `xcode`: compiler-style diagnostics for CI logs
- `junit`: XML suite for CI ingestion

## Exit Codes

### `doctor`

- `0`: informational findings only
- `1`: warnings or errors found
- `65`: input path invalid

### `report`

- `0`: informational findings only
- `1`: warnings or errors found
- `65`: input path invalid

### `check-tracking`

- `0`: `Package.resolved` is tracked by git
- `2`: `Package.resolved` is missing, untracked, or gitignored
- `65`: input path invalid

## Build and Test

```bash
swift build
swift test
swift run spm-dep-tracker --help
make build
make test
make run
```

For repeated invocations, build a release binary and run it directly:

```bash
swift build -c release --product spm-dep-tracker
.build/release/spm-dep-tracker doctor "/path/to/MyApp.xcodeproj"
```

## Installation

Install the CLI only:

```bash
./scripts/install_dependency_tracker_app.sh --mode cli
```

Install both the CLI and the macOS app:

```bash
./scripts/install_dependency_tracker_app.sh --mode full
```

Useful installer variants:

```bash
./scripts/install_dependency_tracker_app.sh --mode full --cli-bin-dir "$HOME/.local/bin"
./scripts/install_dependency_tracker_app.sh --mode app --app-path "/Applications/DependencyTrackerApp.app"
./scripts/install_dependency_tracker_app.sh --mode full --non-interactive --dry-run
```

Installer defaults worth remembering:

- CLI destination defaults to a user-owned bin dir, typically `~/.local/bin`
- App destination defaults to `/Applications/DependencyTrackerApp.app`
- Existing installs are not overwritten without confirmation unless `--force` is passed

## Environment

- macOS 14 or newer
- Swift 6.2 toolchain
- Xcode required for AppKit app builds
