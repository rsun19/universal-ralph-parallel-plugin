# Getting Started

This guide walks you through everything from installation to running your first Ralph Wiggum agent team.

## What is this?

Ralph Wiggum is a system that makes AI coding tools work **in a loop**. Instead of asking an AI to build something once, Ralph asks it over and over, and the AI improves its work each time by reading what it already wrote on disk.

On top of that basic loop, this plugin adds **teams**: a manager agent breaks your task into pieces, several implementer agents work on those pieces in parallel, and reviewer agents check the quality of each piece. If a reviewer rejects something, it goes back to an implementer to fix.

## Prerequisites

You need two things installed:

1. **bash** (version 3.2 or later) — already on macOS and Linux
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

| Tool | Install | CLI command |
|------|---------|-------------|
| Claude Code | `npm install -g @anthropic-ai/claude-code` | `claude -p` |
| Cursor | `curl https://cursor.com/install -fsS \| bash` | `agent -p` |
| GitHub Copilot | [Install Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli) | `copilot -p` |
| Any CLI tool | Must accept a prompt via stdin or flag | Configurable via generic adapter |

## Installation

There are three ways to install Ralph.

### Option A: Clone the repo (development)

```bash
git clone <repo-url> ralph-wiggum
cd ralph-wiggum
./install.sh          # make scripts executable
./install.sh --link   # also symlink `ralph` to /usr/local/bin
```

Or add the `bin/` directory to your PATH manually in your `~/.zshrc` or `~/.bashrc`:

```bash
export PATH="/path/to/ralph-wiggum/bin:$PATH"
```

### Option B: Download a release tarball / binary archive

If you downloaded a `.tar.gz` or `.zip` release (no `git clone`), extract it and install to a prefix like `~/.local` or `/opt/ralph`:

```bash
tar xzf ralph-wiggum-v1.0.0.tar.gz
cd ralph-wiggum-v1.0.0
./install.sh --prefix ~/.local
```

This copies Ralph's files into `~/.local/share/ralph-wiggum/` and creates a wrapper at `~/.local/bin/ralph` that bakes in the correct `RALPH_ROOT`. If `~/.local/bin` is already in your PATH, you're done. Otherwise, add it:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Option C: Manual placement

If you put the Ralph directory somewhere yourself, just set `RALPH_ROOT` and add the binary to PATH:

```bash
export RALPH_ROOT="/wherever/you/put/ralph-wiggum"
export PATH="${RALPH_ROOT}/bin:$PATH"
```

Ralph checks for `RALPH_ROOT` first. If it's set and points to a valid directory (containing `lib/`), Ralph uses it directly — no symlink resolution needed.

### Step 2: Initialize Ralph (first time only)

```bash
ralph init
```

This launches an interactive setup wizard that asks you:
- **Target repository path** — type it, scan for it, or use current directory
- **AI tool** — which AI tool you want to use (Claude Code, Cursor, Copilot, etc.)
- **Model** — sonnet, opus, gpt-4.1, etc.
- **Team size** — how many implementer and reviewer agents
- **Loop settings** — max iterations per agent
- **Claude Teams** — whether to use native Agent Teams mode (Claude Code only)

It generates your personal `ralph.config.json` (gitignored).

To edit your config later: `ralph settings`

### Step 3: Start Ralph

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

## Finding repos (scan)

Don't know the exact path? Use `ralph scan` to find repos on your filesystem:

```bash
ralph scan              # scans common directories
ralph scan ~/work       # scans a specific folder
```

Ralph finds git repositories (up to 4 levels deep), shows a numbered list, and lets you pick one to start working on.

## Next steps

- [How It Works](02-how-it-works.md) - understand the architecture
- [Configuration](03-configuration.md) - tune team size, iterations, and more
- [Choosing an AI Tool](04-ai-tools.md) - setup guides for each supported tool
- [Writing Good Prompts](05-writing-prompts.md) - get better results
- [Claude Code Agent Teams](06-claude-teams.md) - native team mode
- [Troubleshooting](07-troubleshooting.md) - common issues and fixes
