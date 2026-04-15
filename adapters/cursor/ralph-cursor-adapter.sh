#!/usr/bin/env bash
# Cursor CLI adapter for the universal Ralph loop engine
#
# By default, respects Cursor's permission config files:
#   ~/.cursor/cli-config.json (global)
#   <project>/.cursor/cli.json (project)
#
# Pass --allow-all to ralph start to add --force (required for
# file writes in print mode without pre-configured permissions).
#
# Install: curl https://cursor.com/install -fsS | bash
# Docs:    https://cursor.com/docs/cli/overview
# Perms:   https://cursor.com/docs/cli/reference/permissions

_cursor_base_flags() {
  local config_file="$1"
  local model allow_all
  model=$(config_get "$config_file" '.model' 'sonnet')
  allow_all=$(config_get "$config_file" '.allow_all' 'false')

  local cmd="agent"

  if [[ "$allow_all" == "true" ]]; then
    cmd="${cmd} --force"
  fi

  if [[ -n "$model" ]] && [[ "$model" != "null" ]]; then
    cmd="${cmd} --model \"${model}\""
  fi

  echo "$cmd"
}

get_adapter_command() {
  echo "$(_cursor_base_flags "$1") -p"
}

get_initial_command() {
  echo "$(_cursor_base_flags "$1") --output-format json -p"
}

get_session_command() {
  local config_file="$1"
  local session_id="$2"
  echo "$(_cursor_base_flags "$config_file") --resume \"${session_id}\" --output-format json -p"
}

get_manager_command() {
  local config_file="$1"
  local mgr_model allow_all
  mgr_model=$(config_get "$config_file" '.manager_model' 'sonnet')
  allow_all=$(config_get "$config_file" '.allow_all' 'false')

  local cmd="agent"

  if [[ "$allow_all" == "true" ]]; then
    cmd="${cmd} --force"
  fi

  if [[ -n "$mgr_model" ]] && [[ "$mgr_model" != "null" ]]; then
    cmd="${cmd} --model \"${mgr_model}\""
  fi

  echo "${cmd} -p"
}
