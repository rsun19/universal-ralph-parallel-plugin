#!/usr/bin/env bash
# Ralph Worker Agent - claims and executes implementation tasks

set -euo pipefail

CONFIG_FILE="${1:?Config file required}"
WORKER_NUM="${2:?Worker number required}"
RALPH_ROOT="${3:?Ralph root required}"
TARGET_REPO="${4:?Target repo required}"

source "${RALPH_ROOT}/lib/utils.sh"
source "${RALPH_ROOT}/lib/task-manager.sh"
source "${RALPH_ROOT}/lib/agent-registry.sh"
source "${RALPH_ROOT}/lib/comms.sh"

init_task_dir "$RALPH_ROOT"
init_agent_dir "$RALPH_ROOT"
init_msg_dir "$RALPH_ROOT"

WORKER_ID="impl-${WORKER_NUM}-$(generate_id)"
agent_register "$WORKER_ID" "implementer" "$$"

AI_COMMAND=$(config_get "$CONFIG_FILE" '.ai_tool_command' 'claude -p')
AI_TOOL=$(config_get "$CONFIG_FILE" '.ai_tool' 'claude-code')
MAX_TASK_ITERATIONS=$(config_get "$CONFIG_FILE" '.loop.max_iterations' '50')
COMMIT_ON_SUCCESS=$(config_get "$CONFIG_FILE" '.loop.commit_on_success' 'false')

ADAPTER_SCRIPT="${RALPH_ROOT}/adapters/${AI_TOOL}/ralph-${AI_TOOL}-adapter.sh"
if [[ -f "$ADAPTER_SCRIPT" ]]; then
  source "$ADAPTER_SCRIPT"
  AI_COMMAND=$(get_adapter_command "$CONFIG_FILE" 2>/dev/null || echo "$AI_COMMAND")
fi

cleanup() {
  agent_set_status "$WORKER_ID" "stopped"
}
trap cleanup EXIT INT TERM

ralph_log INFO "Worker $WORKER_ID started (num=$WORKER_NUM)"

run_task() {
  local task_id="$1"

  ralph_log INFO "Worker $WORKER_ID claimed task: $task_id"
  agent_set_task "$WORKER_ID" "$task_id"

  local task_json title description review_feedback
  task_json=$(task_get "$task_id")
  title=$(echo "$task_json" | jq -r '.title')
  description=$(echo "$task_json" | jq -r '.description')
  review_feedback=$(echo "$task_json" | jq -r '.review_feedback // ""')

  local impl_prompt="${RALPH_ROOT}/state/worker-${WORKER_ID}-prompt.md"
  local impl_template="${RALPH_ROOT}/templates/prompt-implement.md"

  if [[ -f "$impl_template" ]]; then
    sed \
      -e "s|{{TASK_TITLE}}|${title}|g" \
      -e "s|{{TASK_ID}}|${task_id}|g" \
      "$impl_template" > "$impl_prompt"
    
    {
      echo ""
      echo "## Task Description"
      echo "$description"
      echo ""
      if [[ -n "$review_feedback" ]]; then
        echo "## Previous Review Feedback (MUST ADDRESS)"
        echo "$review_feedback"
        echo ""
      fi
      echo "## Target Repository"
      echo "Path: ${TARGET_REPO}"
      echo ""
      echo "## Completion Signal"
      echo "When the task is fully implemented and tests pass, output: <promise>TASK_DONE</promise>"
    } >> "$impl_prompt"
  else
    cat > "$impl_prompt" << IMPL_EOF
You are an implementation agent for Ralph Wiggum. Complete this task fully.

## Task: ${title}
ID: ${task_id}

## Description
${description}

$(if [[ -n "$review_feedback" ]]; then echo "## Previous Review Feedback (MUST ADDRESS)"; echo "$review_feedback"; fi)

## Instructions
1. Study the codebase before making changes (don't assume something isn't implemented)
2. Implement the task fully - NO placeholders or minimal implementations
3. Write tests for your implementation
4. Run tests and fix any failures
5. After implementing, run tests for the unit of code you improved
6. When complete, output: <promise>TASK_DONE</promise>

## CRITICAL RULES
- DO NOT implement placeholders. Full implementations only.
- If tests fail, debug and fix them.
- If you find existing code that already handles this, extend rather than duplicate.
- Search the codebase before assuming something doesn't exist.
IMPL_EOF
  fi

  local task_output="${RALPH_ROOT}/state/logs/${task_id}-output.log"
  mkdir -p "$(dirname "$task_output")"

  local iteration=0
  local task_completed=false

  while [[ $iteration -lt $MAX_TASK_ITERATIONS ]]; do
    iteration=$((iteration + 1))
    ralph_log INFO "Worker $WORKER_ID: Task $task_id iteration $iteration"
    agent_heartbeat "$WORKER_ID"

    local iter_output="${RALPH_ROOT}/state/logs/${task_id}-iter-${iteration}.log"
    local iter_exit=0
    (cd "$TARGET_REPO" && cat "$impl_prompt" | eval "$AI_COMMAND") > "$iter_output" 2>&1 || iter_exit=$?

    if grep -qF "TASK_DONE" "$iter_output" 2>/dev/null; then
      ralph_log INFO "Worker $WORKER_ID: Task $task_id completed at iteration $iteration"
      task_completed=true

      if [[ "$COMMIT_ON_SUCCESS" == "true" ]]; then
        (cd "$TARGET_REPO" && git add -A && git commit -m "Ralph: ${title} [${task_id}]" 2>/dev/null) || true
      fi
      break
    fi

    sleep 2
  done

  if [[ "$task_completed" == "true" ]]; then
    task_complete "$task_id"
    msg_send "$WORKER_ID" "manager" "status_update" "Task $task_id completed: $title"
  else
    ralph_log WARN "Worker $WORKER_ID: Task $task_id did not complete after $iteration iterations"
    task_update "$task_id" "status" "completed"
    msg_send "$WORKER_ID" "manager" "status_update" "Task $task_id reached max iterations without explicit completion"
  fi

  agent_set_task "$WORKER_ID" ""
}

# Main worker loop: claim tasks and execute them
while true; do
  agent_heartbeat "$WORKER_ID"

  task_id=$(task_claim "$WORKER_ID" 2>/dev/null || echo "")

  if [[ -z "$task_id" ]]; then
    ralph_log INFO "Worker $WORKER_ID: No tasks available, shutting down"
    break
  fi

  run_task "$task_id"
done

ralph_log INFO "Worker $WORKER_ID finished"
agent_set_status "$WORKER_ID" "idle"
