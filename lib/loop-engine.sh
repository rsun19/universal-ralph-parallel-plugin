#!/usr/bin/env bash
# Core Ralph loop engine - tool-agnostic iterative execution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Run a single iteration of the Ralph loop
# Args: ai_command, prompt_file, output_file, target_dir
run_iteration() {
  local ai_command="$1"
  local prompt_file="$2"
  local output_file="$3"
  local target_dir="${4:-.}"
  
  if [[ ! -f "$prompt_file" ]]; then
    ralph_die "Prompt file not found: $prompt_file"
  fi

  local prompt_content
  prompt_content=$(cat "$prompt_file")

  ralph_log INFO "Running iteration in ${target_dir} with command: ${ai_command%% *}..."

  local exit_code=0
  (
    cd "$target_dir"
    echo "$prompt_content" | eval "$ai_command" > "$output_file" 2>&1
  ) || exit_code=$?

  return $exit_code
}

# Check if output contains the completion promise
check_completion_promise() {
  local output_file="$1"
  local promise="$2"

  if [[ -z "$promise" ]] || [[ "$promise" == "null" ]]; then
    return 1
  fi

  if [[ ! -f "$output_file" ]]; then
    return 1
  fi

  # Check for promise in <promise> tags (like the Claude Code plugin)
  local promise_text
  promise_text=$(perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' < "$output_file" 2>/dev/null || echo "")

  if [[ -n "$promise_text" ]] && [[ "$promise_text" == "$promise" ]]; then
    return 0
  fi

  # Fallback: check if promise text appears anywhere in output
  if grep -qF "$promise" "$output_file" 2>/dev/null; then
    return 0
  fi

  return 1
}

# Main Ralph loop
# Args: config_file, prompt_file, [loop_id]
ralph_loop() {
  local config_file="$1"
  local prompt_file="$2"
  local loop_id="${3:-$(generate_id loop)}"
  
  require_jq

  local ai_command target_dir max_iterations completion_promise commit_on_success
  ai_command=$(config_get "$config_file" '.ai_tool_command' 'claude --dangerously-skip-permissions')
  target_dir=$(config_get "$config_file" '.target_repo' '.')
  max_iterations=$(config_get "$config_file" '.loop.max_iterations' '0')
  completion_promise=$(config_get "$config_file" '.loop.completion_promise' '')
  commit_on_success=$(config_get "$config_file" '.loop.commit_on_success' 'false')

  # Resolve adapter-specific command override
  local ai_tool
  ai_tool=$(config_get "$config_file" '.ai_tool' 'generic')
  local ralph_root
  ralph_root=$(resolve_ralph_root)
  local adapter_script="${ralph_root}/adapters/${ai_tool}/ralph-${ai_tool}-adapter.sh"
  if [[ -f "$adapter_script" ]]; then
    source "$adapter_script"
    ai_command=$(get_adapter_command "$config_file" 2>/dev/null || echo "$ai_command")
  fi

  local state_dir
  state_dir=$(get_state_dir "$ralph_root")
  local log_dir="${state_dir}/logs/${loop_id}"
  mkdir -p "$log_dir"

  local iteration=0
  local state_file="${state_dir}/loops/${loop_id}.json"
  mkdir -p "$(dirname "$state_file")"

  ralph_log INFO "Starting Ralph loop '${loop_id}' (max_iterations=${max_iterations}, promise='${completion_promise}')"

  while true; do
    iteration=$((iteration + 1))

    # Check max iterations
    if [[ $max_iterations -gt 0 ]] && [[ $iteration -gt $max_iterations ]]; then
      ralph_log WARN "Max iterations ($max_iterations) reached for loop $loop_id"
      break
    fi

    ralph_log INFO "=== Loop $loop_id | Iteration $iteration ==="

    # Write state
    atomic_write "$state_file" "$(jq -n \
      --arg id "$loop_id" \
      --argjson iter "$iteration" \
      --argjson max "$max_iterations" \
      --arg promise "$completion_promise" \
      --arg status "running" \
      '{id: $id, iteration: $iter, max_iterations: $max, completion_promise: $promise, status: $status}'
    )"

    local output_file="${log_dir}/iteration-${iteration}.log"

    # Run one iteration
    local iter_exit=0
    run_iteration "$ai_command" "$prompt_file" "$output_file" "$target_dir" || iter_exit=$?

    # Check completion promise
    if [[ -n "$completion_promise" ]] && [[ "$completion_promise" != "null" ]]; then
      if check_completion_promise "$output_file" "$completion_promise"; then
        ralph_log INFO "Completion promise detected: '$completion_promise'"
        
        if [[ "$commit_on_success" == "true" ]]; then
          (cd "$target_dir" && git add -A && git commit -m "Ralph loop $loop_id completed (iteration $iteration)" 2>/dev/null) || true
        fi

        atomic_write "$state_file" "$(jq -n \
          --arg id "$loop_id" \
          --argjson iter "$iteration" \
          --arg status "completed" \
          '{id: $id, iteration: $iter, status: $status}'
        )"
        return 0
      fi
    fi

    # Brief pause between iterations to avoid hammering
    sleep 2
  done

  atomic_write "$state_file" "$(jq -n \
    --arg id "$loop_id" \
    --argjson iter "$iteration" \
    --arg status "max_iterations_reached" \
    '{id: $id, iteration: $iter, status: $status}'
  )"
  return 1
}
