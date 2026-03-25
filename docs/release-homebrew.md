# Homebrew Release Notes

The end-user target for this repository is:

```bash
brew install AmrMohamad/spm-den-tracker/spm-dep-tracker
```

That command is only valid once `Formula/spm-dep-tracker.rb` has a stable `url` and `sha256`.
Homebrew rejects plain installs for `HEAD`-only formulae, and first-time
installation of `AmrMohamad/spm-den-tracker/spm-dep-tracker` requires a
dedicated tap repo named `AmrMohamad/homebrew-spm-den-tracker`.

## Recommended Release Shape

- keep this repository as the source repo and release artifact owner
- publish the public formula from the dedicated tap repo `AmrMohamad/homebrew-spm-den-tracker`
- ship a stable GitHub release asset for the CLI as one universal macOS binary
- keep a `head` stanza in the formula for maintainer-only installs and validation
- validate the formula in CI using a temporary local tap before publishing or syncing it
- treat release assets as immutable for a given version; reruns must fail instead of overwriting the published archive

This repo already includes that CI check in [homebrew-validate.yml](../.github/workflows/homebrew-validate.yml).
The tag-driven release path is implemented in [release-homebrew.yml](../.github/workflows/release-homebrew.yml).

The PR validation workflow intentionally treats `HEAD` formulas differently from stable formulas:

- stable formulas are installed and tested through a temporary local tap
- `HEAD` formulas are syntax-checked only on GitHub-hosted runners because the current runner toolchain (`Swift 6.2.3` on `Xcode 26.2`) fails inside `swift-argument-parser`, which would make maintainer-only `HEAD` validation an unreliable merge blocker

## Maintainer Flow

1. Prepare the release artifact and render the tap formula:

```bash
./scripts/prepare_homebrew_release.sh --version 0.1.0 --formula-out /tmp/spm-dep-tracker.rb
```

This script:

- builds the release CLI as a universal `arm64` + `x86_64` binary unless `--skip-build` is passed
- creates `dist/homebrew/v<version>/spm-dep-tracker-macos.tar.gz`
- computes the SHA-256 checksum
- renders a stable formula with both:
  - a release-backed install path for the dedicated tap repo
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

4. Let the release workflow sync the dedicated tap repo using the `HOMEBREW_TAP_TOKEN` secret.

5. If you need to recover or backfill the dedicated tap manually after the release asset exists:

```bash
./scripts/sync_homebrew_tap.sh --version 0.1.0
```

6. Verify the public install path:

```bash
brew install AmrMohamad/spm-den-tracker/spm-dep-tracker
brew test AmrMohamad/spm-den-tracker/spm-dep-tracker
```

## Validation

Local validation before pushing:

```bash
ruby -c Formula/spm-dep-tracker.rb
bash scripts/prepare_homebrew_release.sh --version 0.1.0 --formula-out /tmp/spm-dep-tracker.rb --output-dir /tmp/homebrew
ruby -c /tmp/spm-dep-tracker.rb
```

For `HEAD` validation, use the same temporary tap strategy as CI:

```bash
brew install --HEAD AmrMohamad/spm-den-tracker/spm-dep-tracker
brew test AmrMohamad/spm-den-tracker/spm-dep-tracker
```

For stable-release validation, the tag workflow validates all of these before publishing the release asset or syncing the dedicated tap repo:

- archive layout contains only the expected `spm-dep-tracker` binary
- the archived binary is universal (`arm64` + `x86_64`)
- the archived binary launches with `--help`
- a synthetic stable formula that points at the locally built archive installs and passes `brew test`
- the dedicated tap sync path renders a formula from the published release checksum rather than from a local build, so reruns and manual recovery use the immutable release asset

## Scope

- the formula installs the CLI only
- `DependencyTrackerApp` stays on the guided installer path
- if the app eventually needs Homebrew distribution, ship it separately as a cask
