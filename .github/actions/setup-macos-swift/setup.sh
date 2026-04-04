#!/usr/bin/env bash

set -euo pipefail

REQUESTED_VERSION="${1:-}"
[[ -n "${REQUESTED_VERSION}" ]] || {
  echo "Missing Swift version argument." >&2
  exit 1
}
[[ "${REQUESTED_VERSION}" =~ ^[0-9]+\.[0-9]+$ ]] || {
  echo "Swift version must look like major.minor, for example 6.2." >&2
  exit 1
}

requested_major="${REQUESTED_VERSION%%.*}"
requested_minor="${REQUESTED_VERSION##*.}"

print_candidate_table() {
  local candidate_path="$1"
  local swift_version="$2"
  printf '  - %s => %s\n' "${candidate_path}" "${swift_version}"
}

extract_swift_version() {
  local candidate_path="$1"
  DEVELOPER_DIR="${candidate_path}/Contents/Developer" xcrun swift --version 2>/dev/null \
    | awk '/Apple Swift version/ { print $4; exit }'
}

compare_versions() {
  local left="$1"
  local right="$2"
  python3 - <<'PY' "${left}" "${right}"
import sys

def normalize(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in value.split("."))

left, right = sys.argv[1:]
if normalize(left) > normalize(right):
    print("gt")
elif normalize(left) < normalize(right):
    print("lt")
else:
    print("eq")
PY
}

shopt -s nullglob
candidates=(/Applications/Xcode*.app)
shopt -u nullglob

if [[ "${#candidates[@]}" -eq 0 ]]; then
  echo "No Xcode.app candidates found under /Applications." >&2
  exit 1
fi

best_path=""
best_version=""
diagnostics=()

for candidate in "${candidates[@]}"; do
  developer_dir="${candidate}/Contents/Developer"
  [[ -d "${developer_dir}" ]] || continue

  swift_version="$(extract_swift_version "${candidate}" || true)"
  if [[ -z "${swift_version}" ]]; then
    diagnostics+=("$(print_candidate_table "${candidate}" "unreadable")")
    continue
  fi

  diagnostics+=("$(print_candidate_table "${candidate}" "${swift_version}")")

  candidate_major="${swift_version%%.*}"
  remainder="${swift_version#*.}"
  candidate_minor="${remainder%%.*}"

  if [[ "${candidate_major}" != "${requested_major}" || "${candidate_minor}" != "${requested_minor}" ]]; then
    continue
  fi

  if [[ -z "${best_version}" ]]; then
    best_path="${candidate}"
    best_version="${swift_version}"
    continue
  fi

  if [[ "$(compare_versions "${swift_version}" "${best_version}")" == "gt" ]]; then
    best_path="${candidate}"
    best_version="${swift_version}"
  fi
done

echo "Discovered Xcode candidates:"
printf '%s\n' "${diagnostics[@]}"

if [[ -z "${best_path}" ]]; then
  echo "No installed Xcode provides Swift ${REQUESTED_VERSION}.x on this runner." >&2
  exit 1
fi

selected_developer_dir="${best_path}/Contents/Developer"
echo "Selected ${best_path} for Swift ${best_version}."
echo "DEVELOPER_DIR=${selected_developer_dir}" >> "${GITHUB_ENV}"
export DEVELOPER_DIR="${selected_developer_dir}"
resolved_swift_version="$(xcrun swift --version | awk '/Apple Swift version/ { print $4; exit }')"
echo "Resolved Swift version: ${resolved_swift_version}"
