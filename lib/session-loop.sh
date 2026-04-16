#!/usr/bin/env bash
# Interactive session loop engine — multi-turn AI sessions with a manager AI
#
# Two-level loop:
#   Inner (turns): The AI works on the task; a manager AI reads each turn's
#                  output and responds (approvals, guidance, answers) on the
#                  user's behalf. Bounded by the "turns" config key.
#   Outer (retries): After the inner loop finishes, the manager AI reads the
#                    git diff against the original prompt + plan and decides
#                    whether requirements are met. If not, a fresh session is
#                    started with specific feedback. Bounded by
#                    loop.max_iterations.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"



# ---------------------------------------------------------------------------
# session_start — Run the first turn of a new session
#   Args: initial_cmd  prompt_text  target_dir  output_file
#   Writes raw JSON output to output_file.
#   Prints the session_id to stdout (empty string on failure).
# ---------------------------------------------------------------------------
session_start() {
  local initial_cmd="$1"
  local prompt_text="$2"
  local target_dir="$3"
  local output_file="$4"

  local exit_code=0
  (
    cd "$target_dir"
    printf '%s\n' "$prompt_text" | eval "$initial_cmd"
  ) > "$output_file" 2>&1 || exit_code=$?

  local session_id=""
  if [[ -f "$output_file" ]]; then
    session_id=$(jq -r '.session_id // empty' "$output_file" 2>/dev/null || true)
  fi

  echo "$session_id"
  return $exit_code
}

# ---------------------------------------------------------------------------
# session_resume — Send a follow-up message to an existing session
#   Args: resume_cmd  message  target_dir  output_file
#   The resume_cmd already contains --resume SESSION_ID.
#   Writes raw output to output_file.
# ---------------------------------------------------------------------------
session_resume() {
  local resume_cmd="$1"
  local message="$2"
  local target_dir="$3"
  local output_file="$4"

  local exit_code=0
  (
    cd "$target_dir"
    printf '%s\n' "$message" | eval "$resume_cmd"
  ) > "$output_file" 2>&1 || exit_code=$?

  return $exit_code
}

# ---------------------------------------------------------------------------
# extract_text — Pull human-readable text from AI output (JSON or plain)
#   Args: output_file
#   Prints the text content to stdout.
# ---------------------------------------------------------------------------
extract_text() {
  local output_file="$1"

  if [[ ! -f "$output_file" ]]; then
    echo ""
    return
  fi

  local text=""
  text=$(jq -r '.result // empty' "$output_file" 2>/dev/null || true)
  if [[ -z "$text" ]]; then
    text=$(cat "$output_file")
  fi
  echo "$text"
}

