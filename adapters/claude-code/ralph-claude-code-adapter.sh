#!/usr/bin/env bash
# Claude Code adapter for the universal Ralph loop engine
#
# By default, respects Claude Code's permission config files:
#   ~/.claude/settings.json (user)
#   <project>/.claude/settings.json (project)
#
# Pass --allow-all to ralph start to add --dangerously-skip-permissions.
#
# Docs: https://code.claude.com/docs/en/permissions

get_adapter_command() {
  local config_file="$1"
  local model allow_all
  model=$(config_get "$config_file" '.model' 'sonnet')
  allow_all=$(config_get "$config_file" '.allow_all' 'false')

  local cmd="claude"

  if [[ "$allow_all" == "true" ]]; then
    cmd="${cmd} --dangerously-skip-permissions"
  fi

  if [[ -n "$model" ]] && [[ "$model" != "null" ]]; then
    cmd="${cmd} --model ${model}"
  fi

  echo "${cmd} -p"
}

install_adapter() {
  local target_dir="$1"
  local ralph_root="$2"
  
  mkdir -p "${target_dir}/.claude"
  
  if [[ ! -d "${target_dir}/.claude-plugin" ]]; then
    cp -r "${ralph_root}/adapters/claude-code/.claude-plugin" "${target_dir}/.claude-plugin"
  fi
  
  mkdir -p "${target_dir}/.claude/hooks"
  cp "${ralph_root}/adapters/claude-code/hooks/"*.sh "${target_dir}/.claude/hooks/" 2>/dev/null || true
  chmod +x "${target_dir}/.claude/hooks/"*.sh 2>/dev/null || true
  
  local settings_file="${target_dir}/.claude/settings.json"
  if [[ -f "$settings_file" ]]; then
    if ! jq -e '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$settings_file" >/dev/null 2>&1; then
      jq '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"' "$settings_file" > "${settings_file}.tmp"
      mv "${settings_file}.tmp" "$settings_file"
    fi
  else
    echo '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}}' | jq '.' > "$settings_file"
  fi
}
