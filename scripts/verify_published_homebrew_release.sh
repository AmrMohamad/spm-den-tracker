#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=""
SOURCE_OWNER="AmrMohamad"
SOURCE_REPO="spm-den-tracker"
TAP_OWNER="AmrMohamad"
TAP_REPO="homebrew-spm-den-tracker"
ARCHIVE_NAME="spm-dep-tracker-macos.tar.gz"
METADATA_NAME="spm-dep-tracker-release-metadata.json"
BREW_INSTALL_CANARY=0
WORK_DIR=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --version <x.y.z> [options]

Verify that the published Homebrew formula, release asset, and optional public
brew install path are all consistent for a released version.

Options:
  --version <x.y.z>         Stable version to verify. Required.
  --source-owner <name>     Source repo owner. Default: ${SOURCE_OWNER}
  --source-repo <name>      Source repo name. Default: ${SOURCE_REPO}
  --tap-owner <name>        Tap repo owner. Default: ${TAP_OWNER}
  --tap-repo <name>         Tap repo name. Default: ${TAP_REPO}
  --archive-name <name>     Release archive name. Default: ${ARCHIVE_NAME}
  --brew-install-canary     Run brew install and brew test against the public tap path.
  -h, --help                Show this help text.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

retry_command() {
  local attempts="$1"
  local delay_seconds="$2"
  local description="$3"
  shift 3

  local attempt
  for attempt in $(seq 1 "${attempts}"); do
    if "$@"; then
      return 0
    fi

    if [[ "${attempt}" -eq "${attempts}" ]]; then
      break
    fi

    printf 'Retrying %s (%s/%s) after %ss...\n' "${description}" "${attempt}" "${attempts}" "${delay_seconds}" >&2
    sleep "${delay_seconds}"
  done

  fail "${description} failed after ${attempts} attempts."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

cleanup() {
  [[ -n "${WORK_DIR}" ]] || return 0

  if [[ "${BREW_INSTALL_CANARY}" -eq 1 ]]; then
    brew uninstall --force "${SOURCE_OWNER}/${SOURCE_REPO}/spm-dep-tracker" >/dev/null 2>&1 || true
    brew untap "${SOURCE_OWNER}/${SOURCE_REPO}" >/dev/null 2>&1 || true
  fi

  rm -rf "${WORK_DIR}"
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || fail "--version requires a value"
      VERSION="$2"
      shift 2
      ;;
    --source-owner)
      [[ $# -ge 2 ]] || fail "--source-owner requires a value"
      SOURCE_OWNER="$2"
      shift 2
      ;;
    --source-repo)
      [[ $# -ge 2 ]] || fail "--source-repo requires a value"
      SOURCE_REPO="$2"
      shift 2
      ;;
    --tap-owner)
      [[ $# -ge 2 ]] || fail "--tap-owner requires a value"
      TAP_OWNER="$2"
      shift 2
      ;;
    --tap-repo)
      [[ $# -ge 2 ]] || fail "--tap-repo requires a value"
      TAP_REPO="$2"
      shift 2
      ;;
    --archive-name)
      [[ $# -ge 2 ]] || fail "--archive-name requires a value"
      ARCHIVE_NAME="$2"
      shift 2
      ;;
    --brew-install-canary)
      BREW_INSTALL_CANARY=1
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

[[ -n "${VERSION}" ]] || fail "--version is required"
[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version must look like x.y.z"

require_command gh
require_command curl
require_command tar
require_command shasum
require_command ruby
require_command mktemp
if [[ "${BREW_INSTALL_CANARY}" -eq 1 ]]; then
  require_command brew
  [[ "${CI:-}" == "true" ]] || fail "--brew-install-canary is intended for CI runners because it temporarily untaps and uninstalls spm-dep-tracker."
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spm-dep-tracker-release-verify.XXXXXX")"
FORMULA_PATH="${WORK_DIR}/spm-dep-tracker.rb"
ARCHIVE_PATH="${WORK_DIR}/${ARCHIVE_NAME}"
EXTRACT_DIR="${WORK_DIR}/extract"
METADATA_PATH="${WORK_DIR}/${METADATA_NAME}"

retry_command 5 5 "fetching published tap formula" \
  bash -lc "gh api 'repos/${TAP_OWNER}/${TAP_REPO}/contents/Formula/spm-dep-tracker.rb' --jq .content | tr -d '\n' | base64 --decode > '${FORMULA_PATH}'"

eval "$(
  ruby -r shellwords - <<'RUBY' "${FORMULA_PATH}"
content = File.read(ARGV[0])
fields = {
  "FORMULA_URL" => content[/^\s*url "(.*?)"/, 1],
  "FORMULA_SHA256" => content[/^\s*sha256 "(.*?)"/, 1],
  "FORMULA_VERSION" => content[/^\s*version "(.*?)"/, 1],
}
missing = fields.select { |_, value| value.nil? }.keys
abort("Missing formula fields: #{missing.join(', ')}") unless missing.empty?
fields.each do |key, value|
  puts("#{key}=#{Shellwords.escape(value)}")
end
RUBY
)"

EXPECTED_URL="https://github.com/${SOURCE_OWNER}/${SOURCE_REPO}/releases/download/v${VERSION}/${ARCHIVE_NAME}"
[[ "${FORMULA_VERSION}" == "${VERSION}" ]] || fail "Tap formula version ${FORMULA_VERSION} does not match expected version ${VERSION}."
[[ "${FORMULA_URL}" == "${EXPECTED_URL}" ]] || fail "Tap formula URL ${FORMULA_URL} does not match expected release URL ${EXPECTED_URL}."

ASSET_NAMES="$(gh release view "v${VERSION}" --repo "${SOURCE_OWNER}/${SOURCE_REPO}" --json assets --jq '.assets[].name')"
printf '%s\n' "${ASSET_NAMES}" | grep -Fx "${ARCHIVE_NAME}" >/dev/null \
  || fail "Published release v${VERSION} is missing asset ${ARCHIVE_NAME}."

if printf '%s\n' "${ASSET_NAMES}" | grep -Fx "${METADATA_NAME}" >/dev/null; then
  gh release download "v${VERSION}" \
    --repo "${SOURCE_OWNER}/${SOURCE_REPO}" \
    --pattern "${METADATA_NAME}" \
    --dir "${WORK_DIR}" \
    --clobber
fi

retry_command 5 5 "downloading published archive" \
  curl -fsSL "${FORMULA_URL}" -o "${ARCHIVE_PATH}"

ARCHIVE_SHA="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{print $1}')"
[[ "${ARCHIVE_SHA}" == "${FORMULA_SHA256}" ]] \
  || fail "Published archive checksum ${ARCHIVE_SHA} does not match tap formula checksum ${FORMULA_SHA256}."

tar -tzf "${ARCHIVE_PATH}" | grep -Fx "spm-dep-tracker" >/dev/null \
  || fail "Published archive layout is invalid; expected only spm-dep-tracker."
mkdir -p "${EXTRACT_DIR}"
tar -xzf "${ARCHIVE_PATH}" -C "${EXTRACT_DIR}"

PUBLISHED_BINARY_SHA="$(shasum -a 256 "${EXTRACT_DIR}/spm-dep-tracker" | awk '{print $1}')"
"${EXTRACT_DIR}/spm-dep-tracker" --help >/dev/null

if [[ -f "${METADATA_PATH}" ]]; then
  eval "$(
    ruby -r json -r shellwords - <<'RUBY' "${METADATA_PATH}"
payload = JSON.parse(File.read(ARGV[0]))
fields = {
  "METADATA_TAG" => payload["tag"],
  "METADATA_TAG_COMMIT_SHA" => payload["tag_commit_sha"],
  "METADATA_BINARY_SHA256" => payload["binary_sha256"],
  "METADATA_ARCHIVE_NAME" => payload["archive_name"],
}
missing = fields.select { |_, value| value.nil? }.keys
abort("Missing release metadata fields: #{missing.join(', ')}") unless missing.empty?
fields.each do |key, value|
  puts("#{key}=#{Shellwords.escape(value)}")
end
RUBY
  )"

  [[ "${METADATA_TAG}" == "v${VERSION}" ]] || fail "Release metadata tag ${METADATA_TAG} does not match v${VERSION}."
  [[ "${METADATA_ARCHIVE_NAME}" == "${ARCHIVE_NAME}" ]] || fail "Release metadata archive ${METADATA_ARCHIVE_NAME} does not match ${ARCHIVE_NAME}."
  [[ "${METADATA_BINARY_SHA256}" == "${PUBLISHED_BINARY_SHA}" ]] \
    || fail "Release metadata binary checksum ${METADATA_BINARY_SHA256} does not match published binary checksum ${PUBLISHED_BINARY_SHA}."
fi

if [[ "${BREW_INSTALL_CANARY}" -eq 1 ]]; then
  export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"
  brew untap "${SOURCE_OWNER}/${SOURCE_REPO}" >/dev/null 2>&1 || true
  brew uninstall --force "${SOURCE_OWNER}/${SOURCE_REPO}/spm-dep-tracker" >/dev/null 2>&1 || true
  retry_command 3 10 "running brew install canary" \
    brew install "${SOURCE_OWNER}/${SOURCE_REPO}/spm-dep-tracker"
  brew test "${SOURCE_OWNER}/${SOURCE_REPO}/spm-dep-tracker"
fi

printf 'Published Homebrew release v%s passed integrity verification.\n' "${VERSION}"
