#!/usr/bin/env bash
# Ralph Interactive Session — tool-agnostic agent teams via multi-turn sessions
#
# Uses the two-level session loop:
#   Inner loop (turns): Manager AI responds on the user's behalf
#   Outer loop (retries): Manager AI verifies git diff against requirements
#
# Works with any CLI that supports --resume (Claude Code, Cursor, Copilot, etc.)

set -euo pipefail

RALPH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${RALPH_ROOT}/lib/utils.sh"
source "${RALPH_ROOT}/lib/team-prompt.sh"
source "${RALPH_ROOT}/lib/session-loop.sh"

CONFIG_FILE="${1:?Config file required}"
PROMPT_FILE="${2:?Prompt file required}"

AI_TOOL=$(config_get "$CONFIG_FILE" '.ai_tool' 'claude-code')

TEAM_PROMPT=$(build_team_prompt "$CONFIG_FILE" "$PROMPT_FILE")

ralph_log INFO "Starting interactive agent teams session..."
ralph_log INFO "  AI tool: ${AI_TOOL}"
ralph_log INFO "  Turns per attempt: $(config_get "$CONFIG_FILE" '.turns' '50')"
ralph_log INFO "  Max retry attempts: $(config_get "$CONFIG_FILE" '.loop.max_iterations' '3')"
ralph_log INFO "  Manager model: $(config_get "$CONFIG_FILE" '.manager_model' 'sonnet')"

session_loop "$CONFIG_FILE" "$PROMPT_FILE" "$TEAM_PROMPT" "$RALPH_ROOT"
