# Story 07: Release and Documentation

Branch: `codex/feature/v0.2.0-release-docs`

## Objective

Align the public docs and maintainer-facing release surface with the workspace-aware `0.2.0` release while preserving the existing `0.2.0` version and `v0.2.0` tag contract.

## Owned Files

- `README.md`
- `docs/release-homebrew.md`
- `docs/homebrew-core-readiness.md`
- `docs/releases/0.2.0.md`

## Decisions

- Use `0.2.0` as the semantic version and `v0.2.0` as the git tag.
- Document repo-root analysis, analysis modes, aggregate workspace output, graph command behavior, and graph certainty language.
- Keep semver/tag examples aligned with the current release scripts.
- Do not introduce `0.2.0v`.

## Deliverables

- README examples for repo-root inputs, mode overrides, graph command, and aggregate outputs.
- Release docs updated to use `0.2.0` examples and `v0.2.0` tag examples.
- A release note file for `0.2.0`.
- A short note explaining provenance and why `Package.resolved` proves resolved pins but not direct declaration provenance by itself.

## Rules

- No code changes outside documentation files.
- Be explicit about what is new in `0.2.0` and what remains compatible.
- Do not claim graph certainty beyond what the implementation can prove.

## Verification

- `rg -n "0\\.2\\.0v" README.md docs/release-homebrew.md docs/homebrew-core-readiness.md docs/releases/0.2.0.md`
- Manual review of README and release docs against the current release scripts
