#!/bin/bash
# Setup a Ralph Wiggum agent team session.
# Creates the state file that the stop hook reads, and outputs
# configuration for the AI to act on.

set -euo pipefail

# --- Argument parsing ---------------------------------------------------

PROMPT_PARTS=()
MAX_ITERATIONS=50
COMPLETION_PROMISE="ALL_TASKS_COMPLETE"
NUM_IMPLEMENTERS=3
NUM_REVIEWERS=2
MODE="auto"  # auto, shell, claude-teams

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP'
Ralph Team - Start a Ralph Wiggum agent team

USAGE:
  /ralph-team [PROMPT...] [OPTIONS]

ARGUMENTS:
  PROMPT...  Task description (can be multiple words without quotes)

OPTIONS:
  --max-iterations <n>       Max iterations per agent (default: 50)
  --completion-promise <text> Phrase that signals completion (default: ALL_TASKS_COMPLETE)
  --implementers <n>         Number of implementer agents (default: 3)
  --reviewers <n>            Number of reviewer agents (default: 2)
  --mode <mode>              Execution mode: auto, shell, claude-teams (default: auto)
  -h, --help                 Show this help

EXAMPLES:
  /ralph-team Build a todo REST API --implementers 3 --reviewers 2
  /ralph-team Fix the auth module --max-iterations 20 --completion-promise DONE
  /ralph-team --mode claude-teams Refactor the database layer
HELP
      exit 0
      ;;
    --max-iterations)
      [[ -z "${2:-}" ]] && { echo "Error: --max-iterations requires a number" >&2; exit 1; }
      [[ "$2" =~ ^[0-9]+$ ]] || { echo "Error: --max-iterations must be a positive integer, got: $2" >&2; exit 1; }
      MAX_ITERATIONS="$2"; shift 2 ;;
    --completion-promise)
      [[ -z "${2:-}" ]] && { echo "Error: --completion-promise requires text" >&2; exit 1; }
      COMPLETION_PROMISE="$2"; shift 2 ;;
    --implementers)
      [[ -z "${2:-}" ]] && { echo "Error: --implementers requires a number" >&2; exit 1; }
      [[ "$2" =~ ^[0-9]+$ ]] || { echo "Error: --implementers must be a positive integer, got: $2" >&2; exit 1; }
      NUM_IMPLEMENTERS="$2"; shift 2 ;;
    --reviewers)
      [[ -z "${2:-}" ]] && { echo "Error: --reviewers requires a number" >&2; exit 1; }
      [[ "$2" =~ ^[0-9]+$ ]] || { echo "Error: --reviewers must be a positive integer, got: $2" >&2; exit 1; }
      NUM_REVIEWERS="$2"; shift 2 ;;
    --mode)
      [[ -z "${2:-}" ]] && { echo "Error: --mode requires a value (auto, shell, claude-teams)" >&2; exit 1; }
      MODE="$2"; shift 2 ;;
    *)
      PROMPT_PARTS+=("$1"); shift ;;
  esac
done

PROMPT="${PROMPT_PARTS[*]}"

if [[ -z "$PROMPT" ]]; then
  echo "Error: No prompt provided." >&2
  echo "" >&2
  echo "Usage: /ralph-team <prompt> [options]" >&2
  echo "For help: /ralph-team --help" >&2
  exit 1
fi

# --- Detect execution mode -----------------------------------------------

if [[ "$MODE" == "auto" ]]; then
  if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}" == "1" ]]; then
    MODE="claude-teams"
  else
    MODE="shell"
  fi
fi

# --- Create state file ---------------------------------------------------

RALPH_PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RALPH_ROOT="$(cd "$RALPH_PLUGIN_ROOT/../../.." && pwd)"

mkdir -p .claude

cat > .claude/ralph-team.local.json << STATE_EOF
{
  "mode": "${MODE}",
  "prompt": $(echo "$PROMPT" | jq -Rs .),
  "max_iterations": ${MAX_ITERATIONS},
  "completion_promise": $(echo "$COMPLETION_PROMISE" | jq -Rs . | sed 's/\\n$//'),
  "implementers": ${NUM_IMPLEMENTERS},
  "reviewers": ${NUM_REVIEWERS},
  "iteration": 0,
  "status": "starting",
  "started_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}
STATE_EOF

# --- Output setup summary ------------------------------------------------

echo "═══════════════════════════════════════════════════════════"
echo "  Ralph Wiggum Agent Team"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Mode:             ${MODE}"
echo "  Implementers:     ${NUM_IMPLEMENTERS}"
echo "  Reviewers:        ${NUM_REVIEWERS}"
echo "  Max iterations:   ${MAX_ITERATIONS}"
echo "  Promise:          ${COMPLETION_PROMISE}"
echo "  State file:       .claude/ralph-team.local.json"
echo ""
echo "═══════════════════════════════════════════════════════════"

# --- Mode-specific output -------------------------------------------------

if [[ "$MODE" == "shell" ]]; then
  echo ""
  echo "Starting shell-based orchestration..."
  echo "Run: ${RALPH_ROOT}/bin/ralph start -p <(echo '${PROMPT}') -n ${NUM_IMPLEMENTERS} -R ${NUM_REVIEWERS} -m ${MAX_ITERATIONS}"
  echo ""
  echo "Or the manager will be launched directly if invoked via the stop hook."
fi

if [[ "$MODE" == "claude-teams" ]]; then
  echo ""
  echo "TEAM_CONFIG_START"
  echo "{"
  echo "  \"team_type\": \"ralph-wiggum\","
  echo "  \"prompt\": $(echo "$PROMPT" | jq -Rs .),"
  echo "  \"roles\": ["
  for i in $(seq 1 "$NUM_IMPLEMENTERS"); do
    echo "    {\"name\": \"impl-${i}\", \"agent_type\": \"implementer\", \"require_plan_approval\": true},"
  done
  for i in $(seq 1 "$NUM_REVIEWERS"); do
    COMMA=","
    [[ $i -eq $NUM_REVIEWERS ]] && COMMA=""
    echo "    {\"name\": \"reviewer-${i}\", \"agent_type\": \"reviewer\", \"require_plan_approval\": false}${COMMA}"
  done
  echo "  ],"
  echo "  \"quality_gates\": {"
  echo "    \"require_plan_approval\": true,"
  echo "    \"check_tests\": true,"
  echo "    \"check_placeholders\": true,"
  echo "    \"max_retries\": 3"
  echo "  }"
  echo "}"
  echo "TEAM_CONFIG_END"
fi

exit 0
