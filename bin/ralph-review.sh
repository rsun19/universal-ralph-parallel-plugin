#!/usr/bin/env bash
# Ralph Reviewer Agent - reviews completed tasks for quality

set -euo pipefail

CONFIG_FILE="${1:?Config file required}"
REVIEWER_NUM="${2:?Reviewer number required}"
RALPH_ROOT="${3:?Ralph root required}"
TARGET_REPO="${4:?Target repo required}"

source "${RALPH_ROOT}/lib/utils.sh"
source "${RALPH_ROOT}/lib/task-manager.sh"
source "${RALPH_ROOT}/lib/agent-registry.sh"
source "${RALPH_ROOT}/lib/comms.sh"

init_task_dir "$RALPH_ROOT"
init_agent_dir "$RALPH_ROOT"
init_msg_dir "$RALPH_ROOT"

REVIEWER_ID="review-${REVIEWER_NUM}-$(generate_id)"
agent_register "$REVIEWER_ID" "reviewer" "$$"

AI_COMMAND=$(config_get "$CONFIG_FILE" '.ai_tool_command' 'claude -p')
AI_TOOL=$(config_get "$CONFIG_FILE" '.ai_tool' 'claude-code')
CHECK_TESTS=$(config_get "$CONFIG_FILE" '.review.check_tests' 'true')
CHECK_PLACEHOLDERS=$(config_get "$CONFIG_FILE" '.review.check_placeholders' 'true')
CHECK_SPEC=$(config_get "$CONFIG_FILE" '.review.check_spec_compliance' 'true')
AUTO_APPROVE=$(config_get "$CONFIG_FILE" '.review.auto_approve_on_pass' 'false')

ADAPTER_SCRIPT="${RALPH_ROOT}/adapters/${AI_TOOL}/ralph-${AI_TOOL}-adapter.sh"
if [[ -f "$ADAPTER_SCRIPT" ]]; then
  source "$ADAPTER_SCRIPT"
  AI_COMMAND=$(get_adapter_command "$CONFIG_FILE" 2>/dev/null || echo "$AI_COMMAND")
fi

cleanup() {
  agent_set_status "$REVIEWER_ID" "stopped"
}
trap cleanup EXIT INT TERM

ralph_log INFO "Reviewer $REVIEWER_ID started (num=$REVIEWER_NUM)"

claim_review_task() {
  for task_file in "${RALPH_ROOT}/state/tasks"/task-*.json; do
    [[ -f "$task_file" ]] || continue
    local lock_file="${task_file}.lock"
    
    (
      flock -n 200 || exit 1
      local status
      status=$(jq -r '.status' "$task_file")
      if [[ "$status" == "review" ]]; then
        local now
        now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
        jq --arg assignee "$REVIEWER_ID" --arg now "$now" \
          '.status = "in_progress" | .assignee = $assignee | .updated_at = $now' \
          "$task_file" > "${task_file}.tmp.$$"
        mv "${task_file}.tmp.$$" "$task_file"
        jq -r '.id' "$task_file"
        exit 0
      fi
      exit 1
    ) 200>"$lock_file" && return 0
  done
  return 1
}

