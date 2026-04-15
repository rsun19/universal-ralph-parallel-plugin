#!/usr/bin/env bash
# Claude Code Agent Teams native mode adapter
# Generates the team prompt and pipes it to claude

set -euo pipefail

RALPH_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${RALPH_ROOT}/lib/utils.sh"

CONFIG_FILE="${1:?Config file required}"
PROMPT_FILE="${2:?Prompt file required}"

NUM_IMPLEMENTERS=$(config_get "$CONFIG_FILE" '.team.implementers' '3')
NUM_REVIEWERS=$(config_get "$CONFIG_FILE" '.team.reviewers' '2')
MAX_RETRIES=$(config_get "$CONFIG_FILE" '.team.max_retries_per_task' '3')
TARGET_REPO=$(config_get "$CONFIG_FILE" '.target_repo' '.')
MODEL=$(config_get "$CONFIG_FILE" '.model' 'sonnet')
ALLOW_ALL=$(config_get "$CONFIG_FILE" '.allow_all' 'false')

PROMPT_CONTENT=$(cat "$PROMPT_FILE")

IMPL_LIST=""
for i in $(seq 1 "$NUM_IMPLEMENTERS"); do
  IMPL_LIST="${IMPL_LIST}- Spawn teammate 'impl-${i}' using the implementer agent type. Require plan approval before they make changes.
"
done

REVIEWER_LIST=""
for i in $(seq 1 "$NUM_REVIEWERS"); do
  REVIEWER_LIST="${REVIEWER_LIST}- Spawn teammate 'reviewer-${i}' using the reviewer agent type.
"
done

TEAM_PROMPT="Create an agent team for a Ralph Wiggum iterative development session.

## The Task
${PROMPT_CONTENT}

## Team Structure
Create the following teammates:

### Implementers (${NUM_IMPLEMENTERS})
${IMPL_LIST}
### Reviewers (${NUM_REVIEWERS})
${REVIEWER_LIST}
## Workflow
1. Break the task into 5-15 discrete subtasks in the shared task list
2. Assign tasks to implementers
3. Implementers plan their approach (you must approve before they code)
4. Once implemented, assign the task to a reviewer
5. If rejected, update the task with feedback and reassign to an implementer
6. Max retries per task: ${MAX_RETRIES}
7. When all tasks are approved, output: <promise>ALL_TASKS_COMPLETE</promise>

## Quality Standards
- No placeholder or stub implementations
- All code must have tests
- Tests must pass
- Reviewers verify spec compliance

## Target Repository
${TARGET_REPO}

## Manager Rules
- Wait for teammates to complete their tasks before proceeding
- If a task is stuck, provide specific guidance
- Keep fix_plan.md updated in the target repo
- Broadcast progress updates periodically
- Only approve implementer plans that include test coverage"

# Build the claude command
CMD="claude"
if [[ "$ALLOW_ALL" == "true" ]]; then
  CMD="${CMD} --dangerously-skip-permissions"
fi
if [[ -n "$MODEL" ]] && [[ "$MODEL" != "null" ]]; then
  CMD="${CMD} --model \"${MODEL}\""
fi
CMD="${CMD} -p"

LOG_DIR="${RALPH_ROOT}/state/logs/claude-teams"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/session-$(date +%s).log"

ralph_log INFO "Running Claude Code Agent Teams: ${CMD%% *}..."
ralph_log INFO "Live log: $LOG_FILE"

cd "$TARGET_REPO"
printf '%s\n' "$TEAM_PROMPT" | eval "$CMD" 2>&1 | tee "$LOG_FILE"
