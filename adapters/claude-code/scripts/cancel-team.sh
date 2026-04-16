#!/bin/bash
# Cancel an active Ralph Wiggum agent team.
# Reads state, kills processes, reports final status.

set -euo pipefail

RALPH_PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RALPH_ROOT="$(cd "$RALPH_PLUGIN_ROOT/../../.." && pwd)"

STATE_FILE=".claude/ralph-team.local.json"

# --- Check for active team ------------------------------------------------

if [[ ! -f "$STATE_FILE" ]]; then
  echo "No active Ralph team found."
  echo "(Looked for: $STATE_FILE)"
  exit 0
fi

MODE=$(jq -r '.mode // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
ITERATION=$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null || echo "0")
STATUS=$(jq -r '.status // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")

echo "═══════════════════════════════════════════════════════════"
echo "  Cancelling Ralph Wiggum Agent Team"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Mode:       ${MODE}"
echo "  Iteration:  ${ITERATION}"
echo "  Status:     ${STATUS}"
echo ""

# --- Kill shell-mode agents -----------------------------------------------

if [[ "$MODE" == "shell" ]]; then
  if [[ -x "${RALPH_ROOT}/bin/ralph" ]]; then
    echo "Killing shell-based agents..."
    "${RALPH_ROOT}/bin/ralph" cancel 2>&1 || true
    echo ""
  fi
fi

# --- Collect final task status --------------------------------------------

TASK_DIR="${RALPH_SESSION_DIR:-${RALPH_ROOT}/state}/tasks"
if [[ -d "$TASK_DIR" ]] && ls "$TASK_DIR"/task-*.json >/dev/null 2>&1; then
  TOTAL=0; PENDING=0; IN_PROGRESS=0; COMPLETED=0; REVIEW=0; APPROVED=0; FAILED=0

  for f in "$TASK_DIR"/task-*.json; do
    [[ -f "$f" ]] || continue
    TOTAL=$((TOTAL + 1))
    S=$(jq -r '.status' "$f" 2>/dev/null)
    case "$S" in
      pending)     PENDING=$((PENDING + 1)) ;;
      in_progress) IN_PROGRESS=$((IN_PROGRESS + 1)) ;;
      completed)   COMPLETED=$((COMPLETED + 1)) ;;
      review)      REVIEW=$((REVIEW + 1)) ;;
      approved)    APPROVED=$((APPROVED + 1)) ;;
      failed)      FAILED=$((FAILED + 1)) ;;
    esac
  done

  echo "--- Final Task Status ---"
  echo "  Total:       ${TOTAL}"
  echo "  Pending:     ${PENDING}"
  echo "  In Progress: ${IN_PROGRESS}"
  echo "  Completed:   ${COMPLETED}"
  echo "  In Review:   ${REVIEW}"
  echo "  Approved:    ${APPROVED}"
  echo "  Failed:      ${FAILED}"
  echo ""
else
  echo "  No tasks found."
  echo ""
fi

# --- Remove state file ----------------------------------------------------

rm -f "$STATE_FILE"
echo "State file removed: $STATE_FILE"

# --- Clean up locks -------------------------------------------------------

_state_dir="${RALPH_SESSION_DIR:-${RALPH_ROOT}/state}"
rm -f "${_state_dir}/tasks"/*.lock 2>/dev/null || true
rm -f "${_state_dir}/messages"/*.json 2>/dev/null || true

echo ""
echo "Ralph team cancelled."
echo "Task files preserved in: ${_state_dir}/tasks/"
echo "═══════════════════════════════════════════════════════════"

exit 0
