#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION=""
SOURCE_OWNER="AmrMohamad"
SOURCE_REPO="spm-den-tracker"
TAP_OWNER="AmrMohamad"
TAP_REPO="homebrew-spm-den-tracker"
TAP_BRANCH="main"
ARCHIVE_NAME="spm-dep-tracker-macos.tar.gz"
WORK_DIR=""
FORMULA_RELATIVE_PATH="Formula/spm-dep-tracker.rb"
README_RELATIVE_PATH="README.md"

usage() {
  cat <<EOF
Usage: $(basename "$0") --version <x.y.z> [options]

Clone or update a dedicated Homebrew tap repo, render the stable formula into it,
and commit/push the change if needed.

Options:
  --version <x.y.z>         Stable version to publish. Required.
  --source-owner <name>     Source repo owner. Default: ${SOURCE_OWNER}
  --source-repo <name>      Source repo name. Default: ${SOURCE_REPO}
  --tap-owner <name>        Tap repo owner. Default: ${TAP_OWNER}
  --tap-repo <name>         Tap repo name. Default: ${TAP_REPO}
  --tap-branch <name>       Tap repo branch to update. Default: ${TAP_BRANCH}
  --work-dir <path>         Existing tap clone to update in place.
  --archive-name <name>     Release archive name. Default: ${ARCHIVE_NAME}
  -h, --help                Show this help text.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

parse_args() {
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
      --tap-branch)
        [[ $# -ge 2 ]] || fail "--tap-branch requires a value"
        TAP_BRANCH="$2"
        shift 2
        ;;
      --work-dir)
        [[ $# -ge 2 ]] || fail "--work-dir requires a value"
        WORK_DIR="$2"
        shift 2
        ;;
      --archive-name)
        [[ $# -ge 2 ]] || fail "--archive-name requires a value"
        ARCHIVE_NAME="$2"
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
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

require_command git
require_command gh

parse_args "$@"
[[ -n "${VERSION}" ]] || fail "--version is required"

if [[ -z "${WORK_DIR}" ]]; then
  WORK_DIR="$(mktemp -d)/${TAP_REPO}"
  gh repo clone "${TAP_OWNER}/${TAP_REPO}" "${WORK_DIR}"
fi

cd "${WORK_DIR}"
git checkout "${TAP_BRANCH}"
git pull --ff-only origin "${TAP_BRANCH}"
git config user.name github-actions
git config user.email github-actions@users.noreply.github.com

mkdir -p "$(dirname "${FORMULA_RELATIVE_PATH}")"

bash "${REPO_ROOT}/scripts/prepare_homebrew_release.sh" \
  --version "${VERSION}" \
  --owner "${SOURCE_OWNER}" \
  --repo "${SOURCE_REPO}" \
  --archive-name "${ARCHIVE_NAME}" \
  --skip-build \
  --formula-out "${WORK_DIR}/${FORMULA_RELATIVE_PATH}"

cat > "${WORK_DIR}/${README_RELATIVE_PATH}" <<EOF
# Homebrew Tap for \`spm-dep-tracker\`

This tap publishes the Homebrew formula for the CLI distributed from:

- source repo: https://github.com/${SOURCE_OWNER}/${SOURCE_REPO}
- formula name: \`spm-dep-tracker\`

Install:

\`\`\`bash
brew install ${SOURCE_OWNER}/${SOURCE_REPO}/spm-dep-tracker
\`\`\`

After this tap is added once, users can also install by short name:

\`\`\`bash
brew tap ${SOURCE_OWNER}/${SOURCE_REPO}
brew install spm-dep-tracker
\`\`\`

Maintainers should not edit the formula in this repo by hand. It is generated from
the upstream release workflow in \`${SOURCE_OWNER}/${SOURCE_REPO}\`.
EOF

if git diff --quiet; then
  echo "No tap changes to publish."
  exit 0
fi

git add "${FORMULA_RELATIVE_PATH}" "${README_RELATIVE_PATH}"
git commit -m "[Enhance]: release spm-dep-tracker v${VERSION}"
git push origin "${TAP_BRANCH}"
