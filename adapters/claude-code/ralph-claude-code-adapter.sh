#!/usr/bin/env bash
# Claude Code adapter for the universal Ralph loop engine

# Returns the appropriate command for running Claude Code
get_adapter_command() {
  local config_file="$1"
  local model
  model=$(config_get "$config_file" '.model' 'sonnet')
  
  local base_cmd="claude --dangerously-skip-permissions"
  
  # Add model flag if specified
  if [[ -n "$model" ]] && [[ "$model" != "null" ]]; then
    base_cmd="${base_cmd} --model ${model}"
  fi
  
  # Claude Code reads from stdin with -p flag for prompt
  echo "${base_cmd} -p"
}

# Install adapter files into target repository
install_adapter() {
  local target_dir="$1"
  local ralph_root="$2"
  
  mkdir -p "${target_dir}/.claude"
  
  # Copy plugin if it doesn't exist
  if [[ ! -d "${target_dir}/.claude-plugin" ]]; then
    cp -r "${ralph_root}/adapters/claude-code/.claude-plugin" "${target_dir}/.claude-plugin"
  fi
  
  # Copy hooks
  mkdir -p "${target_dir}/.claude/hooks"
  cp "${ralph_root}/adapters/claude-code/hooks/"*.sh "${target_dir}/.claude/hooks/" 2>/dev/null || true
  chmod +x "${target_dir}/.claude/hooks/"*.sh 2>/dev/null || true
  
  # Enable agent teams in settings
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
