#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${REPO_ROOT}/DependencyTrackerApp/DependencyTrackerApp.xcodeproj"
APP_SCHEME="DependencyTrackerApp"
APP_NAME="DependencyTrackerApp"
CLI_NAME="spm-dep-tracker"

MODE=""
CONFIGURATION="${CONFIGURATION:-Release}"
CLI_BIN_DIR="${CLI_BIN_DIR:-}"
APP_INSTALL_PATH="${APP_INSTALL_PATH:-}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${HOME}/Library/Developer/Xcode/DerivedData/DependencyTrackerApp-install}"
FORCE=0
NON_INTERACTIVE=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Guided installer for SPM Dependency Tracker.

Modes:
  cli         Build and install only the command-line tool
  app         Build and install only the macOS app
  full        Build and install both the CLI and the macOS app

Options:
  --mode <cli|app|full>     Installation mode. If omitted and running in a TTY,
                            the script asks interactively.
  --configuration <name>    Build configuration for both SwiftPM and Xcode builds.
                            Default: Release
  --cli-bin-dir <path>      Directory where the CLI binary will be installed.
                            Default: auto-detected safe user path
  --app-path <path>         Full destination path for the app bundle.
                            Default: /Applications/${APP_NAME}.app
  --derived-data-path <p>   DerivedData path for the app build.
                            Default: ${DERIVED_DATA_PATH}
  --force                   Overwrite existing installs without prompting.
  --non-interactive         Fail instead of prompting for missing choices.
  --dry-run                 Print the planned actions without executing them.
  -h, --help                Show this help text.

Examples:
  $(basename "$0")
  $(basename "$0") --mode cli
  $(basename "$0") --mode full --cli-bin-dir "\$HOME/.local/bin"
  $(basename "$0") --mode app --app-path "/Applications/${APP_NAME}.app"
EOF
}

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
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

is_tty() {
  [[ -t 0 && -t 1 ]]
}

swiftpm_configuration() {
  printf '%s\n' "${CONFIGURATION}" | tr '[:upper:]' '[:lower:]'
}

confirm() {
  local prompt="$1"
  if [[ "${FORCE}" -eq 1 ]]; then
    return 0
  fi
  if [[ "${NON_INTERACTIVE}" -eq 1 ]] || ! is_tty; then
    return 1
  fi

  local reply
  read -r -p "${prompt} [y/N] " reply
  [[ "${reply}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

choose_default_cli_bin_dir() {
  local candidates=()

  if [[ ":${PATH}:" == *":${HOME}/.local/bin:"* ]]; then
    candidates+=("${HOME}/.local/bin")
  fi
  if [[ ":${PATH}:" == *":${HOME}/bin:"* ]]; then
    candidates+=("${HOME}/bin")
  fi

  candidates+=("${HOME}/.local/bin" "${HOME}/bin")

  if [[ ":${PATH}:" == *":/opt/homebrew/bin:"* && -w /opt/homebrew/bin ]]; then
    candidates+=("/opt/homebrew/bin")
  fi
  if [[ ":${PATH}:" == *":/usr/local/bin:"* && -w /usr/local/bin ]]; then
    candidates+=("/usr/local/bin")
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    [[ -n "${candidate}" ]] || continue
    printf '%s\n' "${candidate}"
    return 0
  done

  printf '%s\n' "${HOME}/.local/bin"
}

choose_mode_interactively() {
  log "Choose what to install:"
  log "  1) CLI only"
  log "  2) GUI + CLI"
  log "  3) GUI only"

  local selection
  read -r -p "Enter choice [1-3]: " selection
  case "${selection}" in
    1) MODE="cli" ;;
    2) MODE="full" ;;
    3) MODE="app" ;;
    *) fail "Invalid selection: ${selection}" ;;
  esac
}

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local result

  if [[ "${NON_INTERACTIVE}" -eq 1 ]] || ! is_tty; then
    printf '%s\n' "${default_value}"
    return 0
  fi

  read -r -p "${prompt} [${default_value}]: " result
  if [[ -z "${result}" ]]; then
    printf '%s\n' "${default_value}"
  else
    printf '%s\n' "${result}"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

ensure_parent_dir() {
  local path="$1"
  local parent
  parent="$(dirname "${path}")"
  run mkdir -p "${parent}"
}

ensure_dir() {
  local path="$1"
  run mkdir -p "${path}"
}

ensure_overwrite_allowed() {
  local target="$1"
  local label="$2"
  if [[ ! -e "${target}" ]]; then
    return 0
  fi

  if confirm "${label} already exists at ${target}. Replace it?"; then
    return 0
  fi

  fail "Refusing to overwrite existing ${label} at ${target}"
}

print_path_hint_if_needed() {
  local dir="$1"
  if [[ ":${PATH}:" != *":${dir}:"* ]]; then
    log
    log "PATH note:"
    log "  ${dir} is not currently on PATH."
    log "  Add this line to your shell profile if you want to invoke ${CLI_NAME} directly:"
    log "    export PATH=\"${dir}:\$PATH\""
  fi
}

build_cli() {
  require_command swift
  log "Building ${CLI_NAME} (${CONFIGURATION})..."
  run swift build -c "$(swiftpm_configuration)" --product "${CLI_NAME}" --package-path "${REPO_ROOT}"
}

