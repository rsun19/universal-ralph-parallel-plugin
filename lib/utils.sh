#!/usr/bin/env bash
# Shared utilities for the Ralph Wiggum universal plugin

set -euo pipefail

RALPH_VERSION="1.0.0"

ralph_log() {
  local level="$1"; shift
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  case "$level" in
    INFO)  echo "[$timestamp] [INFO]  $*" ;;
    WARN)  echo "[$timestamp] [WARN]  $*" >&2 ;;
    ERROR) echo "[$timestamp] [ERROR] $*" >&2 ;;
    DEBUG) [[ "${RALPH_DEBUG:-0}" == "1" ]] && echo "[$timestamp] [DEBUG] $*" ;;
  esac
}

ralph_die() {
  ralph_log ERROR "$@"
  exit 1
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || ralph_die "Required command not found: $cmd"
}

require_jq() {
  require_command jq
}

# Resolve the ralph plugin root directory (where bin/, lib/, etc. live)
resolve_ralph_root() {
  local source="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  local dir
  dir=$(cd "$(dirname "$source")/.." && pwd)
  echo "$dir"
}

# Load config with defaults
load_config() {
  local config_file="${1:-ralph.config.json}"
  
  if [[ ! -f "$config_file" ]]; then
    ralph_die "Config file not found: $config_file"
  fi

  require_jq

  # Validate JSON
  if ! jq empty "$config_file" 2>/dev/null; then
    ralph_die "Invalid JSON in config: $config_file"
  fi

  echo "$config_file"
}

config_get() {
  local config_file="$1"
  local key="$2"
  local default="${3:-}"
  
  local val
  val=$(jq -r "$key // empty" "$config_file" 2>/dev/null)
  
  if [[ -z "$val" ]]; then
    echo "$default"
  else
    echo "$val"
  fi
}

# Atomic file write via temp + rename
atomic_write() {
  local target="$1"
  local content="$2"
  local tmpfile="${target}.tmp.$$"
  
  echo "$content" > "$tmpfile"
  mv "$tmpfile" "$target"
}

# Generate a short unique ID
generate_id() {
  local prefix="${1:-}"
  local id
  id=$(date +%s%N | sha256sum 2>/dev/null || shasum -a 256 2>/dev/null | head -c 8)
  id=${id:0:8}
  if [[ -n "$prefix" ]]; then
    echo "${prefix}-${id}"
  else
    echo "$id"
  fi
}

# Wait for a file to appear with timeout
wait_for_file() {
  local file="$1"
  local timeout="${2:-30}"
  local elapsed=0
  
  while [[ ! -f "$file" ]] && [[ $elapsed -lt $timeout ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done
  
  [[ -f "$file" ]]
}

# Get the state directory, creating if needed
get_state_dir() {
  local ralph_root="${1:-$(resolve_ralph_root)}"
  local state_dir="${ralph_root}/state"
  mkdir -p "$state_dir"/{tasks,messages,agents}
  echo "$state_dir"
}

# Check if a process is still running
is_pid_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

# Kill a process tree
kill_tree() {
  local pid="$1"
  local signal="${2:-TERM}"
  
  # Kill children first
  local children
  children=$(pgrep -P "$pid" 2>/dev/null || true)
  for child in $children; do
    kill_tree "$child" "$signal"
  done
  
  kill "-${signal}" "$pid" 2>/dev/null || true
}

timestamp_ms() {
  if [[ "$(uname)" == "Darwin" ]]; then
    python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || date +%s000
  else
    date +%s%3N 2>/dev/null || date +%s000
  fi
}
