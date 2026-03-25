# Homebrew Core Readiness

`brew install spm-dep-tracker` for first-time users is only possible after the
formula is accepted into `homebrew/core`.

This document tracks the upstream work needed before that submission is credible.

## Current State

- The project is macOS-only in `Package.swift`.
- The upstream repo only recently gained release automation.
- The install story is currently better suited to a dedicated custom tap than to
  immediate `homebrew/core` submission.

## Required Readiness Items

- Stable semantic version tags and repeatable releases.
- A top-level `LICENSE` file.
- A clear homepage and maintainable public docs.
- A source-build-friendly formula path from a tagged release.
- Reliable CLI-only build/test behavior across supported macOS architectures.
- An explicit platform story for Linux and non-macOS environments.

## Recommended Order

1. Ship the dedicated tap flow successfully.
2. Ship at least one stable tagged release through that path.
3. Keep release assets and formula updates immutable and reproducible.
4. Evaluate whether the project has enough adoption and maintenance maturity to
   justify `homebrew/core`.

## Non-Goals For Now

- Packaging `DependencyTrackerApp` for Homebrew.
- Promising `homebrew/core` acceptance on a fixed timeline.
