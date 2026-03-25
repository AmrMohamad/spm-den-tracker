#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PREPARE_SCRIPT="${REPO_ROOT}/scripts/prepare_homebrew_release.sh"

TAG=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --tag <vX.Y.Z>

Run the local Homebrew release preflight used by the tracked pre-push hook.
The script validates the archive and rendered formula without mutating
repo-tracked files.

Options:
  --tag <vX.Y.Z>   Release tag to validate. Required.
  -h, --help       Show this help text.
EOF
}

fail_usage() {
  printf 'Error: %s\n' "$*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      [[ $# -ge 2 ]] || fail_usage "--tag requires a value"
      TAG="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail_usage "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${TAG}" ]] || fail_usage "--tag is required"
[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail_usage "Tag must look like vX.Y.Z"
[[ -x "${PREPARE_SCRIPT}" ]] || fail_usage "Expected executable prepare script at ${PREPARE_SCRIPT}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Release preflight failed for %s\nReason: required command not found: %s\n' "${TAG}" "$1" >&2
    exit 1
  }
}

require_command git
require_command ruby
require_command tar
require_command mktemp
require_command shasum
require_command lipo

GIT_DIR="$(git -C "${REPO_ROOT}" rev-parse --absolute-git-dir)"
CACHE_DIR="${GIT_DIR}/release-preflight-cache"
LOG_DIR="${CACHE_DIR}/logs"
mkdir -p "${LOG_DIR}"

find "${CACHE_DIR}" -maxdepth 1 -type f -name '*.ok' -mtime +30 -delete >/dev/null 2>&1 || true
find "${LOG_DIR}" -maxdepth 1 -type f -name '*.log' -mtime +30 -delete >/dev/null 2>&1 || true

PEELED_SHA="$(git -C "${REPO_ROOT}" rev-list -n 1 "${TAG}" 2>/dev/null || true)"
if [[ -z "${PEELED_SHA}" ]]; then
  printf 'Release preflight failed for %s\nReason: tag does not resolve locally\n' "${TAG}" >&2
  exit 1
fi

VERSION="${TAG#v}"
SCRIPT_HASH="$(
  cat "${BASH_SOURCE[0]}" "${PREPARE_SCRIPT}" | shasum -a 256 | awk '{print $1}'
)"
CACHE_KEY="${TAG//\//_}--${PEELED_SHA}--${SCRIPT_HASH}"
SUCCESS_MARKER="${CACHE_DIR}/${CACHE_KEY}.ok"
LOG_PATH="${LOG_DIR}/${CACHE_KEY}.log"

if [[ -f "${SUCCESS_MARKER}" ]]; then
  printf 'Release preflight already passed for %s at %s; skipping rebuild.\n' "${TAG}" "${PEELED_SHA}" >&2
  exit 0
fi

TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/spm-dep-tracker-release-preflight.XXXXXX")"
TEMP_FORMULA="${TEMP_ROOT}/spm-dep-tracker.rb"
TEMP_OUTPUT_DIR="${TEMP_ROOT}/dist"
EXTRACT_DIR="${TEMP_ROOT}/extract"

cleanup() {
  rm -rf "${TEMP_ROOT}"
}
trap cleanup EXIT

: > "${LOG_PATH}"

log() {
  printf '%s\n' "$*" >> "${LOG_PATH}"
}

fail_preflight() {
  local reason="$1"
  printf 'Release preflight failed for %s\n' "${TAG}" >&2
  printf 'Reason: %s\n' "${reason}" >&2
  printf 'Log: %s\n' "${LOG_PATH}" >&2
  exit 1
}

run_step() {
  local description="$1"
  shift
  log "==> ${description}"
  if ! "$@" >> "${LOG_PATH}" 2>&1; then
    fail_preflight "${description}"
  fi
}

run_step "rendering Homebrew release inputs" \
  bash "${PREPARE_SCRIPT}" \
    --version "${VERSION}" \
    --formula-out "${TEMP_FORMULA}" \
    --output-dir "${TEMP_OUTPUT_DIR}"

run_step "validating rendered formula syntax" ruby -c "${TEMP_FORMULA}"

ARCHIVE_PATH="${TEMP_OUTPUT_DIR}/v${VERSION}/spm-dep-tracker-macos.tar.gz"
[[ -f "${ARCHIVE_PATH}" ]] || fail_preflight "expected archive missing at ${ARCHIVE_PATH}"

ARCHIVE_LISTING="$(tar -tzf "${ARCHIVE_PATH}" 2>> "${LOG_PATH}" || true)"
if [[ "${ARCHIVE_LISTING}" != "spm-dep-tracker" ]]; then
  fail_preflight "archive layout is unexpected; expected only spm-dep-tracker"
fi

run_step "extracting release archive" mkdir -p "${EXTRACT_DIR}"
run_step "unpacking release archive" tar -xzf "${ARCHIVE_PATH}" -C "${EXTRACT_DIR}"

BINARY_PATH="${EXTRACT_DIR}/spm-dep-tracker"
[[ -x "${BINARY_PATH}" ]] || fail_preflight "expected executable missing at ${BINARY_PATH}"

ARCHS="$(lipo -archs "${BINARY_PATH}" 2>> "${LOG_PATH}" || true)"
if [[ " ${ARCHS} " != *" arm64 "* ]] || [[ " ${ARCHS} " != *" x86_64 "* ]]; then
  fail_preflight "binary is not universal (found: ${ARCHS:-unknown}; expected arm64 and x86_64)"
fi

run_step "running archived binary help" "${BINARY_PATH}" --help

printf 'tag=%s\npeeled_sha=%s\nvalidated_at=%s\n' \
  "${TAG}" \
  "${PEELED_SHA}" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${SUCCESS_MARKER}"

rm -f "${LOG_PATH}"
printf 'Release preflight passed for %s\n' "${TAG}" >&2
