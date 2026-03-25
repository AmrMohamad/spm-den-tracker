#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=""
OWNER="AmrMohamad"
REPO_NAME="spm-den-tracker"
OUTPUT_DIR="${REPO_ROOT}/dist/homebrew"
ARCHIVE_NAME="spm-dep-tracker-macos.tar.gz"
DRY_RUN=0
SKIP_BUILD=0

usage() {
  cat <<EOF
Usage: $(basename "$0") --version <x.y.z> [options]

Prepare a stable Homebrew release artifact and rewrite Formula/spm-dep-tracker.rb
for a tagged GitHub release, while preserving HEAD installs for maintainers.

Options:
  --version <x.y.z>       Stable version to publish. Required.
  --owner <name>          GitHub owner. Default: ${OWNER}
  --repo <name>           GitHub repository name. Default: ${REPO_NAME}
  --output-dir <path>     Directory where the release archive will be written.
                          Default: ${OUTPUT_DIR}
  --archive-name <name>   Archive filename. Default: ${ARCHIVE_NAME}
  --skip-build            Reuse an existing .build/release/spm-dep-tracker binary.
  --dry-run               Print the planned work without mutating files.
  -h, --help              Show this help text.

Examples:
  $(basename "$0") --version 0.1.0
  $(basename "$0") --version 0.1.0 --owner AmrMohamad --repo spm-den-tracker
  $(basename "$0") --version 0.1.0 --dry-run
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '%s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

run() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '[dry-run] %q' "$1"
    shift || true
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
    return 0
  fi
  "$@"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || fail "--version requires a value"
        VERSION="$2"
        shift 2
        ;;
      --owner)
        [[ $# -ge 2 ]] || fail "--owner requires a value"
        OWNER="$2"
        shift 2
        ;;
      --repo)
        [[ $# -ge 2 ]] || fail "--repo requires a value"
        REPO_NAME="$2"
        shift 2
        ;;
      --output-dir)
        [[ $# -ge 2 ]] || fail "--output-dir requires a value"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --archive-name)
        [[ $# -ge 2 ]] || fail "--archive-name requires a value"
        ARCHIVE_NAME="$2"
        shift 2
        ;;
      --skip-build)
        SKIP_BUILD=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done
}

validate_inputs() {
  [[ -n "${VERSION}" ]] || fail "--version is required"
  [[ "${VERSION}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || fail "Version must look like x.y or x.y.z"
}

build_cli_if_needed() {
  if [[ "${SKIP_BUILD}" -eq 1 ]]; then
    return 0
  fi

  require_command swift
  log "Building release CLI..."
  run swift build -c release --product spm-dep-tracker --package-path "${REPO_ROOT}"
}

archive_cli() {
  local archive_path="$1"
  local built_binary="${REPO_ROOT}/.build/release/spm-dep-tracker"

  if [[ "${DRY_RUN}" -ne 1 && ! -x "${built_binary}" ]]; then
    fail "Release binary not found at ${built_binary}"
  fi

  run mkdir -p "$(dirname "${archive_path}")"
  run tar -C "${REPO_ROOT}/.build/release" -czf "${archive_path}" spm-dep-tracker
}

compute_sha() {
  local archive_path="$1"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '%s\n' "DRY_RUN_SHA256"
    return 0
  fi

  shasum -a 256 "${archive_path}" | awk '{print $1}'
}

write_formula() {
  local version="$1"
  local owner="$2"
  local repo="$3"
  local archive_name="$4"
  local sha="$5"
  local formula_path="${REPO_ROOT}/Formula/spm-dep-tracker.rb"

  local homepage="https://github.com/${owner}/${repo}"
  local release_url="${homepage}/releases/download/v${version}/${archive_name}"
  local head_url="${homepage}.git"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    cat <<EOF
[dry-run] Would rewrite ${formula_path} with:
  stable url: ${release_url}
  stable sha: ${sha}
  install path: brew install ${owner}/${repo}/spm-dep-tracker
EOF
    return 0
  fi

  cat > "${formula_path}" <<EOF
class SpmDepTracker < Formula
  desc "Audit Swift Package Manager lockfiles, pinning strategy, schema, and update drift"
  homepage "${homepage}"
  url "${release_url}"
  sha256 "${sha}"
  version "${version}"
  head "${head_url}", branch: "main"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma

  def install
    if build.head?
      system "swift", "build",
        "--configuration", "release",
        "--product", "spm-dep-tracker",
        "--disable-sandbox"

      bin.install ".build/release/spm-dep-tracker"
    else
      bin.install "spm-dep-tracker"
    end
  end

  test do
    assert_match "Inspect Xcode-managed Swift Package dependencies", shell_output("#{bin}/spm-dep-tracker --help")
  end
end
EOF
}

print_next_steps() {
  local version="$1"
  local owner="$2"
  local repo="$3"
  local archive_path="$4"
  local sha="$5"

  log
  log "Prepared Homebrew release inputs."
  log "  Version: ${version}"
  log "  Archive: ${archive_path}"
  log "  SHA256: ${sha}"
  log
  log "Next steps:"
  log "  1. Create and push tag v${version}."
  log "  2. Create a GitHub release for v${version}."
  log "  3. Upload $(basename "${archive_path}") to that release."
  log "  4. Commit the rewritten Formula/spm-dep-tracker.rb."
  log "  5. Users install with: brew install ${owner}/${repo}/spm-dep-tracker"
}

main() {
  parse_args "$@"
  validate_inputs

  local archive_path="${OUTPUT_DIR}/v${VERSION}/${ARCHIVE_NAME}"

  build_cli_if_needed
  archive_cli "${archive_path}"

  local sha
  sha="$(compute_sha "${archive_path}")"

  write_formula "${VERSION}" "${OWNER}" "${REPO_NAME}" "${ARCHIVE_NAME}" "${sha}"
  print_next_steps "${VERSION}" "${OWNER}" "${REPO_NAME}" "${archive_path}" "${sha}"
}

main "$@"
