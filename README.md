# Ralph Wiggum - Universal AI Agent Team Orchestrator

> "I'm helping!" - Ralph Wiggum

Ralph is a CLI tool that turns any AI coding assistant into a **team of AI agents** that plan, implement, review, and iterate on code — autonomously. You give it a prompt, and it coordinates multiple AI agents to get the job done.

It works with **Claude Code**, **Cursor**, **GitHub Copilot**, or any CLI-based AI tool.

## Why Ralph?

Writing code with AI one prompt at a time is slow. Ralph automates the entire loop:

1. You describe what you want (a feature, a bug fix, a refactor)
2. Ralph breaks it into subtasks, assigns them to AI agents, reviews the results, and retries failures
3. You get a finished branch ready to merge

No babysitting. No copy-pasting between chat windows. Just one command.

## Quick Start

### 1. Install

```bash
git clone <this-repo> ralph-wiggum
cd ralph-wiggum
./install.sh --link
```

### 2. Set up (first time only)

```bash
ralph init
```

This walks you through an interactive wizard: pick your AI tool (Claude Code, Cursor, Copilot), choose a model, point it at your project repository, and configure team size. Creates `ralph.config.json`.

### 3. Run it

```bash
ralph start -p "Build a REST API for todos with CRUD, validation, SQLite, and tests"
```

That's it. Ralph creates an isolated git branch, sends your prompt to the AI, coordinates the work, and tells you when it's done.

## Common Use Cases

### Basic: one feature, one repo

Your config already has a default repo and tool. Just tell Ralph what to build:

```bash
ralph start -p "Add user authentication with JWT tokens and bcrypt password hashing"
```

Or omit `-p` and Ralph opens your `$EDITOR` so you can write a detailed spec:

```bash
ralph start
```

### Ad-hoc: different repo, different tool, different model

You don't have to change your config to work on a different project. Use session flags to override anything for a single run:

```bash
# Work on a different repo (just this session — config unchanged)
ralph start --repo /path/to/other-project -p "Fix the login bug"

# Don't know the path? Launch the interactive repo scanner
ralph start --repo

# Use a different AI tool (auto-prompts for model selection)
ralph start --cli claude-code -p "Refactor the database layer"

# Use a specific model
ralph start --model opus -p "Complex architectural refactor"

# Combine everything: different repo + tool + model
ralph start --repo ~/projects/backend --cli claude-code --model opus -p "Add caching layer"
```

None of these change `ralph.config.json`. Each session is fully isolated.

### Parallel: multiple features at once

Every `ralph start` creates its own **git worktree** on a new branch. Run as many as you want in separate terminals:

```bash
# Terminal 1
ralph start -p "Build the auth module"

# Terminal 2
ralph start --repo ~/projects/frontend -p "Add dark mode"

# Terminal 3
ralph start --model opus -p "Write integration tests"
```

Each session works independently — different worktree, different branch, no conflicts. When done, merge whichever branches you want.

### Monitoring and managing sessions

```bash
# See all sessions and their status
ralph sessions

# Browse logs for a specific session
ralph sessions --session <id>

# Clean up a finished session (removes worktree, branch, and state)
ralph prune --session <id>

# Clean up everything
ralph prune
```

## How It Works

Ralph runs a **two-level loop**:

**Inner loop (turns):** Ralph sends your prompt to the AI tool. The AI works on the task (creating files, writing tests, etc.). Between turns, a lightweight **manager AI** reads the output and responds — approving plans, answering questions, or providing guidance. This simulates a human operator so the AI can work unattended.

**Outer loop (retries):** After the inner loop finishes, the manager AI reviews the `git diff` against your original requirements. If something is missing, Ralph starts a fresh session with specific feedback about what needs fixing. This repeats until requirements are met or max retries are exhausted.

