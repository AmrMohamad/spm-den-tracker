#!/usr/bin/env bash

set -euo pipefail

VERSION=""
SOURCE_OWNER="AmrMohamad"
SOURCE_REPO="spm-den-tracker"
ARCHIVE_PATH=""
ARCHIVE_NAME="spm-dep-tracker-macos.tar.gz"
METADATA_PATH=""
METADATA_NAME="spm-dep-tracker-release-metadata.json"

usage() {
  cat <<EOF
Usage: $(basename "$0") --version <x.y.z> --archive-path <path> --metadata-path <path> [options]

Create or reconcile immutable Homebrew release assets for a tagged version.

Options:
  --version <x.y.z>         Stable version to publish. Required.
  --source-owner <name>     Source repo owner. Default: ${SOURCE_OWNER}
  --source-repo <name>      Source repo name. Default: ${SOURCE_REPO}
  --archive-path <path>     Path to the built release archive. Required.
  --archive-name <name>     Release archive name. Default: ${ARCHIVE_NAME}
  --metadata-path <path>    Path where release metadata should be written. Required.
  --metadata-name <name>    Release metadata asset name. Default: ${METADATA_NAME}
  -h, --help                Show this help text.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

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
    --archive-path)
      [[ $# -ge 2 ]] || fail "--archive-path requires a value"
      ARCHIVE_PATH="$2"
      shift 2
      ;;
    --archive-name)
      [[ $# -ge 2 ]] || fail "--archive-name requires a value"
      ARCHIVE_NAME="$2"
      shift 2
      ;;
    --metadata-path)
      [[ $# -ge 2 ]] || fail "--metadata-path requires a value"
      METADATA_PATH="$2"
      shift 2
      ;;
    --metadata-name)
      [[ $# -ge 2 ]] || fail "--metadata-name requires a value"
      METADATA_NAME="$2"
      shift 2
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
[[ -n "${ARCHIVE_PATH}" ]] || fail "--archive-path is required"
[[ -f "${ARCHIVE_PATH}" ]] || fail "Expected archive missing at ${ARCHIVE_PATH}"
[[ -n "${METADATA_PATH}" ]] || fail "--metadata-path is required"

require_command gh
require_command git
require_command tar
require_command shasum
require_command python3
require_command mktemp

TAG="v${VERSION}"

extract_binary_sha() {
  local archive_path="$1"
  local extract_dir

  extract_dir="$(mktemp -d)"
  tar -tzf "${archive_path}" | grep -Fx "spm-dep-tracker" >/dev/null \
    || fail "Archive layout is invalid for ${archive_path}; expected only spm-dep-tracker."
  tar -xzf "${archive_path}" -C "${extract_dir}"
  shasum -a 256 "${extract_dir}/spm-dep-tracker" | awk '{print $1}'
  rm -rf "${extract_dir}"
}

read_metadata_field() {
  local metadata_path="$1"
  local field="$2"

  python3 - <<'PY' "${metadata_path}" "${field}"
import json
import sys

metadata_path, field = sys.argv[1:]
with open(metadata_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

value = data.get(field)
if value is None:
    raise SystemExit(1)

print(value)
PY
}

TAG_COMMIT="$(git rev-list -n 1 "${TAG}" 2>/dev/null || true)"
[[ -n "${TAG_COMMIT}" ]] || fail "Tag ${TAG} does not resolve in the current checkout."
LOCAL_BINARY_SHA="$(extract_binary_sha "${ARCHIVE_PATH}")"

python3 - <<'PY' "${METADATA_PATH}" "${TAG}" "${TAG_COMMIT}" "${LOCAL_BINARY_SHA}" "${ARCHIVE_NAME}"
import json
import sys
from pathlib import Path

metadata_path, tag, tag_commit_sha, binary_sha256, archive_name = sys.argv[1:]
payload = {
    "tag": tag,
    "tag_commit_sha": tag_commit_sha,
    "binary_sha256": binary_sha256,
    "archive_name": archive_name,
}
path = Path(metadata_path)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

if gh release view "${TAG}" --repo "${SOURCE_OWNER}/${SOURCE_REPO}" >/dev/null 2>&1; then
  ASSET_NAMES="$(gh release view "${TAG}" --repo "${SOURCE_OWNER}/${SOURCE_REPO}" --json assets --jq '.assets[].name')"
  ARCHIVE_PRESENT=0
  METADATA_PRESENT=0

  if printf '%s\n' "${ASSET_NAMES}" | grep -Fx "${ARCHIVE_NAME}" >/dev/null; then
    ARCHIVE_PRESENT=1
  fi

  if printf '%s\n' "${ASSET_NAMES}" | grep -Fx "${METADATA_NAME}" >/dev/null; then
    METADATA_PRESENT=1
    DOWNLOAD_DIR="$(mktemp -d)"
    gh release download "${TAG}" \
      --repo "${SOURCE_OWNER}/${SOURCE_REPO}" \
      --pattern "${METADATA_NAME}" \
      --dir "${DOWNLOAD_DIR}" \
      --clobber

    PUBLISHED_TAG_COMMIT="$(read_metadata_field "${DOWNLOAD_DIR}/${METADATA_NAME}" tag_commit_sha)"
    [[ "${PUBLISHED_TAG_COMMIT}" == "${TAG_COMMIT}" ]] || {
      fail "Release ${TAG} was already published from commit ${PUBLISHED_TAG_COMMIT}, but the current tag points to ${TAG_COMMIT}. Refusing to mutate a moved release tag."
    }

    PUBLISHED_METADATA_BINARY_SHA="$(read_metadata_field "${DOWNLOAD_DIR}/${METADATA_NAME}" binary_sha256)"
    [[ "${PUBLISHED_METADATA_BINARY_SHA}" == "${LOCAL_BINARY_SHA}" ]] || {
      fail "Published release metadata binary checksum ${PUBLISHED_METADATA_BINARY_SHA} does not match local build binary checksum ${LOCAL_BINARY_SHA}."
    }
    rm -rf "${DOWNLOAD_DIR}"
  fi

  if [[ "${ARCHIVE_PRESENT}" -eq 1 ]]; then
    DOWNLOAD_DIR="$(mktemp -d)"
    gh release download "${TAG}" \
      --repo "${SOURCE_OWNER}/${SOURCE_REPO}" \
      --pattern "${ARCHIVE_NAME}" \
      --dir "${DOWNLOAD_DIR}" \
      --clobber

    PUBLISHED_BINARY_SHA="$(extract_binary_sha "${DOWNLOAD_DIR}/${ARCHIVE_NAME}")"
    [[ "${PUBLISHED_BINARY_SHA}" == "${LOCAL_BINARY_SHA}" ]] || {
      fail "Published asset binary checksum ${PUBLISHED_BINARY_SHA} does not match local build binary checksum ${LOCAL_BINARY_SHA}."
    }
    rm -rf "${DOWNLOAD_DIR}"
  fi

  if [[ "${ARCHIVE_PRESENT}" -eq 0 ]]; then
    gh release upload "${TAG}" "${ARCHIVE_PATH}" \
      --repo "${SOURCE_OWNER}/${SOURCE_REPO}"
  fi

  if [[ "${METADATA_PRESENT}" -eq 0 ]]; then
    gh release upload "${TAG}" "${METADATA_PATH}" \
      --repo "${SOURCE_OWNER}/${SOURCE_REPO}"
  fi

  printf 'Release %s already exists with the expected payload and provenance; continuing without mutation.\n' "${TAG}"
  exit 0
fi

gh release create "${TAG}" "${ARCHIVE_PATH}" "${METADATA_PATH}" \
  --repo "${SOURCE_OWNER}/${SOURCE_REPO}" \
  --title "${TAG}" \
  --notes "Release ${TAG}"
