# Agent Teams (Interactive Session Mode)

Ralph runs an interactive multi-turn session where the AI spawns parallel sub-agents, and a manager AI approves plans and provides guidance on the user's behalf.

This works with **all supported tools** (Claude Code, Cursor, Copilot).

## What are Agent Teams?

Modern AI coding CLIs support spawning parallel sub-agents from a single session. The lead agent coordinates teammates that work on different tasks simultaneously. Examples:
- **Claude Code**: Agent Teams (teammates communicate through shared mailbox and task list)
- **Cursor**: Agent sub-sessions with `--resume` for multi-turn coordination
- **Copilot**: Session-based parallel workflows with `--resume`

As all major CLIs converge on this capability, Ralph provides a unified interface for all of them.

## Configuration

Key settings in `ralph.config.json`:

```json
{
  "turns": 50,
  "manager_model": "sonnet"
}
```

### Claude Code: additional setup

For Claude Code, Agent Teams must also be enabled in your Claude settings:

```json
// .claude/settings.json in your project
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

## How it works

Ralph runs an interactive multi-turn session using a **two-level loop**:

### Inner loop (turns)

1. Ralph sends the team prompt as the first turn using `claude -p --output-format json`
2. Claude creates the agent team, proposes a plan, and may ask for approval
3. A **manager AI** (a separate, cheaper model) reads the output and generates a response (approval, feedback, guidance)
4. Ralph resumes the session with `claude -p --resume SESSION_ID`, sending the manager's response
5. This continues for up to `turns` conversations (default: 50)

### Outer loop (retries)

1. After the inner loop finishes (turns exhausted or completion promise detected), the manager AI reads the actual `git diff` from the target repo
2. It compares the diff against the original prompt and the plan generated in turn 1
3. If all requirements are met, the session is complete
4. If requirements are missing, a **fresh session** starts with a summary of what's incomplete
5. This repeats up to `loop.max_iterations` times (default: 3)

### Key config

| Key | Description | Default |
|-----|-------------|---------|
| `turns` | Max conversation turns per attempt | `50` |
| `loop.max_iterations` | Max retry attempts | `3` |
| `manager_model` | Model for the manager AI | `sonnet` |

## Subagent definitions

The plugin provides three subagent definitions in `adapters/claude-code/agents/`:

### `manager.md`

Defines the team lead role. Has access to all tools (Read, Write, Bash, Grep, Glob, SendMessage, TodoWrite). Its instructions tell it to:
- Break tasks into 5-15 focused subtasks
- Monitor progress and reassign failed tasks
- Track progress and broadcast updates
- Output `<promise>ALL_TASKS_COMPLETE</promise>` when done

### `implementer.md`

Defines the worker role. Has access to Read, Write, Bash, Grep, Glob, SendMessage. Its instructions enforce:
- Search before assuming something isn't implemented
- Full implementations only (no placeholders)
- Write and run tests
- Address previous review feedback on retries

### `reviewer.md`

Defines the reviewer role. Has access to Read, Bash, Grep, Glob, SendMessage (no Write - reviewers don't modify code). Its instructions cover:
- Check correctness, completeness, tests, placeholders, regressions
- Only reject for substantive issues
- Provide specific, actionable feedback

## Using subagent definitions

You can reference these agent definitions when working with Claude Code directly:

```
Spawn a teammate using the implementer agent type to work on the auth module.
```

The teammate inherits the definition's tool restrictions and instructions.

## Display modes

### In-process (default)

All teammates run in your main terminal. Use **Shift+Down** to cycle through them and type to send direct messages. Press **Ctrl+T** to toggle the task list.

### Split panes (tmux)

Each teammate gets its own terminal pane. Requires tmux or iTerm2.

Set in config:

```json
{
  "claude_teams": {
    "teammate_mode": "tmux"
  }
}
```

Or globally in `~/.claude.json`:

```json
{
  "teammateMode": "tmux"
}
```

## Hooks

The Claude Code adapter includes two hooks:

### Stop hook (`hooks/stop-hook.sh`)

Intercepts Claude's exit and feeds the prompt back, creating a loop within a single Claude session. Supports both the plugin's JSON state format and the classic markdown format.

### TaskCompleted hook (`hooks/task-completed.sh`)

Runs when a task is marked complete. Checks for placeholder patterns (TODO, FIXME, STUB, etc.) in recently changed files. Returns exit code 2 to block completion if placeholders are found.