```
Attempt 1:
  Turn 1: AI reads prompt, proposes plan     → Manager approves
  Turn 2: AI implements code                  → Manager: "looks good, continue"
  Turn 3: AI writes tests                     → Manager: "tests passing, complete"
  → Verify git diff → "Missing input validation" → RETRY

Attempt 2:
  Turn 1: Fresh session with: "Add input validation (missing from attempt 1)"
  Turn 2: AI adds validation + tests          → Manager approves
  → Verify git diff → "All requirements met"  → DONE
```

Each turn logs elapsed time so you can distinguish slow turns from stuck ones:

```
[INFO]  Turn 3/10: Manager AI generating response...
[INFO]  Manager (8s): **APPROVED** - Continue with the current plan...
[INFO]  Turn 3/10: Resuming session...
[INFO]  Turn 3/10: Complete (resume: 45s, total turn: 53s)
```

## Supported AI Tools

| Tool | Adapter | CLI Command |
|------|---------|-------------|
| **Claude Code** | `claude-code` | `claude --model sonnet -p` |
| **Cursor** | `cursor` | `agent --model sonnet -p` |
| **GitHub Copilot** | `copilot` | `copilot --allow-all --model sonnet -p` |
| **Any CLI tool** | `generic` | Configurable in `ralph.config.json` |

Switch tools at any time:

```bash
# Permanently (updates config)
ralph agent switch

# Per-session (config unchanged)
ralph start --cli claude-code --model opus -p "your prompt"
```

## CLI Reference

```
ralph <command> [options]

Commands:
  init        Interactive setup wizard (creates ralph.config.json)
  start       Start a Ralph session on a task
  scan        Find git repos on your system and pick one
  sessions    List sessions, view status, and browse logs
  cancel      Cancel all running agents
  plan        Generate a task breakdown without executing
  agent       Switch AI CLI tool and/or model (updates config)
  templates   List, edit, or reset prompt templates
  settings    Open ralph.config.json in your editor
  prune       Clean up sessions, worktrees, and state

Session flags (override config for one run, never saved):
  -r, --repo [path]       Target repo (interactive scanner if no path)
  --cli [tool]            AI tool (interactive picker if no tool)
  --model [name]          Model (interactive picker if no name)

Config flags (apply to all future runs):
  -t, --tool <name>       Set AI tool permanently
  -p, --prompt <text|file> Prompt text or path to a .md file
  -n, --implementers <n>  Number of implementer agents
  -R, --reviewers <n>     Number of reviewer agents
  -m, --max-iterations    Max retry attempts
  --allow-all             Skip all AI tool permission prompts
  -c, --config <file>     Use a different config file
```

## Configuration

`ralph.config.json` is created by `ralph init` and is gitignored. Edit it with `ralph settings`.

| Key | Description | Default |
|-----|-------------|---------|
| `default_target_repo` | Default project repository | `.` |
| `ai_tool` | AI tool adapter | `claude-code` |
| `ai_tool_command` | Shell command for the AI tool | varies |
| `model` | Model for worker agents | `sonnet` |
| `manager_model` | Model for the manager AI | `sonnet` |
| `turns` | Max conversation turns per attempt | `50` |
| `team.implementers` | Parallel implementer agents | `3` |
| `team.reviewers` | Parallel reviewer agents | `2` |
| `loop.max_iterations` | Max retry attempts | `3` |
| `loop.completion_promise` | Phrase signaling task completion | `ALL_TASKS_COMPLETE` |

## Session Isolation

Every `ralph start` creates a git worktree at `<repo>-worktrees/ralph-<session_id>` on branch `ralph/<session_id>`. This means:

- Multiple sessions run in parallel on different features
- No session can interfere with another's code
- Your main branch stays clean until you merge
- Each session's state lives in `state/sessions/<id>/`

When a session completes, Ralph prints merge instructions:

```bash
# Review changes
cd /path/to/worktree && git diff main

# Merge into main
cd /path/to/original-repo && git merge ralph/<session_id>

# Or push for a PR
git push -u origin ralph/<session_id>

# Clean up
ralph prune --session <session_id>
```

