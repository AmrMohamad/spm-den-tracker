# Story 06: AppKit Workspace and Graph UI

Branch: `codex/feature/v0.2.0-appkit-graph-ui`

## Objective

Teach the macOS app to present aggregate workspace state, per-context details, and rendered Mermaid graphs.

## Owned Files

- `DependencyTrackerApp/DependencyTrackerApp/**`
- `DependencyTrackerApp/DependencyTrackerAppTests/TrackerViewModelTests.swift`
- `DependencyTrackerApp/DependencyTrackerApp.xcodeproj/project.pbxproj`
- `DependencyTrackerApp/DependencyTrackerApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

## Deliverables

- Service and view-model support for aggregate analysis results.
- Workspace overview state, context selection, and selected-context findings/dependencies presentation.
- Graph tab that renders Mermaid output via an app-only dependency.
- Export support for Markdown, JSON, and Mermaid text.
- Tests for state transitions, selection behavior, stale task protection, and export results.

## Rules

- Core and CLI stay free of the renderer dependency.
- Keep the app readable on small windows; summary and selection come before detail.
- Do not redesign the whole app; extend the existing flow.

## Verification

- App target build
- `swift test`
