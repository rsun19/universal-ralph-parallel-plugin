# Claude Code Agent Teams Integration

This plugin has two modes for running agent teams with Claude Code:

1. **Shell mode** (default): Ralph spawns Claude Code processes itself, coordinating through files on disk
2. **Native Agent Teams mode**: Ralph delegates to Claude Code's built-in Agent Teams feature, where Claude manages the team internally

This document covers the native Agent Teams mode.

## What is Claude Code Agent Teams?

Agent Teams is an experimental feature in Claude Code (v2.1.32+) that lets one Claude session (the "lead") spawn and coordinate other Claude sessions ("teammates"). Teammates have their own context windows, communicate through a shared mailbox, and coordinate through a shared task list.

For more details, see the [official docs](https://code.claude.com/docs/en/agent-teams).

## Enabling native Agent Teams mode

### Step 1: Enable the feature flag

Agent Teams must be enabled in your Claude Code settings. The installer does this automatically, but you can verify:

```json
// .claude/settings.json in your project
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

### Step 2: Set the config flag

In `ralph.config.json`:

```json
{
  "claude_teams": {
    "enabled": true,
    "teammate_mode": "in-process"
  }
}
```

Or use the CLI flag:

```bash
ralph start -p PROMPT.md --claude-teams
```

## How it works in native mode

When `claude_teams.enabled` is `true`, the `ralph start` command doesn't spawn shell processes. Instead, it generates a detailed prompt and passes it to Claude Code, asking Claude to:

1. Create an agent team with the specified number of implementers and reviewers
2. Break the task into subtasks using the shared task list
3. Assign implementer teammates to work on tasks
4. Require plan approval from implementers before they start coding
5. Send completed tasks to reviewer teammates
6. Handle rejections by reassigning with feedback

The manager becomes the Claude Code **team lead**. Implementers and reviewers become **teammates**.

## Subagent definitions

The plugin provides three subagent definitions in `adapters/claude-code/agents/`:

### `manager.md`

Defines the team lead role. Has access to all tools (Read, Write, Bash, Grep, Glob, SendMessage, TodoWrite). Its instructions tell it to:
- Break tasks into 5-15 focused subtasks
- Monitor progress and reassign failed tasks
- Keep fix_plan.md updated
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

## Shell mode vs. native mode

| Aspect | Shell mode | Native Agent Teams |
|--------|-----------|-------------------|
| How agents run | Separate shell processes, each invoking Claude CLI | Claude Code spawns teammates internally |
| Communication | File-based mailbox in `state/messages/` | Claude's native mailbox system |
| Task coordination | Custom file-based task manager with flock | Claude's shared task list |
| Works with other tools | Yes (Cursor, Copilot, etc.) | Claude Code only |
| Setup complexity | Just works | Requires Agent Teams feature flag |
| Token cost | Each process is independent | Managed by Claude (similar cost) |
| Monitoring | `ralph status` | Shift+Down or tmux panes |

**Use shell mode** when you want tool-agnostic operation or are using a non-Claude AI tool.

**Use native mode** when you want Claude Code's built-in team coordination, inter-agent messaging, and plan approval workflows.

## Hooks

The Claude Code adapter includes two hooks:

### Stop hook (`hooks/stop-hook.sh`)

Intercepts Claude's exit and feeds the prompt back, creating a loop within a single Claude session. Supports both the plugin's JSON state format and the classic markdown format.

### TaskCompleted hook (`hooks/task-completed.sh`)

Runs when a task is marked complete. Checks for placeholder patterns (TODO, FIXME, STUB, etc.) in recently changed files. Returns exit code 2 to block completion if placeholders are found.
