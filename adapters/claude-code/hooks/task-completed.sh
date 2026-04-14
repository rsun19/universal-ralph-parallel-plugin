#!/bin/bash
# Quality gate hook for Claude Code Agent Teams TaskCompleted event
# Blocks task completion if quality checks fail

set -euo pipefail

HOOK_INPUT=$(cat)

TASK_ID=$(echo "$HOOK_INPUT" | jq -r '.task_id // empty' 2>/dev/null || echo "")
if [[ -z "$TASK_ID" ]]; then
  exit 0
fi

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RALPH_ROOT="$(cd "$PLUGIN_ROOT/../../.." && pwd)"

TASK_FILE="${RALPH_ROOT}/state/tasks/${TASK_ID}.json"
if [[ ! -f "$TASK_FILE" ]]; then
  exit 0
fi

TASK_STATUS=$(jq -r '.status' "$TASK_FILE")
if [[ "$TASK_STATUS" == "approved" ]]; then
  exit 0
fi

# Run basic quality checks
ISSUES=()

# Check for placeholder patterns in recently changed files
CHANGED_FILES=$(git diff --name-only HEAD~1 2>/dev/null || echo "")
for file in $CHANGED_FILES; do
  [[ -f "$file" ]] || continue
  if grep -n "TODO\|FIXME\|PLACEHOLDER\|STUB\|NotImplemented\|pass  #" "$file" 2>/dev/null; then
    ISSUES+=("Placeholder found in $file")
  fi
done

if [[ ${#ISSUES[@]} -gt 0 ]]; then
  FEEDBACK=$(printf '%s\n' "${ISSUES[@]}")
  echo "Quality check failed:" >&2
  echo "$FEEDBACK" >&2
  # Exit code 2 blocks completion and sends feedback
  exit 2
fi

exit 0
