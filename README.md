# Ralph Wiggum - Universal AI Agent Team Orchestrator

> "I'm helping!" - Ralph Wiggum

A universal implementation of the [Ralph Wiggum technique](https://ghuntley.com/ralph/) for iterative, self-referential AI development loops. Works with **Claude Code**, **Cursor**, **GitHub Copilot**, and any CLI-based AI tool.

Extends the core Ralph loop with **agent team orchestration**: a manager coordinates parallel implementers and reviewers, with automatic retry logic and quality gates.

## What is Ralph?

Ralph is a development methodology based on continuous AI agent loops. In its purest form:

```bash
while :; do cat PROMPT.md | claude; done
```

This plugin implements Ralph with:
- **Agent Teams**: A manager + parallel implementers + parallel reviewers
- **Task Management**: Shared task list with dependencies, retries, and progress tracking
- **Quality Gates**: Reviewers verify code quality, tests, and spec compliance before approval
- **Multi-Tool Support**: Same orchestration works across any AI coding tool
- **Claude Code Agent Teams**: Native integration with Claude's team spawning when available

## Quick Start

### 1. Install

**From a clone:**

```bash
git clone <this-repo> ralph-wiggum
cd ralph-wiggum
./install.sh --link
```

**From a release tarball / binary archive:**

```bash
tar xzf ralph-wiggum-v1.0.0.tar.gz
cd ralph-wiggum-v1.0.0
./install.sh --prefix ~/.local    # installs to ~/.local/share/ralph-wiggum/
```

**Manual placement** (just set the env var):

```bash
export RALPH_ROOT="/path/to/ralph-wiggum"
export PATH="${RALPH_ROOT}/bin:$PATH"
```

### 2. Initialize (first time only)

```bash
ralph init
```

This launches an interactive setup wizard that walks you through:
- Target repository path (type it, scan for it, or use current directory)
- Which AI tool to use
- Which model (sonnet, opus, gpt-4.1, etc.)
- Team size (implementers + reviewers)
- Loop settings

It creates your personal `ralph.config.json` (gitignored — not checked in).

### 3. Start the team

```bash
ralph start -p "Build a REST API for todos with CRUD, validation, SQLite, and tests"
```

Or omit `-p` and Ralph opens your `$EDITOR` so you can write a formatted prompt with lists, headings, and code blocks:

```bash
ralph start
# → Opens your editor (nano, vim, etc.)
# → Write your prompt in markdown, save and close
```

You can also point `-p` at a file for longer specs:

```bash
ralph start -p detailed-spec.md
```

This will:
1. Run an AI planner to break your prompt into 5-15 discrete tasks
2. Spawn 3 implementer agents in parallel
3. Each implementer claims and works on tasks
4. Spawn 2 reviewer agents to check completed work
5. Rejected tasks get re-queued with reviewer feedback
6. Repeat until all tasks are approved or max retries exhausted

## Supported AI Tools

| Tool | Adapter | CLI command |
|------|---------|-------------|
| **Claude Code** | `claude-code` | `claude --model sonnet -p` |
| **Cursor** | `cursor` | `agent --model sonnet -p` |
| **GitHub Copilot** | `copilot` | `copilot --allow-all --model sonnet -p` |
| **Any CLI tool** | `generic` | Configurable command in `ralph.config.json` |

## Configuration

`ralph.config.json` is created by `ralph init` and **gitignored** — it's your local config, not checked in. A reference copy is shipped as `ralph.config.example.json`.

To edit it after creation:

```bash
ralph settings
```

### Configuration Reference

| Key | Description | Default |
|-----|-------------|---------|
| `target_repo` | Path to the project repository | `.` |
| `ai_tool` | Which AI tool adapter to use | `claude-code` |
| `ai_tool_command` | The shell command to invoke the AI tool | varies by adapter |
| `model` | Model to use (passed to adapter) | `sonnet` |
| `manager_model` | Model for the manager AI (approvals, verification) | `sonnet` |
| `turns` | Max conversation turns per attempt (interactive session) | `50` |
| `team.implementers` | Number of parallel implementer agents | `3` |
| `team.reviewers` | Number of parallel reviewer agents | `2` |
| `team.max_retries_per_task` | Max retry attempts per task | `3` |
| `loop.max_iterations` | Max retry attempts if verification fails | `3` |
| `loop.completion_promise` | Phrase signaling completion | `ALL_TASKS_COMPLETE` |
| `loop.commit_on_success` | Auto-commit on task completion | `true` |
| `agent_teams` | Enable interactive agent teams (multi-turn session mode) | `false` |
| `claude_teams.teammate_mode` | Claude-specific: `in-process` or `tmux` | `in-process` |

## Repo Scanner

Don't know the exact path to your repo? Use `scan` to find it:

```bash
ralph scan              # scans common directories (~, ~/projects, ~/code, etc.)
ralph scan ~/work       # scans a specific folder
```

Ralph finds git repositories (up to 4 levels deep), shows a numbered list with branch, language, and last commit date, and lets you pick one to start working on.

## CLI Reference

```
ralph <command> [options]

Commands:
  init        Set up Ralph (interactive wizard, creates ralph.config.json)
  start       Start a Ralph agent team on a task
  scan        Find git repos on your system, pick one, and start Ralph
  sessions    List sessions, view status, and browse logs
  cancel      Cancel all running agents and clean up
  plan        Run planning mode only (generate a task breakdown)
  agent       Switch AI CLI tool and/or model
  templates   List or edit prompt templates
  settings    Open ralph.config.json in your editor
  prune       Clean up sessions, worktrees, and state

Options:
  -c, --config <file>     Config file (default: ralph.config.json)
  -r, --repo <path>       Target repository path
  -t, --tool <name>       AI tool: claude-code, cursor, copilot, generic
  -p, --prompt <text|file> Inline prompt text OR path to a .md file
  -n, --implementers <n>  Number of implementer agents
  -R, --reviewers <n>     Number of reviewer agents
  -m, --max-iterations    Max loop iterations per agent
  --completion-promise     Phrase that signals task completion
  --agent-teams            Use interactive agent teams (multi-turn session mode)
  --allow-all              Skip all permission prompts in the AI tool
```

Run `ralph init` first. The `-p` flag accepts either a file path or inline text. If you omit `-p`, Ralph opens your `$EDITOR` for a full editing experience.

### Session Management

Every `ralph start` creates an isolated **git worktree** on a new branch. This means you can run multiple sessions in parallel without code collisions:

```bash
# Terminal 1
ralph start -p "Build auth module"

# Terminal 2 (runs in its own worktree and branch)
ralph start -p "Build payment integration"
```

When a session completes, Ralph shows you the exact commands to merge or push:

```bash
# View sessions and their status
ralph sessions

# Browse a specific session's logs
ralph sessions --session <id>

# Clean up a finished session (removes worktree + branch + state)
ralph prune --session <id>

# Clean up everything
ralph prune
```

`ralph status` and `ralph logs` are aliases for `ralph sessions`.

### Switching Tools and Models

```bash
ralph agent switch
```

Interactive wizard to change your AI CLI tool and/or model. Updates `ralph.config.json` automatically.

### Customizing Prompt Templates

Ralph uses prompt templates to instruct implementers, reviewers, and managers. Editable copies live in `state/templates/`:

```bash
# List all templates (shows which ones you've customized)
ralph templates

# Edit a template
ralph templates prompt-implement.md

# Reset all templates to defaults
ralph templates --reset
```

## Agent Teams (Interactive Session Mode)

When `agent_teams` is `true`, Ralph runs an **interactive multi-turn session** where the AI spawns parallel sub-agents and a manager AI acts as the human operator, approving plans and providing guidance. **Works with any supported tool** (Claude Code, Cursor, Copilot):

```bash
ralph start -p "Build auth with JWT" --agent-teams
```

### How it works

Ralph uses a **two-level loop**:

**Inner loop (turns):** Each turn is a CLI `-p` call using `--resume` to maintain conversation context. Between turns, a manager AI reads the output and generates approvals, feedback, or guidance. Bounded by the `turns` config key (default: 50).

**Outer loop (retries):** After the inner loop finishes, the manager AI reads the `git diff`, compares it against the original requirements + plan, and decides if the work is complete. If not, a fresh session starts with specific feedback about what's missing. Bounded by `loop.max_iterations` (default: 3).

```
Attempt 1:
  Turn 1: AI creates team, proposes plan → Manager approves
  Turn 2: AI implements tasks → Manager provides feedback
  ...
  Turn N: Session ends → Manager reads git diff → "Auth tests missing"
  → RETRY

Attempt 2:
  Turn 1: Fresh session with: "Previous attempt missing auth tests"
  ...
  Turn N: Manager verifies diff → "All requirements met" → DONE
```

### Configuration

| Key | Description | Default |
|-----|-------------|---------|
| `agent_teams` | Enable interactive agent teams | `false` |
| `turns` | Max conversation turns per attempt | `50` |
| `loop.max_iterations` | Max retry attempts | `3` |
| `manager_model` | Model for the manager AI (cheaper is fine) | `sonnet` |

## Architecture

### Mode 1: Bash Orchestration (default)

```
User
 └── ralph CLI
      └── Creates worktree + branch (ralph/<session_id>)
           └── Manager Agent (outer loop)
                ├── Phase 1: Planning
                │    └── AI generates task breakdown
                ├── Phase 2: Implementation
           │    ├── Worker 1 (inner loop) ─── claims tasks → implements → reports
           │    ├── Worker 2 (inner loop) ─── claims tasks → implements → reports
           │    └── Worker N (inner loop) ─── claims tasks → implements → reports
           ├── Phase 3: Review
           │    ├── Reviewer 1 ─── reviews → approve/reject
           │    └── Reviewer 2 ─── reviews → approve/reject
           └── Phase 4: Retry / Complete
                ├── Rejected tasks → re-queue with feedback
                └── All approved → completion report
```

### Mode 2: Interactive Session (agent_teams: true)

```
User
 └── ralph CLI
      └── Session Loop (outer: retries, inner: turns)
           ├── Attempt 1:
           │    ├── Turn 1: Send team prompt → AI creates team
           │    ├── Turn 2: Manager AI approves plan → resume
           │    ├── Turn N: Manager AI provides feedback → resume
           │    └── Verify: Manager AI reads git diff → incomplete
           ├── Attempt 2:
           │    ├── Turn 1: Fresh session with retry feedback
           │    ├── ...
           │    └── Verify: Manager AI reads git diff → COMPLETE
           └── Done
```

### Task States

```
pending → in_progress → completed → review → approved
                  ↑                    │
                  └──── rejected ◄─────┘
                  (with feedback, up to max_retries)
```

### Worktree Isolation

Every `ralph start` creates a git worktree at `<repo>-worktrees/ralph-<session_id>` on branch `ralph/<session_id>`. This means:
- Multiple sessions can run in parallel on different features
- No session can interfere with another's code changes
- Your main branch stays clean until you explicitly merge
- For Cursor users, each worktree opens in its own Cursor window automatically

### File-Based Coordination

All coordination uses the filesystem (no network dependencies):
- **Sessions**: `state/sessions/<id>/` - per-session state (tasks, logs, config)
- **Tasks**: `state/sessions/<id>/tasks/*.json` - task files with `flock` locking
- **Templates**: `state/templates/` - editable prompt templates
- **Prompts**: `state/prompts/` - generated prompt files
- **Logs**: `state/sessions/<id>/logs/agent-teams/<id>/attempt-N/` - per-turn logs

## Prompt Writing Best Practices

### Clear Completion Criteria

```markdown
Build a REST API for todos.

When complete:
- All CRUD endpoints working
- Input validation in place
- Tests passing (coverage > 80%)
- README with API docs
```

### Incremental Goals

```markdown
Phase 1: User authentication (JWT, tests)
Phase 2: Product catalog (list/search, tests)
Phase 3: Shopping cart (add/remove, tests)
```

### Self-Correction Instructions

```markdown
Implement feature X following TDD:
1. Write failing tests
2. Implement feature
3. Run tests
4. If any fail, debug and fix
5. Refactor if needed
6. Repeat until all green
```

### Safety Nets

Always use `--max-iterations` to prevent runaway loops:

```bash
ralph start -p "Build the thing" -m 30
```

## Using Different Tools

### Cursor

Ralph uses the Cursor CLI (`agent`) to drive agents non-interactively:

```bash
# Install the Cursor CLI
curl https://cursor.com/install -fsS | bash

# Run the setup wizard (select cursor when asked)
ralph init

# Start
ralph start -p "Build a REST API for todos"
```

Ralph pipes prompts to `agent --model <model> -p`, giving you the full Ralph
orchestration (parallel workers, reviewers, retry loops) powered by Cursor.

### GitHub Copilot

Ralph uses the Copilot CLI (`copilot`) to drive agents non-interactively:

```bash
# Install the Copilot CLI
# See: https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli

# Run the setup wizard (select copilot when asked)
ralph init

# Start
ralph start -p "Build a REST API for todos"
```

Ralph pipes prompts to `copilot --allow-all --model <model> -p`, giving you the full
Ralph orchestration (parallel workers, reviewers, retry loops) powered by Copilot.

> **Note:** Copilot CLI does not support config-file-based permissions. `--allow-all`
> is always included in the Copilot adapter. See [Permissions](#permissions) below.

### Custom Tool

Set `ai_tool_command` in your config via `ralph settings`:
```json
{
  "ai_tool": "generic",
  "ai_tool_command": "./my-custom-ai-wrapper.sh"
}
```

## Permissions

Ralph runs AI agents in unattended loops, so they need permission to read files, write files, and run shell commands without prompting you each time. **By default, Ralph respects each tool's native permission config** — it does not skip permissions unless you tell it to.

### Claude Code

Configure permissions in `~/.claude/settings.json` (user-level) or `<project>/.claude/settings.json` (project-level):

```json
{
  "permissions": {
    "allow": ["Bash", "Read", "Edit", "WebFetch"]
  }
}
```

Docs: [code.claude.com/docs/en/permissions](https://code.claude.com/docs/en/permissions)

### Cursor

Configure permissions in `~/.cursor/cli-config.json` (global) or `<project>/.cursor/cli.json` (project-level):

```json
{
  "permissions": {
    "allow": ["Shell(*)", "Read(**)", "Write(**)", "Mcp(*:*)"]
  }
}
```

Docs: [cursor.com/docs/cli/reference/permissions](https://cursor.com/docs/cli/reference/permissions)

### GitHub Copilot (no config-based permissions)

Copilot CLI does **not** have a config-file-based permission system. The only way to skip permission prompts is the `--allow-all` CLI flag, which Ralph's Copilot adapter includes by default. Without it, every tool use prompts for approval, making unattended loops impossible.

Docs: [docs.github.com/en/copilot/how-tos/copilot-cli/allowing-tools](https://docs.github.com/en/copilot/how-tos/copilot-cli/allowing-tools)

### `--allow-all` flag

To skip all permission prompts regardless of config, pass `--allow-all`:

```bash
ralph start --allow-all -p "Build a REST API"
```

This adds the appropriate flag for each tool:

| Tool | Flag added |
|------|-----------|
| Claude Code | `--dangerously-skip-permissions` |
| Cursor | `--force` |
| Copilot | `--allow-all` (always included) |

## Philosophy

Ralph embodies several key principles from [Geoffrey Huntley's original technique](https://ghuntley.com/ralph/):

1. **Iteration over perfection** - Don't aim for perfect on the first try. Let the loop refine.
2. **Failures are data** - Each failure is informative and helps tune the next iteration.
3. **Operator skill matters** - Success depends on writing good prompts, not just having a good model.
4. **Persistence wins** - Keep trying until success. The loop handles retry logic automatically.
5. **One thing at a time** - Each agent focuses on a single task per loop to minimize context window usage.

## Prerequisites

- **bash** (3.2+)
- **jq** (for JSON processing)
- An AI coding tool CLI (`claude`, `agent` for Cursor, `copilot` for GitHub Copilot, or any CLI tool)

## Documentation

Full docs are in the [`docs/`](docs/) directory:

| Doc | What it covers |
|-----|---------------|
| [Getting Started](docs/01-getting-started.md) | Install, set up a project, run your first team |
| [How It Works](docs/02-how-it-works.md) | The full lifecycle: planning, implementation, review, retry |
| [Configuration](docs/03-configuration.md) | Every setting explained |
| [Choosing an AI Tool](docs/04-ai-tools.md) | Setup for Claude Code, Cursor, Copilot, and more |
| [Writing Prompts](docs/05-writing-prompts.md) | How to write prompts that get results |
| [Claude Code Agent Teams](docs/06-claude-teams.md) | Native team mode |
| [Troubleshooting](docs/07-troubleshooting.md) | Common issues and fixes |
| [Project Structure](docs/08-project-structure.md) | Every file and directory explained |

## Learn More

- Original technique: https://ghuntley.com/ralph/
- Claude Code Agent Teams: https://code.claude.com/docs/en/agent-teams
- Claude Code Plugin (upstream): https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum

## License

MIT
