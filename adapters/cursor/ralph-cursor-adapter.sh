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

get_adapter_command() {
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

  echo "${cmd} -p"
}
