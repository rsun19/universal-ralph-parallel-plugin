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

_copilot_base_flags() {
  local config_file="$1"
  local model
  model=$(config_get "$config_file" '.model' 'sonnet')

  local cmd="copilot --allow-all"

  if [[ -n "$model" ]] && [[ "$model" != "null" ]]; then
    cmd="${cmd} --model \"${model}\""
  fi

  echo "$cmd"
}

get_adapter_command() {
  echo "$(_copilot_base_flags "$1") -p"
}

get_initial_command() {
  echo "$(_copilot_base_flags "$1") --output-format json -p"
}

get_session_command() {
  local config_file="$1"
  local session_id="$2"
  echo "$(_copilot_base_flags "$config_file") --resume=\"${session_id}\" --output-format json -p"
}

get_manager_command() {
  local config_file="$1"
  local mgr_model
  mgr_model=$(config_get "$config_file" '.manager_model' 'sonnet')

  local cmd="copilot --allow-all"

  if [[ -n "$mgr_model" ]] && [[ "$mgr_model" != "null" ]]; then
    cmd="${cmd} --model \"${mgr_model}\""
  fi

  echo "${cmd} -p"
}
