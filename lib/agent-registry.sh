#!/usr/bin/env bash
# Agent registry - tracks running agent processes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

AGENT_DIR=""

init_agent_dir() {
  local ralph_root="${1:-$(resolve_ralph_root)}"
  local state_dir="${RALPH_SESSION_DIR:-${ralph_root}/state}"
  AGENT_DIR="${state_dir}/agents"
  mkdir -p "$AGENT_DIR"
}

# Register a new agent
agent_register() {
  local agent_id="$1"
  local agent_role="$2"  # manager, implementer, reviewer
  local pid="$3"
  local task_id="${4:-}"

  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  local agent_file="${AGENT_DIR}/${agent_id}.json"
  local now
  now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local agent_json
  agent_json=$(jq -n \
    --arg id "$agent_id" \
    --arg role "$agent_role" \
    --argjson pid "$pid" \
    --arg task "$task_id" \
    --arg status "running" \
    --arg started "$now" \
    '{
      id: $id,
      role: $role,
      pid: $pid,
      current_task: $task,
      status: $status,
      started_at: $started,
      last_heartbeat: $started
    }'
  )

  atomic_write "$agent_file" "$agent_json"
  ralph_log INFO "Registered agent $agent_id (role=$agent_role, pid=$pid)"
}

# Update agent heartbeat
agent_heartbeat() {
  local agent_id="$1"
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  local agent_file="${AGENT_DIR}/${agent_id}.json"
  [[ -f "$agent_file" ]] || return 1

  local now
  now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local updated
  updated=$(jq --arg now "$now" '.last_heartbeat = $now' "$agent_file")
  atomic_write "$agent_file" "$updated"
}

# Set agent status
agent_set_status() {
  local agent_id="$1"
  local status="$2"
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  local agent_file="${AGENT_DIR}/${agent_id}.json"
  [[ -f "$agent_file" ]] || return 1

  local now
  now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  local updated
  updated=$(jq --arg status "$status" --arg now "$now" \
    '.status = $status | .last_heartbeat = $now' "$agent_file")
  atomic_write "$agent_file" "$updated"
}

# Set agent's current task
agent_set_task() {
  local agent_id="$1"
  local task_id="$2"
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  local agent_file="${AGENT_DIR}/${agent_id}.json"
  [[ -f "$agent_file" ]] || return 1

  local updated
  updated=$(jq --arg task "$task_id" '.current_task = $task' "$agent_file")
  atomic_write "$agent_file" "$updated"
}

# Get agent info
agent_get() {
  local agent_id="$1"
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  local agent_file="${AGENT_DIR}/${agent_id}.json"
  [[ -f "$agent_file" ]] || return 1
  cat "$agent_file"
}

# List agents by role
agent_list() {
  local filter_role="${1:-all}"
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  for agent_file in "$AGENT_DIR"/*.json; do
    [[ -f "$agent_file" ]] || continue
    if [[ "$filter_role" == "all" ]]; then
      cat "$agent_file"
    else
      local role
      role=$(jq -r '.role' "$agent_file")
      [[ "$role" == "$filter_role" ]] && cat "$agent_file"
    fi
  done | jq -s '.'
}

# List running agents
agent_list_running() {
  local filter_role="${1:-all}"
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  for agent_file in "$AGENT_DIR"/*.json; do
    [[ -f "$agent_file" ]] || continue
    local status pid
    status=$(jq -r '.status' "$agent_file")
    pid=$(jq -r '.pid' "$agent_file")

    if [[ "$status" == "running" ]] && is_pid_alive "$pid"; then
      if [[ "$filter_role" == "all" ]]; then
        cat "$agent_file"
      else
        local role
        role=$(jq -r '.role' "$agent_file")
        [[ "$role" == "$filter_role" ]] && cat "$agent_file"
      fi
    fi
  done | jq -s '.'
}

# Deregister an agent
agent_deregister() {
  local agent_id="$1"
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  local agent_file="${AGENT_DIR}/${agent_id}.json"
  if [[ -f "$agent_file" ]]; then
    agent_set_status "$agent_id" "stopped"
    ralph_log INFO "Deregistered agent $agent_id"
  fi
}

# Kill an agent process
agent_kill() {
  local agent_id="$1"
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  local agent_file="${AGENT_DIR}/${agent_id}.json"
  [[ -f "$agent_file" ]] || return 1

  local pid
  pid=$(jq -r '.pid' "$agent_file")
  
  if is_pid_alive "$pid"; then
    kill_tree "$pid"
    ralph_log INFO "Killed agent $agent_id (pid=$pid)"
  fi

  agent_set_status "$agent_id" "killed"
}

# Kill all agents of a role
agent_kill_all() {
  local role="${1:-all}"
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  for agent_file in "$AGENT_DIR"/*.json; do
    [[ -f "$agent_file" ]] || continue
    local agent_id agent_role status
    agent_id=$(jq -r '.id' "$agent_file")
    agent_role=$(jq -r '.role' "$agent_file")
    status=$(jq -r '.status' "$agent_file")

    if [[ "$status" == "running" ]]; then
      if [[ "$role" == "all" ]] || [[ "$agent_role" == "$role" ]]; then
        agent_kill "$agent_id"
      fi
    fi
  done
}

# Clean up dead agent entries
agent_cleanup() {
  [[ -z "$AGENT_DIR" ]] && init_agent_dir

  for agent_file in "$AGENT_DIR"/*.json; do
    [[ -f "$agent_file" ]] || continue
    local pid status
    pid=$(jq -r '.pid' "$agent_file")
    status=$(jq -r '.status' "$agent_file")

    if [[ "$status" == "running" ]] && ! is_pid_alive "$pid"; then
      local agent_id
      agent_id=$(jq -r '.id' "$agent_file")
      agent_set_status "$agent_id" "dead"
      ralph_log WARN "Agent $agent_id (pid=$pid) found dead"
    fi
  done
}
