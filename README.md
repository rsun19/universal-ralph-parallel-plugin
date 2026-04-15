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
| `team.implementers` | Number of parallel implementer agents | `3` |
| `team.reviewers` | Number of parallel reviewer agents | `2` |
| `team.max_retries_per_task` | Max retry attempts per task | `3` |
| `loop.max_iterations` | Max iterations per agent loop | `50` |
| `loop.completion_promise` | Phrase signaling completion | `ALL_TASKS_COMPLETE` |
| `loop.commit_on_success` | Auto-commit on task completion | `true` |
| `claude_teams.enabled` | Use Claude Code Agent Teams natively | `false` |
| `claude_teams.teammate_mode` | `in-process` or `tmux` | `in-process` |

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
  status      Show current team and task status
  cancel      Cancel all running agents and clean up
  plan        Run planning mode only (generate fix_plan.md)
  settings    Open ralph.config.json in your editor

Options:
  -c, --config <file>     Config file (default: ralph.config.json)
  -r, --repo <path>       Target repository path
  -t, --tool <name>       AI tool: claude-code, cursor, copilot, generic
  -p, --prompt <text|file> Inline prompt text OR path to a .md file
  -n, --implementers <n>  Number of implementer agents
  -R, --reviewers <n>     Number of reviewer agents
  -m, --max-iterations    Max loop iterations per agent
  --completion-promise     Phrase that signals task completion
  --claude-teams           Use Claude Code Agent Teams (native mode)
  --allow-all              Skip all permission prompts in the AI tool
```

Run `ralph init` first. The `-p` flag accepts either a file path or inline text. If you omit `-p`, Ralph opens your `$EDITOR` for a full editing experience.

## Claude Code Agent Teams Integration

When `claude_teams.enabled` is `true`, Ralph uses Claude Code's native Agent Teams feature instead of shell-based parallelism:

```bash
ralph start -p "Build auth with JWT" --claude-teams
```

This creates a Claude Code team where:
- **You (the lead)** coordinate the team
- **Implementer teammates** claim and implement tasks
- **Reviewer teammates** check completed work
- Communication uses Claude's native mailbox system
- Tasks use Claude's shared task list with file locking

### Subagent Definitions

The plugin provides reusable agent definitions in `adapters/claude-code/agents/`:

- `manager.md` - Coordinates team, manages task list, handles retries
- `implementer.md` - Implements tasks with full code and tests
- `reviewer.md` - Reviews code quality, tests, and spec compliance

These can be referenced when spawning teammates:

```
Spawn a teammate using the implementer agent type to work on the auth module.
```

## Architecture

```
User
 └── ralph CLI
      └── Manager Agent (outer loop)
           ├── Phase 1: Planning
           │    └── AI generates task breakdown → fix_plan.md
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

### Task States

```
pending → in_progress → completed → review → approved
                  ↑                    │
                  └──── rejected ◄─────┘
                  (with feedback, up to max_retries)
```

### File-Based Coordination

All coordination uses the filesystem (no network dependencies):
- **Tasks**: `state/tasks/*.json` - individual task files with `flock` locking
- **Messages**: `state/messages/*.json` - inter-agent mailbox
- **Agents**: `state/agents/*.json` - agent registry with heartbeats
- **Logs**: `state/logs/` - iteration output logs

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
