#!/usr/bin/env bash
# Ralph Manager Agent - orchestrates implementers and reviewers

set -euo pipefail

RALPH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${RALPH_ROOT}/lib/utils.sh"
source "${RALPH_ROOT}/lib/task-manager.sh"
source "${RALPH_ROOT}/lib/agent-registry.sh"
source "${RALPH_ROOT}/lib/comms.sh"
source "${RALPH_ROOT}/lib/loop-engine.sh"

CONFIG_FILE="${1:?Config file required}"
PROMPT_FILE="${2:?Prompt file required}"

init_task_dir "$RALPH_ROOT"
init_agent_dir "$RALPH_ROOT"
init_msg_dir "$RALPH_ROOT"

MANAGER_ID="manager-$(generate_id)"
agent_register "$MANAGER_ID" "manager" "$$"

TARGET_REPO=$(config_get "$CONFIG_FILE" '.target_repo' '.')
[[ "$TARGET_REPO" != /* ]] && TARGET_REPO="$(cd "$TARGET_REPO" && pwd)"

NUM_IMPLEMENTERS=$(config_get "$CONFIG_FILE" '.team.implementers' '3')
NUM_REVIEWERS=$(config_get "$CONFIG_FILE" '.team.reviewers' '2')
MAX_RETRIES=$(config_get "$CONFIG_FILE" '.team.max_retries_per_task' '3')
MAX_ITERATIONS=$(config_get "$CONFIG_FILE" '.loop.max_iterations' '50')
AI_COMMAND=$(config_get "$CONFIG_FILE" '.ai_tool_command' 'claude -p')
AI_TOOL=$(config_get "$CONFIG_FILE" '.ai_tool' 'claude-code')
COMPLETION_PROMISE=$(config_get "$CONFIG_FILE" '.loop.completion_promise' 'ALL_TASKS_COMPLETE')

# Load adapter if available
ADAPTER_SCRIPT="${RALPH_ROOT}/adapters/${AI_TOOL}/ralph-${AI_TOOL}-adapter.sh"
if [[ -f "$ADAPTER_SCRIPT" ]]; then
  source "$ADAPTER_SCRIPT"
fi

cleanup() {
  ralph_log INFO "Manager shutting down, cleaning up agents..."
  agent_kill_all
  agent_set_status "$MANAGER_ID" "stopped"
}
trap cleanup EXIT INT TERM

# Phase 1: Generate the plan by running AI against the prompt
phase_plan() {
  ralph_log INFO "=== Phase 1: Planning ==="
  
  local plan_prompt="${RALPH_ROOT}/state/.manager-plan-prompt.md"
  local plan_template="${RALPH_ROOT}/templates/prompt-plan.md"
  
  # Build planning prompt
  cat > "$plan_prompt" << PLAN_EOF
You are the planning agent for Ralph Wiggum. Your job is to analyze the task and break it into discrete, implementable subtasks.

## The Task
$(cat "$PROMPT_FILE")

## Target Repository
Path: ${TARGET_REPO}

## Instructions
1. Analyze the task requirements thoroughly
2. Study the target repository structure if it exists
3. Break the work into 5-15 discrete subtasks, each independently implementable
4. Each subtask should be completable in a single focused session
5. Order subtasks by dependency (independent tasks first)
6. Output the plan as a JSON array of tasks

## Output Format
Output ONLY a JSON array (no markdown fences, no explanation). Each task object:
[
  {
    "title": "Short task title",
    "description": "Detailed description of what to implement, including file paths and acceptance criteria",
    "depends_on": [],
    "priority": "high|medium|low"
  }
]

Think carefully. Be specific about file paths and expected behavior.
PLAN_EOF

  local plan_output="${RALPH_ROOT}/state/plan-output.json"
  ralph_log INFO "Running AI planner..."
  
  local plan_exit=0
  (cd "$TARGET_REPO" && cat "$plan_prompt" | eval "$AI_COMMAND") > "$plan_output" 2>&1 || plan_exit=$?

  # Extract JSON array from output (handle markdown fences)
  local tasks_json
  tasks_json=$(sed -n '/^\[/,/^\]/p' "$plan_output" | head -1000)
  
  if [[ -z "$tasks_json" ]] || ! echo "$tasks_json" | jq empty 2>/dev/null; then
    # Try extracting from code fences
    tasks_json=$(sed -n '/```json/,/```/{/```/d;p}' "$plan_output" | head -1000)
  fi

  if [[ -z "$tasks_json" ]] || ! echo "$tasks_json" | jq empty 2>/dev/null; then
    ralph_log WARN "AI planner did not return valid JSON. Creating default tasks from prompt."
    tasks_json='[{"title":"Implement full task","description":"'"$(head -c 500 "$PROMPT_FILE")"'","depends_on":[],"priority":"high"}]'
  fi

  # Create tasks from plan
  local task_count
  task_count=$(echo "$tasks_json" | jq 'length')
  ralph_log INFO "Plan generated with $task_count tasks"

  local dep_map=()  # Maps plan index -> task ID for dependency resolution

  for i in $(seq 0 $((task_count - 1))); do
    local title description priority deps_str
    title=$(echo "$tasks_json" | jq -r ".[$i].title")
    description=$(echo "$tasks_json" | jq -r ".[$i].description")
    priority=$(echo "$tasks_json" | jq -r ".[$i].priority // \"medium\"")
    
    # Resolve dependencies (map plan indices to task IDs)
    deps_str=""
    local dep_indices
    dep_indices=$(echo "$tasks_json" | jq -r ".[$i].depends_on[]? // empty" 2>/dev/null)
    for dep_idx in $dep_indices; do
      if [[ "$dep_idx" =~ ^[0-9]+$ ]] && [[ -n "${dep_map[$dep_idx]:-}" ]]; then
        [[ -n "$deps_str" ]] && deps_str="${deps_str},"
        deps_str="${deps_str}${dep_map[$dep_idx]}"
      fi
    done

    local task_id
    task_id=$(task_create "$title" "$description" "$deps_str" "$MAX_RETRIES" "$priority")
    dep_map+=("$task_id")
  done

  ralph_log INFO "Created $task_count tasks in task list"
  echo "$tasks_json" > "${RALPH_ROOT}/state/plan.json"

  # Also write fix_plan.md in the target repo
  {
    echo "# Fix Plan (Generated by Ralph)"
    echo ""
    echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
    for i in $(seq 0 $((task_count - 1))); do
      local title description priority
      title=$(echo "$tasks_json" | jq -r ".[$i].title")
      description=$(echo "$tasks_json" | jq -r ".[$i].description")
      priority=$(echo "$tasks_json" | jq -r ".[$i].priority // \"medium\"")
      echo "## [$priority] $title"
      echo ""
      echo "$description"
      echo ""
    done
  } > "${TARGET_REPO}/fix_plan.md" 2>/dev/null || true
}

# Phase 2: Spawn implementer agents
phase_implement() {
  ralph_log INFO "=== Phase 2: Implementation ==="

  for i in $(seq 1 "$NUM_IMPLEMENTERS"); do
    spawn_implementer "$i" &
  done

  # Wait for implementers to claim and complete tasks
  monitor_progress "implement"
}

spawn_implementer() {
  local worker_num="$1"
  "${RALPH_ROOT}/bin/ralph-worker.sh" "$CONFIG_FILE" "$worker_num" "$RALPH_ROOT" "$TARGET_REPO"
}

# Phase 3: Spawn reviewer agents
phase_review() {
  ralph_log INFO "=== Phase 3: Review ==="

  # Move completed tasks to review status
  for task_file in "${RALPH_ROOT}/state/tasks"/task-*.json; do
    [[ -f "$task_file" ]] || continue
    local status task_id
    status=$(jq -r '.status' "$task_file")
    task_id=$(jq -r '.id' "$task_file")
    if [[ "$status" == "completed" ]]; then
      task_submit_for_review "$task_id"
    fi
  done

  for i in $(seq 1 "$NUM_REVIEWERS"); do
    spawn_reviewer "$i" &
  done

  monitor_progress "review"
}

spawn_reviewer() {
  local reviewer_num="$1"
  "${RALPH_ROOT}/bin/ralph-review.sh" "$CONFIG_FILE" "$reviewer_num" "$RALPH_ROOT" "$TARGET_REPO"
}

# Monitor progress, retrying failed tasks
monitor_progress() {
  local phase="$1"
  local check_interval=10
  local stall_count=0
  local max_stall=30  # Max checks with no progress before giving up

  while true; do
    sleep "$check_interval"
    agent_heartbeat "$MANAGER_ID"
    agent_cleanup

    local summary
    summary=$(task_summary)
    local pending in_progress completed review approved failed total
    pending=$(echo "$summary" | jq '.pending')
    in_progress=$(echo "$summary" | jq '.in_progress')
    completed=$(echo "$summary" | jq '.completed')
    review=$(echo "$summary" | jq '.review')
    approved=$(echo "$summary" | jq '.approved')
    failed=$(echo "$summary" | jq '.failed')
    total=$(echo "$summary" | jq '.total')

    ralph_log INFO "Progress: pending=$pending in_progress=$in_progress completed=$completed review=$review approved=$approved failed=$failed"

    # Check if this phase is done
    if [[ "$phase" == "implement" ]]; then
      if [[ $pending -eq 0 ]] && [[ $in_progress -eq 0 ]]; then
        ralph_log INFO "Implementation phase complete"
        break
      fi
    elif [[ "$phase" == "review" ]]; then
      if [[ $review -eq 0 ]] && [[ $in_progress -eq 0 ]]; then
        ralph_log INFO "Review phase complete"
        break
      fi
    fi

    # Detect stalling
    stall_count=$((stall_count + 1))
    if [[ $stall_count -ge $max_stall ]]; then
      ralph_log WARN "Progress stalled for $max_stall checks. Breaking out."
      break
    fi

    # Respawn dead workers
    local running_workers
    running_workers=$(agent_list_running "implementer" | jq 'length')
    if [[ "$phase" == "implement" ]] && [[ $pending -gt 0 ]] && [[ $running_workers -lt $NUM_IMPLEMENTERS ]]; then
      local needed=$((NUM_IMPLEMENTERS - running_workers))
      ralph_log INFO "Respawning $needed implementer(s)..."
      for i in $(seq 1 "$needed"); do
        spawn_implementer "$((running_workers + i))" &
      done
    fi

    local running_reviewers
    running_reviewers=$(agent_list_running "reviewer" | jq 'length')
    if [[ "$phase" == "review" ]] && [[ $review -gt 0 ]] && [[ $running_reviewers -lt $NUM_REVIEWERS ]]; then
      local needed=$((NUM_REVIEWERS - running_reviewers))
      ralph_log INFO "Respawning $needed reviewer(s)..."
      for i in $(seq 1 "$needed"); do
        spawn_reviewer "$((running_reviewers + i))" &
      done
    fi

    # Handle rejected tasks: re-queue for implementation
    for task_file in "${RALPH_ROOT}/state/tasks"/task-*.json; do
      [[ -f "$task_file" ]] || continue
      local task_status task_id attempt max_r
      task_status=$(jq -r '.status' "$task_file")
      task_id=$(jq -r '.id' "$task_file")
      attempt=$(jq -r '.attempt_count' "$task_file")
      max_r=$(jq -r '.max_retries' "$task_file")

      if [[ "$task_status" == "pending" ]] && [[ $attempt -gt 0 ]] && [[ $attempt -lt $max_r ]]; then
        ralph_log INFO "Task $task_id was rejected, re-queuing (attempt $attempt/$max_r)"
        stall_count=0  # Reset stall counter on activity
      fi
    done
  done
}

# Main orchestration loop
manager_loop() {
  local iteration=0

  while true; do
    iteration=$((iteration + 1))
    ralph_log INFO "====== Manager Iteration $iteration ======"

    if [[ $iteration -gt $MAX_ITERATIONS ]]; then
      ralph_log WARN "Manager max iterations ($MAX_ITERATIONS) reached"
      break
    fi

    # Phase 1: Plan (only first iteration or if tasks need replanning)
    if [[ $iteration -eq 1 ]]; then
      phase_plan
    fi

    # Phase 2: Implement
    phase_implement

    # Phase 3: Review
    phase_review

    # Check if all done
    if all_tasks_done; then
      local summary
      summary=$(task_summary)
      local approved failed
      approved=$(echo "$summary" | jq '.approved')
      failed=$(echo "$summary" | jq '.failed')

      ralph_log INFO "========================================="
      ralph_log INFO "All tasks processed!"
      ralph_log INFO "  Approved: $approved"
      ralph_log INFO "  Failed: $failed"
      ralph_log INFO "========================================="

      # Generate completion report
      {
        echo "# Ralph Completion Report"
        echo ""
        echo "Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
        echo "Iterations: $iteration"
        echo "Approved: $approved"
        echo "Failed: $failed"
        echo ""
        echo "## Tasks"
        task_list "all" | jq -r '.[] | "- [\(.status)] \(.title) (attempts: \(.attempt_count))"'
      } > "${RALPH_ROOT}/state/completion-report.md"

      if [[ $failed -eq 0 ]]; then
        echo "<promise>${COMPLETION_PROMISE}</promise>"
      fi
      break
    fi

    # If we have failed tasks that can still be retried, loop again
    local has_retryable=false
    for task_file in "${RALPH_ROOT}/state/tasks"/task-*.json; do
      [[ -f "$task_file" ]] || continue
      local status attempt max_r
      status=$(jq -r '.status' "$task_file")
      attempt=$(jq -r '.attempt_count' "$task_file")
      max_r=$(jq -r '.max_retries' "$task_file")
      if [[ "$status" == "pending" ]] && [[ $attempt -lt $max_r ]]; then
        has_retryable=true
        break
      fi
    done

    if [[ "$has_retryable" == "false" ]]; then
      ralph_log INFO "No more retryable tasks. Finishing."
      break
    fi

    ralph_log INFO "Retryable tasks remain. Starting next iteration..."
    sleep 5
  done

  agent_set_status "$MANAGER_ID" "completed"
}

manager_loop
