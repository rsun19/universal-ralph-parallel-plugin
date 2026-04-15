# Project Structure

This document explains every file and directory in the plugin.

```
ralph-wiggum/
│
├── bin/                          # Executable scripts
│   ├── ralph                     # Main CLI (entry point for all commands)
│   ├── ralph-interactive.sh      # Interactive agent teams session runner
│   ├── ralph-manager.sh          # Manager agent orchestrator (bash mode)
│   ├── ralph-worker.sh           # Implementer agent (bash mode)
│   └── ralph-review.sh           # Reviewer agent (bash mode)
│
├── lib/                          # Shared libraries (sourced by scripts)
│   ├── utils.sh                  # Logging, config loading, ID generation
│   ├── loop-engine.sh            # Core Ralph loop (run AI, check promise)
│   ├── session-loop.sh           # Interactive session engine (multi-turn + retries)
│   ├── team-prompt.sh            # Tool-agnostic team prompt generator
│   ├── task-manager.sh           # Task CRUD, claiming, status transitions
│   ├── agent-registry.sh         # Agent lifecycle tracking
│   └── comms.sh                  # Inter-agent messaging
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
├── templates/                    # Prompt templates
│   ├── prompt-plan.md            # Planning prompt (task breakdown)
│   ├── prompt-implement.md       # Implementation prompt (per task)
│   ├── prompt-review.md          # Review prompt (per task)
│   ├── prompt-manager.md         # Manager coordination prompt
│   └── AGENT.md.template         # Template for project learnings file
│
├── state/                        # Runtime state (gitignored)
│   ├── prompts/                  # Generated prompt files
│   ├── tasks/                    # Task JSON files
│   ├── agents/                   # Agent registry files
│   ├── messages/                 # Inter-agent messages
│   └── logs/                     # AI output logs per iteration
│       └── agent-teams/          # Interactive session logs
│           └── attempt-N/        # Per-attempt directory
│               ├── turn-01.json  # Raw JSON output from AI
│               ├── turn-01.log   # Human-readable output
│               ├── manager-02.log # Manager AI response for turn 2
│               └── verification.log # Manager AI diff verdict
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

**Bash orchestration mode** (default):

1. `bin/ralph` parses your flags, loads `ralph.config.json`, applies CLI overrides
2. `bin/ralph` calls `bin/ralph-manager.sh`
3. `ralph-manager.sh` sources all `lib/*.sh` libraries
4. It runs **Phase 1**: builds a planning prompt, pipes it to the AI tool, parses the JSON task list, creates files in `state/tasks/`
5. It runs **Phase 2**: spawns `bin/ralph-worker.sh` processes in the background. Each worker claims tasks, builds prompts from `templates/prompt-implement.md`, runs the AI in a loop, and updates task status
6. It runs **Phase 3**: spawns `bin/ralph-review.sh` processes. Each reviewer claims completed tasks, builds prompts from `templates/prompt-review.md`, runs the AI, and approves or rejects
7. The manager monitors `state/tasks/` for progress, respawns dead agents, and loops if rejected tasks need retrying

**Interactive session mode** (`--agent-teams`):

1. `bin/ralph` parses flags, loads config, calls `bin/ralph-interactive.sh`
2. `ralph-interactive.sh` generates a team prompt via `lib/team-prompt.sh`, then delegates to `lib/session-loop.sh`
3. **Inner loop**: First turn starts a session (`--output-format json`), captures `session_id`. Subsequent turns use `--resume` to maintain context. Between turns, the manager AI reads output and generates approvals/feedback.
4. **Outer loop**: After turns are exhausted, the manager AI reads the `git diff` and compares against requirements. If incomplete, a fresh session starts with specific retry feedback.
5. Logs are written per-turn to `state/logs/agent-teams/attempt-N/`

### When you run `ralph init`:

1. An interactive wizard collects your preferences (repo path, AI tool, model, team size)
2. Writes `ralph.config.json` (gitignored, never checked in)

### The adapter pattern

Each adapter exports these functions:

- `get_adapter_command(config_file)` — One-shot command for workers/reviewers (e.g., `claude --model sonnet -p`)
- `get_initial_command(config_file)` — First turn of an interactive session (includes `--output-format json`)
- `get_session_command(config_file, session_id)` — Resume an existing session (includes `--resume`)
- `get_manager_command(config_file)` — Lightweight command for the manager AI (uses `manager_model`)

Adapters live in `adapters/` and include tool-specific configuration files (rules, hooks, agent definitions) that Ralph uses internally.
