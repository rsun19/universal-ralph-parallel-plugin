#!/usr/bin/env bash
# Cursor adapter for the universal Ralph loop engine
#
# Cursor doesn't have a stdin-based CLI like Claude Code, so this adapter
# writes prompts to a file and invokes Cursor's CLI or uses the Cursor
# Agent mode with rules to drive iterative behavior.

get_adapter_command() {
  local config_file="$1"
  
  # Cursor's CLI integration varies by platform.
  # The primary approach is to use the Cursor CLI with --prompt flag if available,
  # or fall back to writing PROMPT.md and using cursor's composer.
  if command -v cursor >/dev/null 2>&1; then
    echo "cursor --cli --prompt"
  else
    # Fallback: write prompt to file for Cursor to pick up via rules
    echo "cat > .cursor/ralph-prompt.md && echo 'Prompt written to .cursor/ralph-prompt.md - open in Cursor'"
  fi
}

install_adapter() {
  local target_dir="$1"
  local ralph_root="$2"
  
  mkdir -p "${target_dir}/.cursor/rules"
  
  # Install Ralph rules
  cp "${ralph_root}/adapters/cursor/.cursor/rules/ralph-loop.mdc" \
     "${target_dir}/.cursor/rules/" 2>/dev/null || true
  
  # Create a Cursor-specific prompt runner script
  cat > "${target_dir}/.cursor/ralph-run.sh" << 'SCRIPT'
#!/usr/bin/env bash
# Run Ralph loop iterations in Cursor
# Usage: .cursor/ralph-run.sh <prompt-text-or-file> [max-iterations]

INPUT="${1:?Usage: ralph-run.sh <prompt text or file> [max-iterations]}"
MAX_ITER="${2:-50}"

# Resolve input: file path or inline text
if [[ -f "$INPUT" ]]; then
  PROMPT_TEXT=$(cat "$INPUT")
else
  PROMPT_TEXT="$INPUT"
fi

for i in $(seq 1 "$MAX_ITER"); do
  echo "=== Ralph Iteration $i ==="
  printf '%s\n' "$PROMPT_TEXT" > .cursor/ralph-prompt.md

  if command -v cursor >/dev/null 2>&1; then
    cursor --cli --prompt "$PROMPT_TEXT" 2>&1 | tee ".cursor/ralph-iter-${i}.log"
  else
    echo "Cursor CLI not available. Please open Cursor and run the prompt from .cursor/ralph-prompt.md"
    echo "Press Enter when iteration $i is complete..."
    read -r
  fi

  if [[ -f ".cursor/ralph-iter-${i}.log" ]] && grep -q "TASK_DONE\|ALL_TASKS_COMPLETE" ".cursor/ralph-iter-${i}.log"; then
    echo "=== Ralph loop complete at iteration $i ==="
    break
  fi

  sleep 2
done
SCRIPT
  chmod +x "${target_dir}/.cursor/ralph-run.sh"
}
