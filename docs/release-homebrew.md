# Homebrew Release Notes

This repo ships a lightweight Homebrew formula template for the CLI.

## Release Steps

1. Build the release binary:

```bash
swift build -c release --product spm-dep-tracker
```

2. Archive the binary:

```bash
tar -C .build/release -czf spm-dep-tracker-macos.tar.gz spm-dep-tracker
```

3. Generate the checksum:

```bash
shasum -a 256 spm-dep-tracker-macos.tar.gz
```

4. Create a GitHub release and upload `spm-dep-tracker-macos.tar.gz`.
5. Update `Formula/spm-dep-tracker.rb`:
   - replace the release tag in `url`
   - replace `<REPLACE_WITH_RELEASE_SHA256>` with the archive checksum
   - replace `<org>` with the real GitHub owner

## Notes

- This formula installs the CLI only.
- The macOS app remains a separate build/install path.
- CI release automation is intentionally out of scope for now.
