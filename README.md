# SPMDependencyTracker

SPMDependencyTracker audits the health of Swift Package Manager dependencies for Xcode app projects by inspecting the Xcode-managed `Package.resolved` lock file, its git tracking state, schema compatibility, pin strategy, and available upstream updates.

The repo is split into three deliverables:

- `DependencyTrackerCore`: cross-platform analysis engine and formatters
- `spm-dep-tracker`: CLI entry point for local and CI usage
- `DependencyTrackerApp`: macOS AppKit GUI that consumes the package locally