# ---------------------------------------------------------------------------
# check_api_error — Detect fatal API errors in turn output.
#   Args: turn_text
#   Returns 0 if a fatal error is detected, 1 otherwise.
#   Prints the error message to stderr.
# ---------------------------------------------------------------------------
check_api_error() {
  local text="$1"
  local error_pattern

  for error_pattern in \
    "API Error: 4" \
    "API Error: 5" \
    "error.*was not found" \
    "model.*not found" \
    "does not have access" \
    "authentication failed" \
    "invalid.*api.key" \
    "rate limit exceeded" \
    "quota exceeded" \
    "PERMISSION_DENIED" \
    "UNAUTHENTICATED" \
    "NOT_FOUND" \
  ; do
    if echo "$text" | grep -qiE "$error_pattern" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# manager_respond — Ask the manager AI what to say next
#   Args: manager_cmd  session_output  original_prompt  plan_text  target_dir
#   Prints the manager's response to stdout.
# ---------------------------------------------------------------------------
manager_respond() {
  local manager_cmd="$1"
  local session_output="$2"
  local original_prompt="$3"
  local plan_text="$4"
  local target_dir="$5"

  local ralph_root
  ralph_root=$(resolve_ralph_root)
  local template="${ralph_root}/state/templates/prompt-manager-respond.md"

  local mgr_prompt
  if [[ -f "$template" ]]; then
    mgr_prompt=$(render_template "$template" \
      ORIGINAL_PROMPT "$original_prompt" \
      PLAN_TEXT "${plan_text:-Not yet generated.}" \
      SESSION_OUTPUT "$session_output")
  else
    ralph_die "Missing template: $template"
  fi

  local mgr_output=""
  mgr_output=$(cd "$target_dir" && printf '%s\n' "$mgr_prompt" | eval "$manager_cmd" 2>/dev/null) || true

  local response=""
  response=$(echo "$mgr_output" | jq -r '.result // empty' 2>/dev/null || true)
  if [[ -z "$response" ]]; then
    response="$mgr_output"
  fi

  if [[ -z "$response" ]]; then
    response="Continue with the current plan."
  fi

  echo "$response"
}

# ---------------------------------------------------------------------------
# verify_completion — Manager AI checks git diff against requirements
#   Args: manager_cmd  git_diff  original_prompt  plan_text  target_dir
#   Prints "COMPLETE" or a description of what's missing.
# ---------------------------------------------------------------------------
verify_completion() {
  local manager_cmd="$1"
  local git_diff="$2"
  local original_prompt="$3"
  local plan_text="$4"
  local target_dir="$5"

  local ralph_root
  ralph_root=$(resolve_ralph_root)
  local template="${ralph_root}/state/templates/prompt-verify.md"

  local verify_prompt
  if [[ -f "$template" ]]; then
    verify_prompt=$(render_template "$template" \
      ORIGINAL_PROMPT "$original_prompt" \
      PLAN_TEXT "${plan_text:-No plan was generated.}" \
      GIT_DIFF "$git_diff")
  else
    ralph_die "Missing template: $template"
  fi

  local verify_output=""
  verify_output=$(cd "$target_dir" && printf '%s\n' "$verify_prompt" | eval "$manager_cmd" 2>/dev/null) || true

  local verdict=""
  verdict=$(echo "$verify_output" | jq -r '.result // empty' 2>/dev/null || true)
  if [[ -z "$verdict" ]]; then
    verdict="$verify_output"
  fi

  if [[ -z "$verdict" ]]; then
    verdict="INCOMPLETE"
  fi

  echo "$verdict"
}

# ---------------------------------------------------------------------------
# session_loop — Two-level loop: inner turns + outer retries
#   Args: config_file  prompt_file  team_prompt  ralph_root
# ---------------------------------------------------------------------------
session_loop() {
  local config_file="$1"
  local prompt_file="$2"
  local team_prompt="$3"
  local ralph_root="$4"

  require_jq

  local target_dir max_turns max_retries completion_promise
  local ai_tool model allow_all manager_model
  target_dir=$(config_get "$config_file" '.target_repo' '.')
  [[ "$target_dir" != /* ]] && target_dir="$(cd "$target_dir" && pwd)"
  max_turns=$(config_get "$config_file" '.turns' '50')
  max_retries=$(config_get "$config_file" '.loop.max_iterations' '3')
  completion_promise=$(config_get "$config_file" '.loop.completion_promise' 'ALL_TASKS_COMPLETE')
  ai_tool=$(config_get "$config_file" '.ai_tool' 'claude-code')
  model=$(config_get "$config_file" '.model' 'sonnet')
  allow_all=$(config_get "$config_file" '.allow_all' 'false')
  manager_model=$(config_get "$config_file" '.manager_model' 'sonnet')

  # Source adapter for session commands
  local adapter_script="${ralph_root}/adapters/${ai_tool}/ralph-${ai_tool}-adapter.sh"
  if [[ -f "$adapter_script" ]]; then
    source "$adapter_script"
  fi

  # Build manager AI command (lightweight, always one-shot -p)
  local manager_cmd
  if type get_manager_command &>/dev/null; then
    manager_cmd=$(get_manager_command "$config_file")
  else
    manager_cmd=$(get_adapter_command "$config_file" 2>/dev/null || echo "claude -p")
  fi

  local original_prompt
  original_prompt=$(cat "$prompt_file")

  local state_dir="${RALPH_SESSION_DIR:-${ralph_root}/state}"
  local session_id="${RALPH_SESSION_ID:-default}"
  local log_base="${state_dir}/logs/agent-teams/${session_id}"
  mkdir -p "$log_base"

  local attempt=0
  local overall_success=false
  local plan_text=""
  local retry_context=""

  # ===================== OUTER LOOP (retries) =====================
  while [[ $attempt -lt $max_retries ]]; do
    attempt=$((attempt + 1))
    local attempt_dir="${log_base}/attempt-${attempt}"
    mkdir -p "$attempt_dir"

    ralph_log INFO "=== Attempt ${attempt}/${max_retries} ==="

    # Build the prompt for this attempt
    local effective_prompt="$team_prompt"
    if [[ -n "$retry_context" ]]; then
      effective_prompt="${team_prompt}

## Retry Context (Attempt ${attempt})
The previous attempt did not fully complete the requirements. Here is what was missing:

${retry_context}

Please address these specific gaps in addition to the original requirements."
    fi

    # Get initial command (no --resume)
    local initial_cmd
    if type get_initial_command &>/dev/null; then
      initial_cmd=$(get_initial_command "$config_file")
    else
      initial_cmd=$(get_adapter_command "$config_file" 2>/dev/null || echo "claude --output-format json -p")
    fi

    # =================== INNER LOOP (turns) ===================
    local turn=0
    local session_id=""
    local promise_found=false
    local stall_count=0

    # -- Turn 1: start session --
    turn=1
    ralph_log INFO "  Turn ${turn}/${max_turns}: Starting session..."
    local turn_output="${attempt_dir}/turn-$(printf '%02d' $turn).json"

    local t_start=$SECONDS
    session_id=$(session_start "$initial_cmd" "$effective_prompt" "$target_dir" "$turn_output") || true
    local t_elapsed=$(( SECONDS - t_start ))

    if [[ -z "$session_id" ]]; then
      ralph_log ERROR "  Failed to start AI session (${t_elapsed}s). No session ID returned."
      ralph_log ERROR ""
      ralph_log ERROR "  Possible causes:"
      ralph_log ERROR "    - The AI tool command failed or isn't installed"
      ralph_log ERROR "    - The model is not supported by the configured tool"
      ralph_log ERROR "    - The AI tool returned an error instead of JSON"
      ralph_log ERROR ""
      ralph_log ERROR "  AI tool: ${ai_tool}"
      ralph_log ERROR "  Command: ${initial_cmd}"
      ralph_log ERROR ""
      if [[ -f "$turn_output" ]]; then
        local err_output
        err_output=$(head -c 500 "$turn_output")
        if [[ -n "$err_output" ]]; then
          ralph_log ERROR "  Output from AI tool:"
          ralph_log ERROR "  ---"
          echo "$err_output" | while IFS= read -r line; do
            ralph_log ERROR "  $line"
          done
          ralph_log ERROR "  ---"
        fi
      fi
      ralph_log ERROR ""
      ralph_log ERROR "  Try: ralph start --cli claude-code --model sonnet"
      return 1
    fi

    ralph_log INFO "  Session ID: ${session_id}  (${t_elapsed}s)"

    local turn_text
    turn_text=$(extract_text "$turn_output")

    # Save human-readable log
    echo "$turn_text" > "${attempt_dir}/turn-$(printf '%02d' $turn).log"

    # Check for fatal API errors
    if check_api_error "$turn_text"; then
      ralph_log ERROR "  Fatal API error detected on turn ${turn}. Aborting session."
      ralph_log ERROR ""
      echo "$turn_text" | head -5 | while IFS= read -r line; do
        ralph_log ERROR "  $line"
      done
      ralph_log ERROR ""
      ralph_log ERROR "  Check your model and tool configuration:"
      ralph_log ERROR "    AI tool: ${ai_tool}"
      ralph_log ERROR "    Model:   ${model}"
      ralph_log ERROR ""
      ralph_log ERROR "  Try: ralph start --model sonnet"
      return 1
    fi

    # Capture the plan from turn 1 for verification later
    if [[ $attempt -eq 1 ]]; then
      plan_text="$turn_text"
    fi

    # Check completion promise
    if [[ -n "$completion_promise" ]] && echo "$turn_text" | grep -qF "$completion_promise" 2>/dev/null; then
      ralph_log INFO "  Completion promise found on turn ${turn}"
      promise_found=true
    fi

    # -- Subsequent turns --
    while [[ "$promise_found" != "true" ]] && [[ $turn -lt $max_turns ]]; do
      turn=$((turn + 1))

      if [[ -z "$session_id" ]]; then
        ralph_log WARN "  No session ID — cannot resume. Ending inner loop."
        break
      fi

      # Ask manager AI what to say
      local t_mgr=$SECONDS
      ralph_log INFO "  Turn ${turn}/${max_turns}: Manager AI generating response..."
      local mgr_response
      mgr_response=$(manager_respond "$manager_cmd" "$turn_text" "$original_prompt" "$plan_text" "$target_dir")
      local t_mgr_elapsed=$(( SECONDS - t_mgr ))
      echo "$mgr_response" > "${attempt_dir}/manager-$(printf '%02d' $turn).log"
      ralph_log INFO "  Manager (${t_mgr_elapsed}s): $(echo "$mgr_response" | head -1 | cut -c1-80)..."

      # Resume session with manager's response
      local resume_cmd
      if type get_session_command &>/dev/null; then
        resume_cmd=$(get_session_command "$config_file" "$session_id")
      else
        resume_cmd="claude --resume \"${session_id}\" --output-format json -p"
      fi

      turn_output="${attempt_dir}/turn-$(printf '%02d' $turn).json"
      local t_resume=$SECONDS
      ralph_log INFO "  Turn ${turn}/${max_turns}: Resuming session..."
      session_resume "$resume_cmd" "$mgr_response" "$target_dir" "$turn_output" || true
      local t_resume_elapsed=$(( SECONDS - t_resume ))
      ralph_log INFO "  Turn ${turn}/${max_turns}: Complete (resume: ${t_resume_elapsed}s, total turn: $(( t_mgr_elapsed + t_resume_elapsed ))s)"

      turn_text=$(extract_text "$turn_output")
      echo "$turn_text" > "${attempt_dir}/turn-$(printf '%02d' $turn).log"

      # Check for fatal API errors
      if check_api_error "$turn_text"; then
        ralph_log ERROR "  Fatal API error detected on turn ${turn}. Aborting session."
        ralph_log ERROR ""
        echo "$turn_text" | head -5 | while IFS= read -r line; do
          ralph_log ERROR "  $line"
        done
        ralph_log ERROR ""
        ralph_log ERROR "  Check your model and tool configuration:"
        ralph_log ERROR "    AI tool: ${ai_tool}"
        ralph_log ERROR "    Model:   ${model}"
        ralph_log ERROR ""
        ralph_log ERROR "  Try: ralph start --model sonnet"
        return 1
      fi

      # Check completion promise
      if [[ -n "$completion_promise" ]] && echo "$turn_text" | grep -qF "$completion_promise" 2>/dev/null; then
        ralph_log INFO "  Completion promise found on turn ${turn}"
        promise_found=true
        break
      fi

      # Stall detection: if output is empty or very short, increment counter
      if [[ ${#turn_text} -lt 20 ]]; then
        stall_count=$((stall_count + 1))
        if [[ $stall_count -ge 3 ]]; then
          ralph_log WARN "  Session stalled (3 consecutive empty/short outputs). Ending inner loop."
          break
        fi
      else
        stall_count=0
      fi

      sleep 2
    done

    ralph_log INFO "  Inner loop finished: ${turn} turns, promise_found=${promise_found}"

    # =================== VERIFICATION ===================
    ralph_log INFO "  Verifying completion via git diff..."

    local git_diff=""
    git_diff=$(cd "$target_dir" && git diff HEAD 2>/dev/null || true)
    if [[ -z "$git_diff" ]]; then
      git_diff=$(cd "$target_dir" && git diff 2>/dev/null || true)
    fi

    local untracked=""
    untracked=$(cd "$target_dir" && git ls-files --others --exclude-standard 2>/dev/null || true)
    if [[ -n "$untracked" ]]; then
      git_diff="${git_diff}

--- UNTRACKED FILES ---
${untracked}"
    fi

    if [[ -z "$git_diff" ]]; then
      git_diff="(no changes detected in working tree)"
    fi

    # Truncate very large diffs to avoid blowing up the manager prompt
    local diff_lines
    diff_lines=$(echo "$git_diff" | wc -l | tr -d ' ')
    if [[ $diff_lines -gt 500 ]]; then
      git_diff="$(echo "$git_diff" | head -500)

... (truncated, ${diff_lines} total lines) ..."
    fi

    local verdict
    verdict=$(verify_completion "$manager_cmd" "$git_diff" "$original_prompt" "$plan_text" "$target_dir")
    echo "$verdict" > "${attempt_dir}/verification.log"
    ralph_log INFO "  Verification verdict: $(echo "$verdict" | head -1)"

    if [[ "$(echo "$verdict" | head -1 | tr -d '[:space:]')" == "COMPLETE" ]]; then
      ralph_log INFO "=== Requirements verified as COMPLETE on attempt ${attempt} ==="
      overall_success=true
      break
    fi

    # Not complete — prepare retry context
    retry_context="$verdict"
    ralph_log WARN "  Requirements not fully met. Will retry with feedback."
    sleep 3
  done

  # ===================== FINAL REPORT =====================
  if [[ "$overall_success" == "true" ]]; then
    ralph_log INFO "Session loop completed successfully after ${attempt} attempt(s)."
    echo "<promise>${completion_promise}</promise>"
  else
    ralph_log WARN "Session loop exhausted ${max_retries} attempts without full verification."
    ralph_log INFO "Logs: ${log_base}/"
  fi

  # ===================== NEXT STEPS =====================
  _print_merge_instructions "$target_dir"

  if [[ "$overall_success" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

_print_merge_instructions() {
  local worktree_dir="$1"
  local session_dir="${RALPH_SESSION_DIR:-}"
  [[ -z "$session_dir" ]] && return

  local meta="${session_dir}/session.json"
  [[ ! -f "$meta" ]] && return

  local orig_repo branch
  orig_repo=$(jq -r '.original_target_repo // empty' "$meta" 2>/dev/null)
  branch=$(jq -r '.branch // empty' "$meta" 2>/dev/null)
  [[ -z "$orig_repo" || -z "$branch" ]] && return

  echo ""
  echo "  ┌─────────────────────────────────────────────────────────┐"
  echo "  │                     Next Steps                          │"
  echo "  └─────────────────────────────────────────────────────────┘"
  echo ""
  echo "  Ralph worked in an isolated worktree. To use the changes:"
  echo ""
  echo "  1. Review what was done:"
  echo "     cd $worktree_dir"
  echo "     git diff main"
  echo "     git log --oneline main..HEAD"
  echo ""
  echo "  2. Merge into your main branch:"
  echo "     cd $orig_repo"
  echo "     git merge $branch"
  echo ""
  echo "  3. Or push the branch for a PR:"
  echo "     cd $worktree_dir"
  echo "     git push -u origin $branch"
  echo ""
  echo "  4. Clean up when done:"
  echo "     ralph prune --session ${RALPH_SESSION_ID}"
  echo ""
}
