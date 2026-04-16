#!/bin/bash
# Ralph Wiggum Stop Hook for Claude Code
# Prevents session exit when a ralph loop is active,
# feeding the same prompt back to continue the iteration.

set -euo pipefail

HOOK_INPUT=$(cat)

# Check for ralph state files in multiple locations
RALPH_STATE_FILE=""
for candidate in \
  ".claude/ralph-loop.local.md" \
  ".ralph-state.json" \
  "${CLAUDE_PLUGIN_ROOT}/../../../state/loops/"*.json; do
  if [[ -f "$candidate" ]]; then
    RALPH_STATE_FILE="$candidate"
    break
  fi
done

if [[ -z "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Handle JSON state format (from universal ralph)
if [[ "$RALPH_STATE_FILE" == *.json ]]; then
  STATUS=$(jq -r '.status' "$RALPH_STATE_FILE" 2>/dev/null || echo "unknown")
  if [[ "$STATUS" == "completed" ]] || [[ "$STATUS" == "max_iterations_reached" ]]; then
    exit 0
  fi

  ITERATION=$(jq -r '.iteration' "$RALPH_STATE_FILE" 2>/dev/null || echo "0")
  MAX_ITERATIONS=$(jq -r '.max_iterations' "$RALPH_STATE_FILE" 2>/dev/null || echo "0")
  PROMISE=$(jq -r '.completion_promise' "$RALPH_STATE_FILE" 2>/dev/null || echo "")

  if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    exit 0
  fi

  # Check transcript for completion promise
  TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path' 2>/dev/null || echo "")
  if [[ -n "$PROMISE" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
    if grep -q '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null; then
      LAST_OUTPUT=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1 | \
        jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")' 2>/dev/null || echo "")
      
      PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
      if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$PROMISE" ]]; then
        exit 0
      fi
    fi
  fi

  NEXT_ITERATION=$((ITERATION + 1))
  jq --argjson iter "$NEXT_ITERATION" '.iteration = $iter' "$RALPH_STATE_FILE" > "${RALPH_STATE_FILE}.tmp"
  mv "${RALPH_STATE_FILE}.tmp" "$RALPH_STATE_FILE"

  jq -n \
    --arg msg "Ralph iteration $NEXT_ITERATION | Continue working on the current task." \
    '{
      "decision": "block",
      "reason": "Continue working on the current task. Check the task list for progress and pick up the next most important item.",
      "systemMessage": $msg
    }'
  exit 0
fi

# Handle markdown state format (classic Claude Code plugin format)
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]] || [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  rm "$RALPH_STATE_FILE"
  exit 0
fi

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  rm "$RALPH_STATE_FILE"
  exit 0
fi

TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
if [[ -f "$TRANSCRIPT_PATH" ]] && grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  LAST_OUTPUT=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1 | \
    jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")' 2>/dev/null || echo "")

  if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
    PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
    if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
      rm "$RALPH_STATE_FILE"
      exit 0
    fi
  fi
fi

NEXT_ITERATION=$((ITERATION + 1))
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  rm "$RALPH_STATE_FILE"
  exit 0
fi

TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE"

jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "Ralph iteration $NEXT_ITERATION" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
