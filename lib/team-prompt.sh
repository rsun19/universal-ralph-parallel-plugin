#!/usr/bin/env bash
# Generates the agent team prompt — tool-agnostic.
#
# All modern AI coding CLIs (Claude Code, Cursor, Copilot) support
# spawning parallel sub-agents from a prompt. This module builds the
# team prompt that any CLI can use.

# build_team_prompt config_file prompt_file
#   Reads config for team size, target repo, etc.
#   Reads the user prompt from prompt_file.
#   Prints the assembled team prompt to stdout.
build_team_prompt() {
  local config_file="$1"
  local prompt_file="$2"

  local num_impl num_rev max_retries target_repo prompt_content
  num_impl=$(config_get "$config_file" '.team.implementers' '3')
  num_rev=$(config_get "$config_file" '.team.reviewers' '2')
  max_retries=$(config_get "$config_file" '.team.max_retries_per_task' '3')
  target_repo=$(config_get "$config_file" '.target_repo' '.')
  prompt_content=$(cat "$prompt_file")

  local impl_list=""
  for i in $(seq 1 "$num_impl"); do
    impl_list="${impl_list}- Spawn teammate 'impl-${i}' using the implementer agent type. Require plan approval before they make changes.
"
  done

  local reviewer_list=""
  for i in $(seq 1 "$num_rev"); do
    reviewer_list="${reviewer_list}- Spawn teammate 'reviewer-${i}' using the reviewer agent type.
"
  done

  cat <<TEAM_EOF
Create an agent team for a Ralph Wiggum iterative development session.

## The Task
${prompt_content}

## Team Structure
Create the following teammates:

### Implementers (${num_impl})
${impl_list}
### Reviewers (${num_rev})
${reviewer_list}
## Workflow
1. Break the task into 5-15 discrete subtasks in the shared task list
2. Assign tasks to implementers
3. Implementers plan their approach (you must approve before they code)
4. Once implemented, assign the task to a reviewer
5. If rejected, update the task with feedback and reassign to an implementer
6. Max retries per task: ${max_retries}
7. When all tasks are approved, output: <promise>ALL_TASKS_COMPLETE</promise>

## Quality Standards
- No placeholder or stub implementations
- All code must have tests
- Tests must pass
- Reviewers verify spec compliance

## Target Repository
${target_repo}

## Manager Rules
- Wait for teammates to complete their tasks before proceeding
- If a task is stuck, provide specific guidance
- Keep fix_plan.md updated in the target repo
- Broadcast progress updates periodically
- Only approve implementer plans that include test coverage
TEAM_EOF
}