resolve_cli_build_path() {
  local bin_dir
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    printf '%s\n' "${REPO_ROOT}/.build/$(swiftpm_configuration)/${CLI_NAME}"
    return 0
  fi

  bin_dir="$(swift build -c "$(swiftpm_configuration)" --show-bin-path --package-path "${REPO_ROOT}")"
  printf '%s\n' "${bin_dir}/${CLI_NAME}"
}

install_cli() {
  local destination_dir="$1"
  local built_cli

  build_cli
  built_cli="$(resolve_cli_build_path)"

  if [[ "${DRY_RUN}" -ne 1 && ! -x "${built_cli}" ]]; then
    fail "Built CLI not found at ${built_cli}"
  fi

  ensure_dir "${destination_dir}"
  ensure_overwrite_allowed "${destination_dir}/${CLI_NAME}" "CLI binary"

  log "Installing CLI to ${destination_dir}/${CLI_NAME}..."
  run install -m 755 "${built_cli}" "${destination_dir}/${CLI_NAME}"
  print_path_hint_if_needed "${destination_dir}"
}

build_app() {
  require_command xcodebuild
  log "Building ${APP_NAME} (${CONFIGURATION})..."
  run xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${APP_SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    build
}

resolve_built_app_path() {
  printf '%s\n' "${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
}

install_app() {
  local destination_path="$1"
  local built_app

  build_app
  built_app="$(resolve_built_app_path)"

  if [[ "${DRY_RUN}" -ne 1 && ! -d "${built_app}" ]]; then
    fail "Built app not found at ${built_app}"
  fi

  ensure_parent_dir "${destination_path}"
  ensure_overwrite_allowed "${destination_path}" "app bundle"

  if [[ -e "${destination_path}" ]]; then
    log "Removing existing app bundle at ${destination_path}..."
    run rm -rf "${destination_path}"
  fi

  log "Installing app to ${destination_path}..."
  run cp -R "${built_app}" "${destination_path}"
}

normalize_mode() {
  case "${MODE}" in
    cli|app|full) ;;
    "") ;;
    *) fail "Unsupported mode: ${MODE}. Expected one of: cli, app, full." ;;
  esac
}

configure_defaults() {
  if [[ -z "${CLI_BIN_DIR}" ]]; then
    CLI_BIN_DIR="$(choose_default_cli_bin_dir)"
  fi

  if [[ -z "${APP_INSTALL_PATH}" ]]; then
    APP_INSTALL_PATH="/Applications/${APP_NAME}.app"
  fi
}

prompt_for_missing_choices() {
  if [[ -z "${MODE}" ]]; then
    if is_tty; then
      choose_mode_interactively
    else
      fail "No --mode provided and no interactive terminal is available."
    fi
  fi

  case "${MODE}" in
    cli|full)
      CLI_BIN_DIR="$(prompt_with_default "CLI install directory" "${CLI_BIN_DIR}")"
      ;;
  esac

  case "${MODE}" in
    app|full)
      APP_INSTALL_PATH="$(prompt_with_default "App install path" "${APP_INSTALL_PATH}")"
      ;;
  esac
}

print_plan() {
  log
  log "Install plan"
  log "  Mode: ${MODE}"
  log "  Configuration: ${CONFIGURATION}"
  case "${MODE}" in
    cli|full)
      log "  CLI destination: ${CLI_BIN_DIR}/${CLI_NAME}"
      ;;
  esac
  case "${MODE}" in
    app|full)
      log "  App destination: ${APP_INSTALL_PATH}"
      log "  DerivedData: ${DERIVED_DATA_PATH}"
      ;;
  esac
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "  Execution: dry-run"
  fi
  log
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)
        [[ $# -ge 2 ]] || fail "--mode requires a value"
        MODE="$2"
        shift 2
        ;;
      --configuration)
        [[ $# -ge 2 ]] || fail "--configuration requires a value"
        CONFIGURATION="$2"
        shift 2
        ;;
      --cli-bin-dir)
        [[ $# -ge 2 ]] || fail "--cli-bin-dir requires a value"
        CLI_BIN_DIR="$2"
        shift 2
        ;;
      --app-path)
        [[ $# -ge 2 ]] || fail "--app-path requires a value"
        APP_INSTALL_PATH="$2"
        shift 2
        ;;
      --derived-data-path)
        [[ $# -ge 2 ]] || fail "--derived-data-path requires a value"
        DERIVED_DATA_PATH="$2"
        shift 2
        ;;
      --force)
        FORCE=1
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
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

main() {
  parse_args "$@"
  normalize_mode
  configure_defaults
  prompt_for_missing_choices
  print_plan

  if [[ "${FORCE}" -ne 1 && "${NON_INTERACTIVE}" -ne 1 ]]; then
    if ! confirm "Proceed with this installation plan?"; then
      fail "Installation cancelled"
    fi
  fi

  case "${MODE}" in
    cli)
      install_cli "${CLI_BIN_DIR}"
      ;;
    app)
      install_app "${APP_INSTALL_PATH}"
      ;;
    full)
      install_cli "${CLI_BIN_DIR}"
      install_app "${APP_INSTALL_PATH}"
      ;;
  esac

  log
  log "Install complete."
  case "${MODE}" in
    cli)
      log "  CLI: ${CLI_BIN_DIR}/${CLI_NAME}"
      ;;
    app)
      log "  App: ${APP_INSTALL_PATH}"
      ;;
    full)
      log "  CLI: ${CLI_BIN_DIR}/${CLI_NAME}"
      log "  App: ${APP_INSTALL_PATH}"
      ;;
  esac
}

main "$@"
