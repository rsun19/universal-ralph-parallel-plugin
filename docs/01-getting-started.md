# Getting Started

This guide walks you through everything from installation to running your first Ralph Wiggum agent team.

## What is this?

Ralph Wiggum is a system that makes AI coding tools work **in a loop**. Instead of asking an AI to build something once, Ralph asks it over and over, and the AI improves its work each time by reading what it already wrote on disk.

On top of that basic loop, this plugin adds **teams**: a manager agent breaks your task into pieces, several implementer agents work on those pieces in parallel, and reviewer agents check the quality of each piece. If a reviewer rejects something, it goes back to an implementer to fix.

## Prerequisites

You need two things installed:

1. **bash** (version 4.0 or later) - already on macOS and Linux
2. **jq** - a command-line JSON processor

Install jq if you don't have it:

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Fedora
sudo dnf install jq
```

You also need at least one AI coding tool. Any of these work:

| Tool | Install | Notes |
|------|---------|-------|
| Claude Code | `npm install -g @anthropic-ai/claude-code` | Best supported; has native Agent Teams mode |
| Cursor | Download from cursor.com | Works via rules + CLI adapter |
| GitHub Copilot | `gh extension install github/gh-copilot` | Via gh CLI extension |
| Aider | `pip install aider-chat` | Open source, works great |
| Any CLI tool | Must accept a prompt via stdin or flag | Fully configurable |

## Installation

### Step 1: Clone the plugin

```bash
git clone <repo-url> ralph-wiggum-cursor-plugin
cd ralph-wiggum-cursor-plugin
```

### Step 2: Run the installer

The simplest install just makes everything executable:

```bash
./install.sh
```

To also add `ralph` to your system PATH so you can run it from anywhere:

```bash
./install.sh --link
```

Or add the `bin/` directory to your PATH manually in your `~/.zshrc` or `~/.bashrc`:

```bash
export PATH="/path/to/ralph-wiggum-cursor-plugin/bin:$PATH"
```

### Step 3: Initialize Ralph (first time only)

```bash
ralph init
```

This launches an interactive setup wizard that asks you:
- **Target repository path** — where your project lives
- **AI tool** — which AI tool you want to use (Claude Code, Cursor, Copilot, etc.)
- **Team size** — how many implementer and reviewer agents
- **Loop settings** — max iterations per agent
- **Claude Teams** — whether to use native Agent Teams mode (Claude Code only)

It generates your personal `ralph.config.json` (gitignored) and sets up the target repo with:
- `AGENT.md` — where Ralph records learnings about your project
- `fix_plan.md` — the shared task list that Ralph maintains
- `specs/` — a directory for project specifications
- Adapter-specific files (e.g., `.cursor/rules/` for Cursor)

To edit your config later: `ralph settings`

You can also use **scan mode** to find repos on your filesystem instead of typing a path:

```bash
ralph scan
ralph scan ~/projects
```

### Step 4: Start Ralph

```bash
ralph start -p "Build a REST API for a bookstore with Express, TypeScript, SQLite, and Jest tests"
```

Or omit `-p` and Ralph will ask you interactively:

```bash
ralph start
# → "No prompt provided. What should Ralph work on?"
# → Type your prompt and press Enter
```

You can also point `-p` at a file for longer specs:

```bash
ralph start -p detailed-spec.md
```

That's it. Ralph will:
1. Ask the AI to read your prompt and break it into subtasks
2. Launch 3 implementer agents in parallel to work on those subtasks
3. Launch 2 reviewer agents to check completed work
4. Retry anything that gets rejected
5. Print a report when everything is done (or max iterations are hit)

## What to expect

- **It takes time.** Each agent runs AI calls in a loop. A full run can take 30 minutes to several hours depending on task complexity.
- **It uses tokens.** Each agent has its own AI session. With 3 implementers + 2 reviewers, you're running 5 parallel AI sessions plus the manager. Budget accordingly.
- **It commits to git.** By default, Ralph commits after each successful task. You can disable this with `"commit_on_success": false` in your config.
- **It's not perfect.** Ralph is "deterministically bad" - it makes mistakes, but they're predictable and fixable through more iterations.

## Monitoring progress

While Ralph is running, open another terminal and check status:

```bash
ralph status
```

This shows you:
- How many tasks are pending, in progress, completed, in review, approved, or failed
- Which agents are running and what they're working on

## Stopping Ralph

To cancel everything:

```bash
ralph cancel
```

This kills all agent processes but preserves the task state so you can inspect what happened.

## Standalone mode (scan)

Ralph can run as standalone software, not just as a plugin inside a project. The `ralph scan` command traverses your filesystem to find git repositories, lets you pick one, and then initializes + starts Ralph on it -- all from a single command:

```bash
# Scan default locations (~, ~/projects, ~/code, ~/dev, etc.)
ralph scan

# Scan a specific directory tree
ralph scan ~/work

# Scan and auto-start with an inline prompt
ralph scan ~/work -p "Build a REST API for the bookstore"
```

This means you don't need to `cd` into a project or know its exact path. Ralph finds it for you.

## Next steps

- [How It Works](02-how-it-works.md) - understand the architecture
- [Configuration](03-configuration.md) - tune team size, iterations, and more
- [Choosing an AI Tool](04-ai-tools.md) - setup guides for each supported tool
- [Writing Good Prompts](05-writing-prompts.md) - get better results
- [Claude Code Agent Teams](06-claude-teams.md) - native team mode
- [Troubleshooting](07-troubleshooting.md) - common issues and fixes
