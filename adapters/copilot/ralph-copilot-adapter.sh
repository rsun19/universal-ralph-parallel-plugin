#!/usr/bin/env bash
# GitHub Copilot CLI adapter for the universal Ralph loop engine
#
# Copilot CLI has no config-file-based permission system, so --allow-all
# is always included. Without it, every tool use prompts for approval,
# making unattended loops impossible.
#
# Install: https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli
# Docs:    https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli-agents/overview
# Perms:   https://docs.github.com/en/copilot/how-tos/copilot-cli/allowing-tools

get_adapter_command() {
  local config_file="$1"
  local model
  model=$(config_get "$config_file" '.model' 'sonnet')

  local cmd="copilot --allow-all"

  if [[ -n "$model" ]] && [[ "$model" != "null" ]]; then
    cmd="${cmd} --model \"${model}\""
  fi

  echo "${cmd} -p"
}
