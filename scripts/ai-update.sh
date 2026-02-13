#!/usr/bin/env bash
set -euo pipefail

# ─── Meta ────────────────────────────────────────────────────────────────
SCRIPT_NAME="ai-update"
SCRIPT_VERSION="1.0.0"
SCRIPT_REPO="https://raw.githubusercontent.com/akawaka/.github/main/scripts/ai-update.sh"

# ─── Colors ──────────────────────────────────────────────────────────────
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

# ─── Tool registry ──────────────────────────────────────────────────────
declare -A TOOL_META=(
  [abacus]="npm:@abacus-ai/cli"
  [codex]="npm:@openai/codex"
  [copilot]="npm:@github/copilot"
  [gemini]="npm:@google/gemini-cli"
  [claude]="self:claude"
  [opencode]="self:opencode"
)

ALL_TOOL_NAMES=(abacus claude codex copilot gemini opencode)

# ─── Helpers ─────────────────────────────────────────────────────────────
die()  { echo -e "${RED}Error:${RESET} $*" >&2; exit 1; }
info() { echo -e "${CYAN}$*${RESET}"; }
ok()   { echo -e "${GREEN}✔ $*${RESET}"; }
warn() { echo -e "${YELLOW}$*${RESET}"; }
sep()  { echo -e "${BLUE}────────────────────────────────────────${RESET}"; }

download() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    die "Neither curl nor wget found. Install one and retry."
  fi
}

npm_latest_version() {
  npm view "$1" version 2>/dev/null | tr -d '[:space:]'
}

npm_global_installed_version() {
  npm ls -g --depth=0 "$1" 2>/dev/null \
    | awk -v p="$1@" '$0 ~ p { sub(/.*@/, "", $0); print $0 }' \
    | head -n1 \
    | tr -d '[:space:]' || true
}

# ─── Update functions ────────────────────────────────────────────────────
update_npm_tool() {
  local pkg="$1"
  sep
  warn "Checking ${pkg}..."

  local installed latest
  installed="$(npm_global_installed_version "$pkg" || true)"
  latest="$(npm_latest_version "$pkg" || true)"

  if [[ -z "$latest" ]]; then
    echo -e "${RED}✖ Could not fetch latest version for ${pkg}.${RESET}"
    echo -e "${RED}  Check network / npm registry access.${RESET}"
    return 1
  fi

  if [[ -z "$installed" ]]; then
    info "Not installed: ${pkg}"
    warn "Installing ${pkg}@${latest}..."
    npm install -g "${pkg}@${latest}"
    ok "Installed: ${pkg}@${latest}"
    return
  fi

  if [[ "$installed" == "$latest" ]]; then
    ok "Up-to-date: ${pkg}@${installed}"
    return
  fi

  info "Installed: ${pkg}@${installed}"
  info "Latest:    ${pkg}@${latest}"
  warn "Updating ${pkg}..."
  npm install -g "${pkg}@${latest}"
  ok "Updated: ${pkg}@${latest}"
}

update_self_tool() {
  local cmd="$1"
  sep
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${RED}${cmd} CLI not found, skipping.${RESET}"
    return 0
  fi

  warn "Checking/Updating ${cmd} CLI..."
  local subcmd="upgrade"
  [[ "$cmd" == "claude" ]] && subcmd="update"

  if "$cmd" "$subcmd"; then
    ok "Done: ${cmd}"
  else
    echo -e "${RED}✖ Failed: ${cmd}${RESET}"
    return 1
  fi
}

update_tool() {
  local name="$1"
  local meta="${TOOL_META[$name]}"
  local type="${meta%%:*}"
  local target="${meta#*:}"

  case "$type" in
    npm)  update_npm_tool "$target" ;;
    self) update_self_tool "$target" ;;
  esac
}

