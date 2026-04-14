#!/usr/bin/env bash
# GitHub Copilot adapter for the universal Ralph loop engine
#
# Copilot Workspace and Copilot CLI have different interfaces.
# This adapter supports both approaches.

get_adapter_command() {
  local config_file="$1"
  
  # GitHub Copilot CLI (gh copilot)
  if command -v gh >/dev/null 2>&1 && gh extension list 2>/dev/null | grep -q copilot; then
    echo "gh copilot suggest -t shell"
  else
    # Fallback: write prompt for Copilot Workspace to pick up
    echo "cat > .github/ralph-prompt.md && echo 'Prompt written for Copilot Workspace'"
  fi
}

install_adapter() {
  local target_dir="$1"
  local ralph_root="$2"
  
  mkdir -p "${target_dir}/.github"
  
  # Install Copilot instructions
  cp "${ralph_root}/adapters/copilot/.github/copilot-instructions.md" \
     "${target_dir}/.github/" 2>/dev/null || true
}
