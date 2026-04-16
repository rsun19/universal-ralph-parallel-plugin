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
│   ├── utils.sh                  # Logging, config, template rendering, ID generation
│   ├── loop-engine.sh            # Core Ralph loop (run AI, check promise)
│   ├── session-loop.sh           # Interactive session engine (multi-turn + retries)
│   ├── team-prompt.sh            # Tool-agnostic team prompt generator
│   ├── task-manager.sh           # Task CRUD, claiming, status transitions
│   ├── agent-registry.sh         # Agent lifecycle tracking
│   ├── worktree.sh               # Git worktree create/remove/list
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
├── templates/                    # Default prompt templates (read-only source)
│   ├── prompt-plan.md            # Planning prompt (task breakdown)
│   ├── prompt-implement.md       # Implementation prompt (per task)
│   ├── prompt-review.md          # Review prompt (per task)
│   ├── prompt-manager.md         # Manager coordination prompt
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
│           ├── fix_plan.md       # Generated task breakdown
│           ├── tasks/            # Task JSON files
│           ├── agents/           # Agent registry files
│           ├── messages/         # Inter-agent messages
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

**Bash orchestration mode** (legacy — not maintained, use `agent_teams: true` instead):

7. `bin/ralph` calls `bin/ralph-manager.sh`
8. `ralph-manager.sh` sources all `lib/*.sh` libraries
9. It runs **Phase 1**: builds a planning prompt from `state/templates/prompt-plan.md`, pipes it to the AI tool, parses the JSON task list, creates files in the session's `tasks/` directory
10. It runs **Phase 2**: spawns `bin/ralph-worker.sh` processes. Each worker claims tasks, builds prompts from `state/templates/prompt-implement.md`, runs the AI in a loop, and updates task status
11. It runs **Phase 3**: spawns `bin/ralph-review.sh` processes. Each reviewer claims completed tasks, builds prompts from `state/templates/prompt-review.md`, runs the AI, and approves or rejects
12. Prints merge instructions showing how to merge the worktree branch back

**Interactive session mode** (`agent_teams: true`, recommended):

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

- `get_adapter_command(config_file)` — One-shot command for workers/reviewers (e.g., `claude --model sonnet -p`)
- `get_initial_command(config_file)` — First turn of an interactive session (includes `--output-format json`)
- `get_session_command(config_file, session_id)` — Resume an existing session (includes `--resume`)
- `get_manager_command(config_file)` — Lightweight command for the manager AI (uses `manager_model`)

Adapters live in `adapters/` and include tool-specific configuration files (rules, hooks, agent definitions) that Ralph uses internally.
