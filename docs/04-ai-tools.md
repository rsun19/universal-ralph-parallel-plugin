# Choosing an AI Tool

Ralph works with any AI coding tool that has a CLI. Each tool has an **adapter** in the `adapters/` directory that handles tool-specific details.

## Claude Code (recommended)

**Adapter:** `claude-code`

Claude Code has the deepest integration because it supports stop hooks (for native loop continuation) and Agent Teams (for native team coordination).

### Setup

```bash
# Install Claude Code
npm install -g @anthropic-ai/claude-code

# Run the setup wizard (select claude-code when asked)
ralph init

# Start
ralph start -p "Build a REST API for todos with CRUD, validation, and tests"
```

### What the adapter does

- Sets the AI command to `claude --model <model> -p`
- `-p` means "read the prompt from stdin"
- Installs a stop hook that intercepts Claude's exit attempts and feeds the prompt back, creating the loop inside a single Claude session
- Installs a `TaskCompleted` hook that checks for placeholder code before allowing task completion

### Permissions

By default, Ralph respects Claude Code's permission config. For unattended loops, pre-configure permissions in `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": ["Bash", "Read", "Edit", "WebFetch"]
  }
}
```

Or skip all prompts at runtime with `ralph start --allow-all` (adds `--dangerously-skip-permissions`).

Docs: [code.claude.com/docs/en/permissions](https://code.claude.com/docs/en/permissions)

### Interactive Agent Teams Mode

All three tools support interactive agent teams via `--agent-teams`:

```bash
ralph start -p "Build auth with JWT" --agent-teams
```

Instead of one-shot `-p` calls, Ralph maintains a conversation across multiple turns using `--resume`. The AI spawns parallel sub-agents internally, and a **manager AI** (a separate, lighter model) reads each turn's output and automatically responds — approving plans, answering questions, and providing guidance.

After the conversation turns are exhausted (or completion is detected), the manager AI verifies the actual `git diff` against the original requirements. If requirements aren't met, a fresh session is started with specific feedback.

**Config keys:**
- `agent_teams` — enable interactive agent teams (default: false)
- `turns` — max conversation turns per attempt (default: 50)
- `loop.max_iterations` — max retry attempts (default: 3)
- `manager_model` — model for the manager AI (default: sonnet, cheaper is recommended)

See [Agent Teams](06-claude-teams.md) for full details.

---

## Cursor

**Adapter:** `cursor`

### Setup

```bash
# Install the Cursor CLI
curl https://cursor.com/install -fsS | bash

# Run the setup wizard (select cursor when asked)
ralph init

# Start
ralph start -p "Build a REST API for todos with CRUD, validation, and tests"
```

### What the adapter does

- Sets the AI command to `agent --model <model> -p`
- `-p` means "read the prompt from stdin and print the result" (non-interactive)
- `--model` selects the model (sonnet, opus, gpt-4.1, etc.)
- Ralph's full bash orchestration works: parallel workers, reviewers, retry loops, atomic task claiming

### Permissions

By default, Ralph respects Cursor's permission config. For unattended loops, pre-configure permissions in `~/.cursor/cli-config.json`:

```json
{
  "permissions": {
    "allow": ["Shell(*)", "Read(**)", "Write(**)", "Mcp(*:*)"]
  }
}
```

Or skip all prompts at runtime with `ralph start --allow-all` (adds `--force --approve-mcps`).

Docs: [cursor.com/docs/cli/reference/permissions](https://cursor.com/docs/cli/reference/permissions)

---

## GitHub Copilot

**Adapter:** `copilot`

### Setup

```bash
# Install the Copilot CLI
# See: https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli

# Run the setup wizard (select copilot when asked)
ralph init

# Start
ralph start -p "Build a REST API for todos with CRUD, validation, and tests"
```

### What the adapter does

- Sets the AI command to `copilot --allow-all --model <model> -p`
- `--allow-all` skips all permission prompts (always included — see note below)
- `-p` means "read the prompt from stdin and print the result" (non-interactive)
- `--model` selects the model (sonnet, opus, gpt-4.1, etc.)
- Ralph's full bash orchestration works: parallel workers, reviewers, retry loops, atomic task claiming

### Permissions

**Copilot CLI does not support config-file-based permissions.** Unlike Claude Code and Cursor, there is no way to pre-approve tool use via a settings file. The only mechanism is the `--allow-all` CLI flag, which Ralph includes by default in the Copilot adapter. Without it, every tool use (shell commands, file writes, etc.) prompts for interactive approval, making unattended loops impossible.

Docs: [docs.github.com/en/copilot/how-tos/copilot-cli/allowing-tools](https://docs.github.com/en/copilot/how-tos/copilot-cli/allowing-tools)

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