run_review() {
  local task_id="$1"

  ralph_log INFO "Reviewer $REVIEWER_ID: Reviewing task $task_id"
  agent_set_task "$REVIEWER_ID" "$task_id"

  local task_json title description
  task_json=$(task_get "$task_id")
  title=$(echo "$task_json" | jq -r '.title')
  description=$(echo "$task_json" | jq -r '.description')

  local review_prompt="${RALPH_ROOT}/state/reviewer-${REVIEWER_ID}-prompt.md"
  local review_template="${RALPH_ROOT}/templates/prompt-review.md"

  if [[ -f "$review_template" ]]; then
    sed \
      -e "s|{{TASK_TITLE}}|${title}|g" \
      -e "s|{{TASK_ID}}|${task_id}|g" \
      "$review_template" > "$review_prompt"
    {
      echo ""
      echo "## Task Description"
      echo "$description"
      echo ""
      echo "## Review Checklist"
      [[ "$CHECK_TESTS" == "true" ]] && echo "- [ ] Tests exist and pass"
      [[ "$CHECK_PLACEHOLDERS" == "true" ]] && echo "- [ ] No placeholder or TODO implementations"
      [[ "$CHECK_SPEC" == "true" ]] && echo "- [ ] Implementation matches the task description"
      echo "- [ ] Code quality is acceptable"
      echo "- [ ] No obvious bugs or regressions"
    } >> "$review_prompt"
  else
    cat > "$review_prompt" << REVIEW_EOF
You are a code reviewer for Ralph Wiggum. Review the implementation of this task.

## Task: ${title}
ID: ${task_id}

## Task Description
${description}

## Review Instructions
1. Study the recent changes in the repository (use git diff, git log)
2. Check that the implementation matches the task description
3. Verify tests exist and pass
4. Look for placeholder implementations, TODOs, or minimal stubs
5. Check for obvious bugs or regressions

## Review Checklist
$(if [[ "$CHECK_TESTS" == "true" ]]; then echo "- Tests exist and pass"; fi)
$(if [[ "$CHECK_PLACEHOLDERS" == "true" ]]; then echo "- No placeholder or TODO implementations"; fi)
$(if [[ "$CHECK_SPEC" == "true" ]]; then echo "- Implementation matches the task description"; fi)
- Code quality is acceptable
- No obvious bugs or regressions

## Output Format
Output your decision as JSON (no markdown fences):
{
  "decision": "approve" or "reject",
  "summary": "Brief summary of findings",
  "issues": ["List of specific issues found, if any"]
}

Be thorough but fair. Only reject for real issues, not style preferences.
REVIEW_EOF
  fi

  local review_output="${RALPH_ROOT}/state/logs/${task_id}-review.log"
  local review_exit=0
  (cd "$TARGET_REPO" && cat "$review_prompt" | eval "$AI_COMMAND") > "$review_output" 2>&1 || review_exit=$?

  local decision="approve"
  local review_summary=""
  local review_json

  review_json=$(sed -n '/^{/,/^}/p' "$review_output" 2>/dev/null | head -50)
  if [[ -n "$review_json" ]] && echo "$review_json" | jq empty 2>/dev/null; then
    decision=$(echo "$review_json" | jq -r '.decision // "approve"')
    review_summary=$(echo "$review_json" | jq -r '(.summary // "") + " Issues: " + ((.issues // []) | join("; "))')
  else
    review_json=$(sed -n '/```json/,/```/{/```/d;p}' "$review_output" 2>/dev/null | head -50)
    if [[ -n "$review_json" ]] && echo "$review_json" | jq empty 2>/dev/null; then
      decision=$(echo "$review_json" | jq -r '.decision // "approve"')
      review_summary=$(echo "$review_json" | jq -r '(.summary // "") + " Issues: " + ((.issues // []) | join("; "))')
    else
      if grep -qi "reject" "$review_output" 2>/dev/null; then
        decision="reject"
        review_summary="Reviewer flagged issues (see full log)"
      else
        decision="approve"
        review_summary="Review passed"
      fi
    fi
  fi

  ralph_log INFO "Reviewer $REVIEWER_ID: Task $task_id -> $decision"

  if [[ "$decision" == "approve" ]]; then
    task_approve "$task_id"
    msg_send "$REVIEWER_ID" "manager" "feedback" "Task $task_id APPROVED: $review_summary"
  else
    task_reject "$task_id" "$review_summary"
    msg_send "$REVIEWER_ID" "manager" "feedback" "Task $task_id REJECTED: $review_summary"
  fi

  agent_set_task "$REVIEWER_ID" ""
}

# Main reviewer loop
while true; do
  agent_heartbeat "$REVIEWER_ID"

  task_id=$(claim_review_task 2>/dev/null || echo "")

  if [[ -z "$task_id" ]]; then
    ralph_log INFO "Reviewer $REVIEWER_ID: No tasks to review, shutting down"
    break
  fi

  run_review "$task_id"
done

ralph_log INFO "Reviewer $REVIEWER_ID finished"
agent_set_status "$REVIEWER_ID" "idle"
