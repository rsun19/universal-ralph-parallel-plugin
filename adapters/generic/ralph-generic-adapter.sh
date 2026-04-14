#!/usr/bin/env bash
# Generic adapter for any CLI-based AI coding tool
#
# This adapter works with any tool that can accept a prompt via stdin or file.
# Configure the exact command in ralph.config.json under "ai_tool_command".
#
# Supported tools (configure ai_tool_command accordingly):
#
#   Aider:          "aider --message"
#   Continue:       "continue"
#   Cline:          "cline --prompt"
#   OpenAI CLI:     "openai api chat.completions.create -m gpt-4 -p"
#   Custom script:  "./my-ai-wrapper.sh"

get_adapter_command() {
  local config_file="$1"
  
  local cmd
  cmd=$(config_get "$config_file" '.ai_tool_command' '')
  
  if [[ -z "$cmd" ]]; then
    ralph_log ERROR "Generic adapter requires 'ai_tool_command' in config"
    ralph_log ERROR "Example: \"ai_tool_command\": \"aider --message\""
    return 1
  fi
  
  echo "$cmd"
}

install_adapter() {
  local target_dir="$1"
  local ralph_root="$2"
  
  # Create a generic loop runner script
  cat > "${target_dir}/ralph-run.sh" << 'SCRIPT'
#!/usr/bin/env bash
# Generic Ralph loop runner
# Usage: ./ralph-run.sh <prompt text or file> <ai-command> [max-iterations]
#
# Examples:
#   ./ralph-run.sh "Add input validation" "aider --message" 50
#   ./ralph-run.sh PROMPT.md "claude -p" 100

INPUT="${1:?Usage: ralph-run.sh <prompt text or file> <ai-command> [max-iterations]}"
AI_CMD="${2:?AI command required}"
MAX_ITER="${3:-50}"

if [[ -f "$INPUT" ]]; then
  PROMPT_TEXT=$(cat "$INPUT")
else
  PROMPT_TEXT="$INPUT"
fi

echo "Ralph Wiggum Generic Loop"
echo "Command: $AI_CMD"
echo "Max iterations: $MAX_ITER"
echo ""

for i in $(seq 1 "$MAX_ITER"); do
  echo "========================================"
  echo "  Ralph Iteration $i / $MAX_ITER"
  echo "========================================"

  OUTPUT_FILE=".ralph-iter-${i}.log"

  printf '%s\n' "$PROMPT_TEXT" | eval "$AI_CMD" 2>&1 | tee "$OUTPUT_FILE"

  if grep -qE "ALL_TASKS_COMPLETE|TASK_DONE|<promise>.*</promise>" "$OUTPUT_FILE" 2>/dev/null; then
    echo ""
    echo "========================================"
    echo "  Ralph loop completed at iteration $i"
    echo "========================================"
    break
  fi

  sleep 2
done
SCRIPT
  chmod +x "${target_dir}/ralph-run.sh"
}
