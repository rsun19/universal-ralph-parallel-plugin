# Choosing an AI Tool

Ralph works with any AI coding tool that has a CLI. Each tool has an **adapter** in the `adapters/` directory that handles tool-specific details.

## Claude Code (recommended)

**Adapter:** `claude-code`

Claude Code has the deepest integration because it supports stop hooks (for native loop continuation) and Agent Teams (for native team coordination).

### Setup

```bash
# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Initialize your project
ralph init /path/to/project --tool claude-code

# Start
ralph start -p PROMPT.md -r /path/to/project -t claude-code
```

### What the adapter does

- Sets the AI command to `claude --dangerously-skip-permissions --model sonnet -p`
- `--dangerously-skip-permissions` lets Claude run shell commands and edit files without asking for confirmation each time (required for unattended loops)
- `-p` means "read the prompt from stdin"
- Installs a stop hook that intercepts Claude's exit attempts and feeds the prompt back, creating the loop inside a single Claude session
- Installs a `TaskCompleted` hook that checks for placeholder code before allowing task completion

### Native Agent Teams mode

If you pass `--claude-teams`, Ralph doesn't use its own shell-based agent spawning. Instead, it generates a prompt that tells Claude Code to create an Agent Team using Claude's built-in system. See [Claude Code Agent Teams](06-claude-teams.md).

---

## Cursor

**Adapter:** `cursor`

### Setup

```bash
# Initialize your project
ralph init /path/to/project --tool cursor

# This installs .cursor/rules/ralph-loop.mdc into your project
```

### What the adapter does

- Installs a Cursor **rule file** (`.cursor/rules/ralph-loop.mdc`) that instructs Cursor's AI to follow Ralph methodology: read fix_plan.md, pick the most important task, implement fully, write tests, update the plan, commit
- If the `cursor` CLI is available, the adapter uses `cursor --cli --prompt` to pipe prompts
- If no CLI is available, it falls back to writing prompts to `.cursor/ralph-prompt.md` for you to open in Cursor manually

### Fully automated mode

If Cursor exposes a CLI (varies by version and platform), Ralph can drive it automatically:

```bash
ralph start -p PROMPT.md -r /path/to/project -t cursor
```

### Semi-automated mode

If no Cursor CLI is available, use the helper script that the adapter installs:

```bash
cd /path/to/project
.cursor/ralph-run.sh PROMPT.md 20
```

This writes the prompt, waits for you to run it in Cursor, and repeats up to 20 times.

### Using Cursor rules only (no ralph CLI)

You can also just use the rule file without the `ralph` CLI at all. After `ralph init`, the `.cursor/rules/ralph-loop.mdc` rule tells Cursor's AI to follow Ralph methodology whenever you interact with it. Create a `fix_plan.md` manually, open Cursor, and ask it to "work on the next item in fix_plan.md."

---

## GitHub Copilot

**Adapter:** `copilot`

### Setup

```bash
# Install GitHub Copilot CLI
gh extension install github/gh-copilot

# Initialize your project
ralph init /path/to/project --tool copilot

# This installs .github/copilot-instructions.md into your project
```

### What the adapter does

- Installs `.github/copilot-instructions.md` which provides workspace-level instructions to Copilot
- If `gh copilot` CLI is available, uses `gh copilot suggest -t shell` for automation
- Falls back to writing prompts for Copilot Workspace

### How to use

The primary workflow with Copilot is semi-automated. The instructions file tells Copilot to follow Ralph methodology (read fix_plan.md, pick the most important task, implement fully, test, update the plan). You interact with Copilot in your editor and it follows these guidelines.

For full automation (if gh copilot CLI supports it):

```bash
ralph start -p PROMPT.md -r /path/to/project -t copilot
```

---

## Aider

**Adapter:** `generic` (with custom command)

[Aider](https://aider.chat/) is an open-source AI coding tool that works well with Ralph.

### Setup

```bash
pip install aider-chat

# Edit ralph.config.json
{
  "ai_tool": "generic",
  "ai_tool_command": "aider --message"
}
```

### Start

```bash
ralph start -p PROMPT.md -r /path/to/project
```

---

## Any other CLI tool

**Adapter:** `generic`

The generic adapter works with anything that reads a prompt from stdin:

```json
{
  "ai_tool": "generic",
  "ai_tool_command": "your-command-here"
}
```

The command receives the prompt via stdin (piped) and should output its response to stdout.

If your tool doesn't read from stdin, create a small wrapper script:

```bash
#!/bin/bash
# my-ai-wrapper.sh
PROMPT=$(cat)  # Read stdin
echo "$PROMPT" | your-tool --some-flag
```

Then configure:

```json
{
  "ai_tool": "generic",
  "ai_tool_command": "./my-ai-wrapper.sh"
}
```

---

## Using multiple tools

You can maintain multiple config files for different tools:

```bash
# Claude Code config
ralph start -p PROMPT.md -c config-claude.json

# Cursor config
ralph start -p PROMPT.md -c config-cursor.json
```

Or use CLI overrides:

```bash
ralph start -p PROMPT.md -t cursor -r /path/to/project
```
