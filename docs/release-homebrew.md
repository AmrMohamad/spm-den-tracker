# Homebrew Release Notes

The end-user target for this repository is:

```bash
brew install AmrMohamad/spm-den-tracker/spm-dep-tracker
```

That command is only valid once `Formula/spm-dep-tracker.rb` has a stable `url` and `sha256`.
Homebrew rejects plain installs for `HEAD`-only formulae.

## Recommended Release Shape

- keep the formula in this repository's `Formula/` directory so the repo acts as the tap
- ship a stable GitHub release asset for the CLI
- keep a `head` stanza in the formula for maintainer-only installs and validation
- validate the formula in CI using a temporary local tap before merging changes

This repo already includes that CI check in [homebrew-validate.yml](/Users/amrmohamad/Developer/spm-den-tracker/.github/workflows/homebrew-validate.yml).
The tag-driven release path is implemented in [release-homebrew.yml](/Users/amrmohamad/Developer/spm-den-tracker/.github/workflows/release-homebrew.yml).

## Maintainer Flow

1. Prepare the release artifact and rewrite the formula:

```bash
./scripts/prepare_homebrew_release.sh --version 0.1.0
```

This script:

- builds the release CLI unless `--skip-build` is passed
- creates `dist/homebrew/v<version>/spm-dep-tracker-macos.tar.gz`
- computes the SHA-256 checksum
- rewrites `Formula/spm-dep-tracker.rb` to include both:
  - a stable release-backed install path
  - a `head` install path for maintainers

2. Create and push the release tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

3. Create a GitHub release for `v0.1.0` and upload:

```bash
dist/homebrew/v0.1.0/spm-dep-tracker-macos.tar.gz
```

4. Let the release workflow open the stabilization PR for the rewritten formula.

5. Verify the public install path:

```bash
brew install AmrMohamad/spm-den-tracker/spm-dep-tracker
brew test AmrMohamad/spm-den-tracker/spm-dep-tracker
```

## Validation

Local validation before pushing:

```bash
ruby -c Formula/spm-dep-tracker.rb
```

For `HEAD` validation, use the same temporary tap strategy as CI:

```bash
brew install --HEAD AmrMohamad/spm-den-tracker/spm-dep-tracker
brew test AmrMohamad/spm-den-tracker/spm-dep-tracker
```

## Scope

- the formula installs the CLI only
- `DependencyTrackerApp` stays on the guided installer path
- if the app eventually needs Homebrew distribution, ship it separately as a cask
