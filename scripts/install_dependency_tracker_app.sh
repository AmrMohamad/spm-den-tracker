#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${REPO_ROOT}/DependencyTrackerApp/DependencyTrackerApp.xcodeproj"
SCHEME="DependencyTrackerApp"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${HOME}/Library/Developer/Xcode/DerivedData/DependencyTrackerApp-install}"
APP_NAME="DependencyTrackerApp"
BUILT_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
INSTALL_PATH="${INSTALL_PATH:-/Applications/${APP_NAME}.app}"

echo "Building ${APP_NAME} (${CONFIGURATION})..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

if [[ ! -d "${BUILT_APP_PATH}" ]]; then
  echo "Built app not found at ${BUILT_APP_PATH}" >&2
  exit 1
fi

echo "Installing to ${INSTALL_PATH}..."
rm -rf "${INSTALL_PATH}"
cp -R "${BUILT_APP_PATH}" "${INSTALL_PATH}"

echo "Installed: ${INSTALL_PATH}"