## Customizing Prompts

Ralph uses markdown templates to instruct its agents. You can customize them:

```bash
# List all templates (shows which ones you've modified)
ralph templates

# Edit a specific template
ralph templates prompt-team.md

# Reset all templates to defaults
ralph templates --reset
```

Templates live in `state/templates/` and are auto-copied from `templates/` on first run.

## Repo Scanner

Don't know the path to your repo? Ralph can find it:

```bash
ralph scan              # scans ~, ~/projects, ~/code, etc.
ralph scan ~/work       # scans a specific folder
ralph start --repo      # scanner built into start
```

Shows a numbered list of git repos with branch, language, and last commit date.

## Permissions

Ralph runs AI agents in unattended loops, so they need file and shell permissions. **By default, Ralph respects each tool's native permission config.**

| Tool | Config file | `--allow-all` adds |
|------|------------|-------------------|
| Claude Code | `~/.claude/settings.json` | `--dangerously-skip-permissions` |
| Cursor | `~/.cursor/cli-config.json` | `--force --approve-mcps` |
| Copilot | (none — always uses `--allow-all`) | `--allow-all` |

```bash
# Skip all permission prompts for a session
ralph start --allow-all -p "Build the thing"
```

## Error Handling

Ralph detects common failures and stops immediately instead of wasting retries:

- **No session ID returned** — the AI tool command failed (wrong model, not installed, etc.). Ralph prints the tool's error output and suggests a fix.
- **API errors** (404, auth failures, model not found, rate limits) — Ralph aborts the session with diagnostic details.
- **Stalled sessions** (3 consecutive empty outputs) — Ralph ends the inner loop and moves to verification.

## Prerequisites

- **bash** (3.2+)
- **jq** (for JSON processing)
- An AI coding tool CLI: `claude`, `agent` (Cursor), `copilot`, or any CLI tool

## Prompt Writing Tips

**Be specific about completion criteria:**

```markdown
Build a REST API for todos.

When complete:
- All CRUD endpoints working
- Input validation on all endpoints
- Tests passing with > 80% coverage
- README with API documentation
```

**Break large tasks into phases:**

```markdown
Phase 1: User authentication (JWT, login/register, tests)
Phase 2: Product catalog (list, search, pagination, tests)
Phase 3: Shopping cart (add/remove/checkout, tests)
```

**Include self-correction instructions:**

```markdown
Follow TDD: write failing tests first, implement, run tests,
debug any failures, refactor, repeat until all green.
```

## Documentation

| Doc | What it covers |
|-----|---------------|
| [Getting Started](docs/01-getting-started.md) | Install, setup, first run |
| [How It Works](docs/02-how-it-works.md) | Full lifecycle: turns, retries, verification |
| [Configuration](docs/03-configuration.md) | Every setting explained |
| [AI Tools](docs/04-ai-tools.md) | Setup for Claude Code, Cursor, Copilot |
| [Writing Prompts](docs/05-writing-prompts.md) | Prompts that get results |
| [Agent Teams](docs/06-claude-teams.md) | Interactive session mode and subagent definitions |
| [Troubleshooting](docs/07-troubleshooting.md) | Common issues and fixes |
| [Project Structure](docs/08-project-structure.md) | Every file and directory |

## Philosophy

From [Geoffrey Huntley's original technique](https://ghuntley.com/ralph/):

1. **Iteration over perfection** — don't aim for perfect on the first try. Let the loop refine.
2. **Failures are data** — each failure helps tune the next iteration.
3. **Operator skill matters** — success depends on good prompts, not just good models.
4. **Persistence wins** — the loop handles retry logic so you don't have to.

## Learn More

- Original technique: https://ghuntley.com/ralph/
- Claude Code Agent Teams: https://code.claude.com/docs/en/agent-teams

## License

MIT
