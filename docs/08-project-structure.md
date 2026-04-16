# Project Structure

This document explains every file and directory in the plugin.

```
ralph-wiggum/
│
├── bin/                          # Executable scripts
│   ├── ralph                     # Main CLI (entry point for all commands)
│   └── ralph-interactive.sh      # Interactive agent teams session runner
│
├── lib/                          # Shared libraries (sourced by scripts)
│   ├── utils.sh                  # Logging, config, template rendering, ID generation
│   ├── loop-engine.sh            # Core Ralph loop (run AI, check promise)
│   ├── session-loop.sh           # Interactive session engine (multi-turn + retries)
│   ├── team-prompt.sh            # Tool-agnostic team prompt generator
│   ├── agent-registry.sh         # Agent lifecycle tracking
│   └── worktree.sh               # Git worktree create/remove/list
│
├── adapters/                     # AI tool-specific integrations
│   ├── claude-code/              # Claude Code adapter
│   │   ├── .claude-plugin/       # Claude Code plugin metadata
│   │   │   └── manifest.json     # Plugin manifest (commands, hooks, agents)
│   │   ├── commands/             # Slash commands for Claude Code
│   │   │   ├── ralph-team.md     # /ralph-team - delegates to setup-team.sh
│   │   │   └── cancel-ralph.md   # /cancel-ralph - delegates to cancel-team.sh
│   │   ├── scripts/              # Bash scripts that commands delegate to
│   │   │   ├── setup-team.sh     # Parse args, create state, output config
│   │   │   ├── cancel-team.sh    # Kill agents, report status, clean up
│   │   │   └── team-status.sh    # Read state files, print structured report
│   │   ├── hooks/                # Claude Code lifecycle hooks
│   │   │   ├── stop-hook.sh      # Intercepts exit to continue loop
│   │   │   └── task-completed.sh # Quality gate on task completion
│   │   ├── agents/               # Subagent definitions (for Agent Teams)
│   │   │   ├── manager.md        # Team lead role definition
│   │   │   ├── implementer.md    # Worker role definition
│   │   │   └── reviewer.md       # Reviewer role definition
│   │   ├── ralph-claude-code-adapter.sh  # Adapter functions
│   │   └── ralph-claude-teams.sh         # Backward compat wrapper → ralph-interactive.sh
│   │
│   ├── cursor/                   # Cursor CLI adapter
│   │   └── ralph-cursor-adapter.sh   # Returns: agent --model X -p
│   │
│   ├── copilot/                  # GitHub Copilot CLI adapter
│   │   └── ralph-copilot-adapter.sh  # Returns: copilot --allow-all --model X -p
│   │
│   └── generic/                  # Generic adapter (any CLI tool)
│       └── ralph-generic-adapter.sh
│
├── templates/                    # Default prompt templates (read-only source)
│   ├── prompt-plan.md            # Planning prompt (task breakdown)
│   ├── prompt-team.md            # Agent teams orchestration prompt
│   ├── prompt-manager-respond.md # Manager turn-by-turn response prompt
│   ├── prompt-verify.md          # Completion verification prompt
│   └── AGENT.md.template         # Template for project learnings file
│
├── state/                        # Runtime state (gitignored)
│   ├── templates/                # Editable copies of prompt templates
│   │   ├── prompt-plan.md        # (copied from templates/ on init/start)
│   │   └── ...                   # Edit these; ralph templates --reset restores defaults
│   ├── prompts/                  # Generated prompt files
│   └── sessions/                 # Per-session state
│       └── <session_id>/         # One directory per ralph start
│           ├── session.json      # Session metadata (repo, branch, worktree path)
│           ├── .ralph-config-effective.json  # Resolved config for this session
│           └── logs/             # Session logs
│               └── agent-teams/
│                   └── <session_id>/
│                       └── attempt-N/
│                           ├── turn-01.json    # Raw JSON output from AI
│                           ├── turn-01.log     # Human-readable output
│                           ├── manager-02.log  # Manager AI response
│                           └── verification.log # Manager AI diff verdict
│
├── docs/                         # Documentation (you are here)
│
├── ralph.config.example.json     # Example configuration (copy to ralph.config.json)
├── ralph.config.json             # YOUR config (created by `ralph init`, gitignored)
├── install.sh                    # Installer script
├── .gitignore                    # Ignores state/, config, and temp files
└── README.md                     # Project overview
```

## How the pieces connect

### When you run `ralph start -p "your prompt"`:

1. `bin/ralph` parses your flags, loads `ralph.config.json`, applies CLI overrides
2. Creates a git worktree at `<repo>-worktrees/ralph-<session_id>` on branch `ralph/<session_id>`
3. Creates session state directory at `state/sessions/<session_id>/`
4. Syncs prompt templates from `templates/` to `state/templates/` (copies any missing ones)
5. For Cursor: opens the worktree in a new Cursor window for parallel execution
6. Writes `session.json` metadata and effective config into the session directory
7. `bin/ralph` calls `bin/ralph-interactive.sh`
8. Generates a team prompt via `lib/team-prompt.sh` using `state/templates/prompt-team.md`, delegates to `lib/session-loop.sh`
9. **Inner loop**: First turn starts a session (`--output-format json`), captures `session_id`. Subsequent turns use `--resume`. Between turns, the manager AI reads output and generates approvals/feedback.
10. **Outer loop**: After turns are exhausted, the manager AI reads the `git diff` and compares against requirements. If incomplete, a fresh session starts with specific retry feedback.
11. Logs are written per-turn to `state/sessions/<id>/logs/agent-teams/<id>/attempt-N/`
12. Prints merge instructions when complete

### When you run `ralph init`:

1. An interactive wizard collects your preferences (repo path, AI tool, model, team size)
2. Writes `ralph.config.json` (gitignored, never checked in)
3. Copies default prompt templates from `templates/` to `state/templates/`

### The adapter pattern

Each adapter exports these functions:

- `get_adapter_command(config_file)` — One-shot command (e.g., `claude --model sonnet -p`)
- `get_initial_command(config_file)` — First turn of an interactive session (includes `--output-format json`)
- `get_session_command(config_file, session_id)` — Resume an existing session (includes `--resume`)
- `get_manager_command(config_file)` — Lightweight command for the manager AI (uses `manager_model`)

Adapters live in `adapters/` and include tool-specific configuration files (rules, hooks, agent definitions) that Ralph uses internally.
