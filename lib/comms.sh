#!/usr/bin/env bash
# Inter-agent file-based messaging system

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

MSG_DIR=""

init_msg_dir() {
  local ralph_root="${1:-$(resolve_ralph_root)}"
  MSG_DIR="${ralph_root}/state/messages"
  mkdir -p "$MSG_DIR"
}

# Send a message from one agent to another
msg_send() {
  local from="$1"
  local to="$2"
  local msg_type="$3"  # task_assigned, review_request, feedback, status_update, broadcast
  local content="$4"

  [[ -z "$MSG_DIR" ]] && init_msg_dir

  local msg_id
  msg_id=$(generate_id "msg")
  local msg_file="${MSG_DIR}/${to}_${msg_id}.json"
  local now
  now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local msg_json
  msg_json=$(jq -n \
    --arg id "$msg_id" \
    --arg from "$from" \
    --arg to "$to" \
    --arg type "$msg_type" \
    --arg content "$content" \
    --arg ts "$now" \
    --arg read "false" \
    '{
      id: $id,
      from: $from,
      to: $to,
      type: $type,
      content: $content,
      timestamp: $ts,
      read: false
    }'
  )

  atomic_write "$msg_file" "$msg_json"
  ralph_log DEBUG "Message $msg_id: $from -> $to ($msg_type)"
  echo "$msg_id"
}

# Broadcast a message to all agents
msg_broadcast() {
  local from="$1"
  local msg_type="$2"
  local content="$3"

  [[ -z "$MSG_DIR" ]] && init_msg_dir

  # Read agent registry to find all agents
  local agent_dir
  agent_dir="$(dirname "$MSG_DIR")/agents"
  
  for agent_file in "$agent_dir"/*.json; do
    [[ -f "$agent_file" ]] || continue
    local agent_id status
    agent_id=$(jq -r '.id' "$agent_file")
    status=$(jq -r '.status' "$agent_file")
    
    if [[ "$agent_id" != "$from" ]] && [[ "$status" == "running" ]]; then
      msg_send "$from" "$agent_id" "$msg_type" "$content"
    fi
  done
}

# Read unread messages for an agent
msg_receive() {
  local agent_id="$1"
  local msg_type="${2:-all}"

  [[ -z "$MSG_DIR" ]] && init_msg_dir

  local messages="[]"

  for msg_file in "$MSG_DIR"/${agent_id}_*.json; do
    [[ -f "$msg_file" ]] || continue

    local is_read
    is_read=$(jq -r '.read' "$msg_file")
    
    if [[ "$is_read" == "false" ]]; then
      local type
      type=$(jq -r '.type' "$msg_file")
      
      if [[ "$msg_type" == "all" ]] || [[ "$type" == "$msg_type" ]]; then
        # Mark as read
        local updated
        updated=$(jq '.read = true' "$msg_file")
        atomic_write "$msg_file" "$updated"

        messages=$(echo "$messages" | jq --argjson msg "$(cat "$msg_file")" '. + [$msg]')
      fi
    fi
  done

  echo "$messages"
}

# Check for unread messages (non-destructive peek)
msg_peek() {
  local agent_id="$1"
  [[ -z "$MSG_DIR" ]] && init_msg_dir

  local count=0
  for msg_file in "$MSG_DIR"/${agent_id}_*.json; do
    [[ -f "$msg_file" ]] || continue
    local is_read
    is_read=$(jq -r '.read' "$msg_file" 2>/dev/null)
    [[ "$is_read" == "false" ]] && count=$((count + 1))
  done

  echo "$count"
}

# Clean up old read messages (older than N minutes)
msg_cleanup() {
  local max_age_minutes="${1:-60}"
  [[ -z "$MSG_DIR" ]] && init_msg_dir

  local now_epoch
  now_epoch=$(date +%s)

  for msg_file in "$MSG_DIR"/*.json; do
    [[ -f "$msg_file" ]] || continue
    local is_read
    is_read=$(jq -r '.read' "$msg_file" 2>/dev/null)
    
    if [[ "$is_read" == "true" ]]; then
      local file_age
      file_age=$(( now_epoch - $(stat -f %m "$msg_file" 2>/dev/null || stat -c %Y "$msg_file" 2>/dev/null || echo "$now_epoch") ))
      
      if [[ $file_age -gt $((max_age_minutes * 60)) ]]; then
        rm -f "$msg_file"
      fi
    fi
  done
}
