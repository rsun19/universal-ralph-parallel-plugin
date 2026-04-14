# Project Structure

This document explains every file and directory in the plugin.

```
ralph-wiggum/
│
├── bin/                          # Executable scripts
│   ├── ralph                     # Main CLI (entry point for all commands)
│   ├── ralph-manager.sh          # Manager agent orchestrator
│   ├── ralph-worker.sh           # Implementer agent
│   └── ralph-review.sh           # Reviewer agent
│
├── lib/                          # Shared libraries (sourced by scripts)
│   ├── utils.sh                  # Logging, config loading, ID generation
│   ├── loop-engine.sh            # Core Ralph loop (run AI, check promise)
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
│   │   └── ralph-claude-teams.sh         # Native Agent Teams launcher
│   │
│   ├── cursor/                   # Cursor CLI adapter
│   │   └── ralph-cursor-adapter.sh   # Returns: agent --model X -p
│   │
│   ├── copilot/                  # GitHub Copilot CLI adapter
│   │   └── ralph-copilot-adapter.sh  # Returns: copilot --model X -p
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
│   ├── tasks/                    # Task JSON files
│   ├── agents/                   # Agent registry files
│   ├── messages/                 # Inter-agent messages
│   └── logs/                     # AI output logs per iteration
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
2. `bin/ralph` calls `bin/ralph-manager.sh` (or `ralph-claude-teams.sh` if `--claude-teams`)
3. `ralph-manager.sh` sources all `lib/*.sh` libraries
4. It runs **Phase 1**: builds a planning prompt from `templates/prompt-plan.md`, pipes it to the AI tool, parses the JSON task list, creates files in `state/tasks/`
5. It runs **Phase 2**: spawns `bin/ralph-worker.sh` processes in the background. Each worker sources `lib/*.sh`, claims tasks from `state/tasks/`, builds prompts from `templates/prompt-implement.md`, runs the AI in a loop, and updates task status
6. It runs **Phase 3**: spawns `bin/ralph-review.sh` processes. Each reviewer claims completed tasks, builds prompts from `templates/prompt-review.md`, runs the AI, and approves or rejects
7. The manager monitors `state/tasks/` for progress, respawns dead agents, and loops if rejected tasks need retrying

### When you run `ralph init`:

1. An interactive wizard collects your preferences (repo path, AI tool, model, team size)
2. Writes `ralph.config.json` (gitignored, never checked in)

### The adapter pattern

Each adapter exports a `get_adapter_command(config_file)` function that returns the shell command to invoke the AI tool. The manager and workers call this to know how to run the AI.

Adapters live in `adapters/` and include tool-specific configuration files (rules, hooks, agent definitions) that Ralph uses internally.
