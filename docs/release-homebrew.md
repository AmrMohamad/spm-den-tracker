# Homebrew Release Notes

The end-user target for this project is:

```bash
brew install AmrMohamad/spm-den-tracker/spm-dep-tracker
```

That command is only valid once the dedicated tap repo
`AmrMohamad/homebrew-spm-den-tracker` has a stable `Formula/spm-dep-tracker.rb`
with a release-backed `url` and `sha256`.
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

## One-Time Local Setup

If you want automatic local release preflight from the terminal or Fork, run this once per clone:

```bash
make setup-hooks
```

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

If you push the tag from Fork instead of the terminal, the same tracked `pre-push`
hook runs first as long as you have already run `make setup-hooks`.
The hook:

- validates the release archive and rendered formula using temporary paths only
- blocks the push with a concise error summary when validation fails
- caches successful validations under `.git/release-preflight-cache/` so re-pushing the same tag after a network hiccup does not rebuild everything

Creating the tag locally does not trigger anything by itself; the local
automation boundary is the tag push.

3. Let the tag workflow create the GitHub release asset and sync the dedicated tap repo using the `HOMEBREW_TAP_TOKEN` secret.

4. If you need to recover or backfill the dedicated tap manually after the release asset exists:

```bash
./scripts/sync_homebrew_tap.sh --version 0.1.0
```

This recovery path requires:

- the GitHub release asset for `v0.1.0` to already exist
- authenticated `gh` access
- a token with write access to `AmrMohamad/homebrew-spm-den-tracker`; for a fine-grained PAT, grant `Contents: Read and write`
- push permission to `AmrMohamad/homebrew-spm-den-tracker`
- the script configures git HTTPS auth from the active `gh` credentials before it clones or pushes the tap repo

5. Verify the public install path:

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

One-time Fork smoke test:

1. Run `make setup-hooks`
2. Push a test tag from Fork
3. Confirm Fork surfaces the hook output before the push completes

If you need to bypass the local preflight in an emergency:

```bash
git push --no-verify origin v0.1.0
SPM_DEP_TRACKER_SKIP_TAG_PREFLIGHT=1 git push origin v0.1.0
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
