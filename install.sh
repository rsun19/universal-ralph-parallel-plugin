#!/usr/bin/env bash
# Ralph Wiggum Universal Installer
# Installs the Ralph CLI and optionally initializes a target repository.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

print_banner() {
  cat << 'BANNER'
  ╔══════════════════════════════════════════════╗
  ║  Ralph Wiggum - Universal AI Agent Teams     ║
  ║  Installer                                   ║
  ╚══════════════════════════════════════════════╝
BANNER
}

usage() {
  cat << EOF
Usage: ./install.sh [options]

Options:
  --link              Symlink ralph to /usr/local/bin (requires sudo)
  --target <path>     Initialize a target repository for Ralph
  --tool <name>       AI tool adapter to install (claude-code, cursor, copilot, generic)
  --all-adapters      Install all adapter files into the target repo
  -h, --help          Show this help

Examples:
  # Just make scripts executable (no root needed)
  ./install.sh

  # Symlink to PATH
  ./install.sh --link

  # Initialize a project for Ralph with Claude Code
  ./install.sh --target /path/to/myproject --tool claude-code

  # Initialize with all adapters
  ./install.sh --target /path/to/myproject --all-adapters
EOF
}

check_dependencies() {
  local missing=()
  
  command -v bash >/dev/null 2>&1 || missing+=("bash")
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required dependencies: ${missing[*]}"
    echo ""
    echo "Install them:"
    if [[ "$(uname)" == "Darwin" ]]; then
      echo "  brew install ${missing[*]}"
    else
      echo "  sudo apt-get install ${missing[*]}"
      echo "  # or"
      echo "  sudo yum install ${missing[*]}"
    fi
    exit 1
  fi
  
  echo "All dependencies satisfied."
}

make_executable() {
  echo "Making scripts executable..."
  chmod +x "${SCRIPT_DIR}/bin/ralph"
  chmod +x "${SCRIPT_DIR}/bin/ralph-manager.sh"
  chmod +x "${SCRIPT_DIR}/bin/ralph-worker.sh"
  chmod +x "${SCRIPT_DIR}/bin/ralph-review.sh"
  chmod +x "${SCRIPT_DIR}/adapters/claude-code/hooks/"*.sh 2>/dev/null || true
  chmod +x "${SCRIPT_DIR}/adapters/claude-code/ralph-claude-teams.sh" 2>/dev/null || true
  echo "Done."
}

symlink_to_path() {
  local link_path="/usr/local/bin/ralph"
  
  if [[ -L "$link_path" ]] || [[ -f "$link_path" ]]; then
    echo "Removing existing $link_path"
    sudo rm -f "$link_path"
  fi
  
  echo "Creating symlink: $link_path -> ${SCRIPT_DIR}/bin/ralph"
  sudo ln -s "${SCRIPT_DIR}/bin/ralph" "$link_path"
  echo "Done. You can now run 'ralph' from anywhere."
}

init_target() {
  local target_dir="$1"
  local tool="${2:-generic}"
  local all_adapters="${3:-false}"
  
  if [[ ! -d "$target_dir" ]]; then
    echo "Directory not found: $target_dir"
    exit 1
  fi
  
  echo "Initializing $target_dir for Ralph (tool: $tool)"
  
  # Create core files
  mkdir -p "${target_dir}/specs"
  
  if [[ ! -f "${target_dir}/AGENT.md" ]]; then
    cp "${SCRIPT_DIR}/templates/AGENT.md.template" "${target_dir}/AGENT.md"
    echo "  Created AGENT.md"
  fi
  
  if [[ ! -f "${target_dir}/fix_plan.md" ]]; then
    cat > "${target_dir}/fix_plan.md" << 'FIXPLAN'
# Fix Plan

This file is maintained by Ralph Wiggum agents. Items are sorted by priority.

## Tasks
<!-- Ralph will populate this with tasks -->
FIXPLAN
    echo "  Created fix_plan.md"
  fi
  
  # Install adapter(s)
  if [[ "$all_adapters" == "true" ]]; then
    for adapter_tool in claude-code cursor copilot generic; do
      install_single_adapter "$target_dir" "$adapter_tool"
    done
  else
    install_single_adapter "$target_dir" "$tool"
  fi
  
  # Update .gitignore
  if [[ -f "${target_dir}/.gitignore" ]]; then
    for pattern in "state/" ".ralph-iter-*.log" "ralph-state/"; do
      if ! grep -qF "$pattern" "${target_dir}/.gitignore" 2>/dev/null; then
        echo "$pattern" >> "${target_dir}/.gitignore"
      fi
    done
  else
    cat > "${target_dir}/.gitignore" << 'GITIGNORE'
state/
.ralph-iter-*.log
ralph-state/
*.lock
GITIGNORE
  fi
  echo "  Updated .gitignore"
  
  echo ""
  echo "Repository initialized for Ralph at: $target_dir"
  echo ""
  echo "Next steps:"
  echo "  1. Run: ralph init"
  echo "  2. Run: ralph start -p \"Describe what you want built\""
}

install_single_adapter() {
  local target_dir="$1"
  local tool="$2"
  
  local adapter_script="${SCRIPT_DIR}/adapters/${tool}/ralph-${tool}-adapter.sh"
  if [[ -f "$adapter_script" ]]; then
    source "$adapter_script"
    if type install_adapter &>/dev/null; then
      install_adapter "$target_dir" "$SCRIPT_DIR"
      echo "  Installed $tool adapter"
    fi
  fi
}

# Main
main() {
  local do_link=false
  local target_dir=""
  local tool="generic"
  local all_adapters=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --link) do_link=true; shift ;;
      --target) target_dir="$2"; shift 2 ;;
      --tool) tool="$2"; shift 2 ;;
      --all-adapters) all_adapters=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
  done
  
  print_banner
  check_dependencies
  make_executable
  
  if [[ "$do_link" == "true" ]]; then
    symlink_to_path
  fi
  
  if [[ -n "$target_dir" ]]; then
    init_target "$target_dir" "$tool" "$all_adapters"
  fi
  
  if [[ -z "$target_dir" ]] && [[ "$do_link" == "false" ]]; then
    echo ""
    echo "Scripts are ready. To add 'ralph' to your PATH:"
    echo "  ./install.sh --link"
    echo ""
    echo "Or add this to your shell profile:"
    echo "  export PATH=\"${SCRIPT_DIR}/bin:\$PATH\""
    echo ""
    echo "To get started:"
    echo "  ralph init"
  fi
}

main "$@"