# ─── Install command ─────────────────────────────────────────────────────
do_install() {
  local bin_dir="${HOME}/.local/bin"
  local dest="${bin_dir}/${SCRIPT_NAME}"
  local shell_rc

  # Reattach stdin to terminal so read works when piped
  exec 3<&0
  if [[ -e /dev/tty ]]; then
    exec 0</dev/tty
  fi

  case "${SHELL:-/bin/bash}" in
    */zsh)  shell_rc="${HOME}/.zshrc" ;;
    */fish) die "Fish shell is not supported (bash/zsh only)." ;;
    *)      shell_rc="${HOME}/.bashrc" ;;
  esac

  mkdir -p "$bin_dir"

  echo -e "${BOLD}${CYAN}AI CLI Update Tool — Interactive Installer${RESET}"
  echo ""

  info "Downloading ${SCRIPT_NAME} from repository..."
  download "$SCRIPT_REPO" "$dest"
  chmod +x "$dest"
  ok "Installed ${dest}"

  echo ""
  echo "Select which tools the alias should update by default:"
  echo "(You can always override at runtime with --tool=NAME)"
  echo ""

  local selected=()
  for name in "${ALL_TOOL_NAMES[@]}"; do
    local meta="${TOOL_META[$name]}"
    local target="${meta#*:}"
    read -rp "  Include ${name} (${target})? [Y/n] " answer
    answer="${answer:-y}"
    if [[ "$answer" =~ ^[Yy] ]]; then
      selected+=("$name")
    fi
  done

  # Restore stdin
  exec 0<&3
  exec 3<&-

  if [[ ${#selected[@]} -eq 0 ]]; then
    die "No tools selected. Aborting install."
  fi

  echo ""
  info "Selected tools: ${selected[*]}"

  # Build alias
  local tool_args=""
  if [[ ${#selected[@]} -ne ${#ALL_TOOL_NAMES[@]} ]]; then
    for t in "${selected[@]}"; do
      tool_args+=" --tool=${t}"
    done
  fi

  local alias_line="alias ${SCRIPT_NAME}='${dest}${tool_args}'"

  # Remove old alias if present, then append
  if grep -q "alias ${SCRIPT_NAME}=" "$shell_rc" 2>/dev/null; then
    sed -i.bak "/alias ${SCRIPT_NAME}=/d" "$shell_rc"
  fi

  {
    echo ""
    echo "# AI CLI Update Tool"
    echo "${alias_line}"
  } >> "$shell_rc"

  ok "Alias added to ${shell_rc}"
  echo ""
  echo -e "${YELLOW}Run ${BOLD}source ${shell_rc}${RESET}${YELLOW} or open a new terminal, then use:${RESET}"
  echo -e "  ${GREEN}${SCRIPT_NAME}${RESET}                              — update selected tools"
  echo -e "  ${GREEN}${SCRIPT_NAME} --tool=claude --tool=codex${RESET}   — update specific tools"
  echo ""

  if [[ ":$PATH:" != *":${bin_dir}:"* ]]; then
    warn "⚠  ${bin_dir} is not in your PATH."
    echo -e "   Add this to your ${shell_rc}:"
    echo -e "   ${CYAN}export PATH=\"\${HOME}/.local/bin:\${PATH}\"${RESET}"
  fi
}

# ─── Usage ───────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}${SCRIPT_NAME}${RESET} v${SCRIPT_VERSION} — Update AI CLI tools"
  echo ""
  echo -e "${BOLD}Usage:${RESET}"
  echo -e "  ${SCRIPT_NAME} [options]"
  echo -e "  ${SCRIPT_NAME} install"
  echo ""
  echo -e "${BOLD}Commands:${RESET}"
  echo -e "  install           Download script and create the ${SCRIPT_NAME} shell alias"
  echo ""
  echo -e "${BOLD}Options:${RESET}"
  echo -e "  --tool=NAME       Tool to update (can be repeated). If omitted, updates all."
  echo -e "                    Names: ${ALL_TOOL_NAMES[*]}"
  echo -e "  -h, --help        Show this help"
  echo -e "  -v, --version     Show version"
  echo ""
  echo -e "${BOLD}Examples:${RESET}"
  echo -e "  ${SCRIPT_NAME} --tool=claude --tool=codex"
  echo -e "  ${SCRIPT_NAME}"
}

# ─── Main ────────────────────────────────────────────────────────────────
main() {
  local tools_to_update=()
  local do_install_flag=false

  # Auto-detect pipe install: no args + stdin is not a terminal
  if [[ $# -eq 0 && ! -t 0 ]]; then
    do_install_flag=true
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      install)
        do_install_flag=true
        shift
        ;;
      --tool=*)
        local name="${1#--tool=}"
        if [[ -z "${TOOL_META[$name]+x}" ]]; then
          die "Unknown tool: ${name}. Valid: ${ALL_TOOL_NAMES[*]}"
        fi
        tools_to_update+=("$name")
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -v|--version)
        echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
        exit 0
        ;;
      *)
        die "Unknown option: $1 (see --help)"
        ;;
    esac
  done

  if $do_install_flag; then
    do_install
    exit 0
  fi

  # Default: all tools
  if [[ ${#tools_to_update[@]} -eq 0 ]]; then
    tools_to_update=("${ALL_TOOL_NAMES[@]}")
  fi

  echo -e "${CYAN}${BOLD}Checking and updating AI CLI tools...${RESET}"

  local has_npm=true
  if ! command -v npm >/dev/null 2>&1; then
    has_npm=false
  fi

  local errors=0
  for name in "${tools_to_update[@]}"; do
    local type="${TOOL_META[$name]%%:}"
    if [[ "$type" == "npm" && "$has_npm" == false ]]; then
      sep
      echo -e "${RED}✖ Skipping ${name}: npm is not installed.${RESET}"
      ((errors++)) || true
      continue
    fi
    update_tool "$name" || ((errors++)) || true
  done

  sep
  if [[ $errors -gt 0 ]]; then
    echo -e "${YELLOW}Completed with ${errors} error(s).${RESET}"
    exit 1
  fi
  ok "All checks complete."
}

main "$@"
