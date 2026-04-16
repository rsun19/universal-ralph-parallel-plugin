#!/bin/bash
# Report status of the Ralph Wiggum agent team.
# Reads state files and outputs a structured summary.

set -euo pipefail

RALPH_PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RALPH_ROOT="$(cd "$RALPH_PLUGIN_ROOT/../../.." && pwd)"

STATE_FILE=".claude/ralph-team.local.json"

# --- Team state -----------------------------------------------------------

echo "═══════════════════════════════════════════════════════════"
echo "  Ralph Wiggum Agent Team Status"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [[ -f "$STATE_FILE" ]]; then
  MODE=$(jq -r '.mode // "unknown"' "$STATE_FILE" 2>/dev/null)
  ITERATION=$(jq -r '.iteration // 0' "$STATE_FILE" 2>/dev/null)
  STATUS=$(jq -r '.status // "unknown"' "$STATE_FILE" 2>/dev/null)
  IMPLEMENTERS=$(jq -r '.implementers // 0' "$STATE_FILE" 2>/dev/null)
  REVIEWERS=$(jq -r '.reviewers // 0' "$STATE_FILE" 2>/dev/null)
  STARTED=$(jq -r '.started_at // "unknown"' "$STATE_FILE" 2>/dev/null)

  echo "  Active:       YES"
  echo "  Mode:         ${MODE}"
  echo "  Status:       ${STATUS}"
  echo "  Iteration:    ${ITERATION}"
  echo "  Implementers: ${IMPLEMENTERS}"
  echo "  Reviewers:    ${REVIEWERS}"
  echo "  Started:      ${STARTED}"
else
  echo "  Active:       NO"
  echo "  (No team state file found at $STATE_FILE)"
fi
echo ""

# --- Task summary ---------------------------------------------------------

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

  echo "--- Tasks ---"
  echo "  Total:       ${TOTAL}"
  echo "  Pending:     ${PENDING}"
  echo "  In Progress: ${IN_PROGRESS}"
  echo "  Completed:   ${COMPLETED}"
  echo "  In Review:   ${REVIEW}"
  echo "  Approved:    ${APPROVED}"
  echo "  Failed:      ${FAILED}"
  echo ""

  echo "--- Task Details ---"
  for f in "$TASK_DIR"/task-*.json; do
    [[ -f "$f" ]] || continue
    ID=$(jq -r '.id' "$f" 2>/dev/null)
    TITLE=$(jq -r '.title' "$f" 2>/dev/null)
    S=$(jq -r '.status' "$f" 2>/dev/null)
    ATTEMPT=$(jq -r '.attempt_count' "$f" 2>/dev/null)
    MAX_R=$(jq -r '.max_retries' "$f" 2>/dev/null)
    ASSIGNEE=$(jq -r '.assignee // ""' "$f" 2>/dev/null)
    echo "  [${S}] ${TITLE} (${ID}, attempt ${ATTEMPT}/${MAX_R}, assignee: ${ASSIGNEE:-none})"
  done
  echo ""
else
  echo "--- Tasks ---"
  echo "  No tasks found."
  echo ""
fi

# --- Agent summary --------------------------------------------------------

AGENT_DIR="${RALPH_SESSION_DIR:-${RALPH_ROOT}/state}/agents"

if [[ -d "$AGENT_DIR" ]] && ls "$AGENT_DIR"/*.json >/dev/null 2>&1; then
  echo "--- Agents ---"
  for f in "$AGENT_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    AID=$(jq -r '.id' "$f" 2>/dev/null)
    ROLE=$(jq -r '.role' "$f" 2>/dev/null)
    ASTATUS=$(jq -r '.status' "$f" 2>/dev/null)
    PID=$(jq -r '.pid' "$f" 2>/dev/null)
    ALIVE="dead"
    kill -0 "$PID" 2>/dev/null && ALIVE="alive"
    echo "  [${ROLE}] ${AID} - ${ASTATUS} (pid ${PID}, ${ALIVE})"
  done
  echo ""
else
  echo "--- Agents ---"
  echo "  No agents registered."
  echo ""
fi

echo "═══════════════════════════════════════════════════════════"

exit 0
