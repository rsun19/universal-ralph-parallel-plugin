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

  local ralph_root
  ralph_root=$(resolve_ralph_root)
  local template="${ralph_root}/state/templates/prompt-team.md"

  if [[ -f "$template" ]]; then
    render_template "$template" \
      PROMPT_CONTENT "$prompt_content" \
      NUM_IMPLEMENTERS "$num_impl" \
      IMPLEMENTER_LIST "$impl_list" \
      NUM_REVIEWERS "$num_rev" \
      REVIEWER_LIST "$reviewer_list" \
      MAX_RETRIES "$max_retries" \
      TARGET_REPO "$target_repo"
  else
    ralph_die "Missing template: $template (run 'ralph templates' to see all templates)"
  fi
}
