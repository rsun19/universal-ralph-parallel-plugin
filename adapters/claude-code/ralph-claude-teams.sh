#!/usr/bin/env bash
# Claude Code Agent Teams native mode adapter
# Generates the prompt to start an agent team within Claude Code

set -euo pipefail

RALPH_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${RALPH_ROOT}/lib/utils.sh"

CONFIG_FILE="${1:?Config file required}"
PROMPT_FILE="${2:?Prompt file required}"

NUM_IMPLEMENTERS=$(config_get "$CONFIG_FILE" '.team.implementers' '3')
NUM_REVIEWERS=$(config_get "$CONFIG_FILE" '.team.reviewers' '2')
MAX_RETRIES=$(config_get "$CONFIG_FILE" '.team.max_retries_per_task' '3')
TARGET_REPO=$(config_get "$CONFIG_FILE" '.target_repo' '.')
TEAMMATE_MODE=$(config_get "$CONFIG_FILE" '.claude_teams.teammate_mode' 'in-process')

PROMPT_CONTENT=$(cat "$PROMPT_FILE")

# Generate the team creation prompt for Claude Code
cat << TEAM_EOF
Create an agent team for a Ralph Wiggum iterative development session.

## The Task
${PROMPT_CONTENT}

## Team Structure
Create the following teammates:

### Implementers (${NUM_IMPLEMENTERS})
$(for i in $(seq 1 "$NUM_IMPLEMENTERS"); do
echo "- Spawn teammate 'impl-${i}' using the implementer agent type. Require plan approval before they make changes."
done)

### Reviewers (${NUM_REVIEWERS})
$(for i in $(seq 1 "$NUM_REVIEWERS"); do
echo "- Spawn teammate 'reviewer-${i}' using the reviewer agent type."
done)

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
- Only approve implementer plans that include test coverage
TEAM_EOF
