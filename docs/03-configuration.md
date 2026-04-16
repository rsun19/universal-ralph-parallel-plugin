# Configuration

Settings live in `ralph.config.json`, which is created when you run `ralph init`. You can also override most settings via CLI flags. A reference example is shipped as `ralph.config.example.json`.

## Full configuration reference

```json
{
  "version": "1.0.0",
  "default_target_repo": ".",
  "prompt_text": "",
  "ai_tool": "claude-code",
  "ai_tool_command": "claude -p",
  "model": "sonnet",
  "manager_model": "sonnet",
  "turns": 50,
  "team": {
    "implementers": 3,
    "reviewers": 2
  },
  "loop": {
    "max_iterations": 3,
    "completion_promise": "ALL_TASKS_COMPLETE"
  },
  "claude_teams": {
    "teammate_mode": "in-process"
  }
}
```

## Settings explained

### `default_target_repo`

**What it does:** The default project repository that Ralph will work on. This is used unless overridden at session start time via `--repo`.

**Default:** `"."` (current directory)

**Example:** `"/Users/me/projects/my-app"`

All AI agents `cd` into this directory before running. This is where code gets written, tests get run, and git commits happen.

**Per-session override:** Use `--repo /path/to/repo` to target a different repository for a single session without changing the default. Use `--repo` (no path) to interactively scan and pick a repository. Neither changes `ralph.config.json`.

---

### `prompt_text`

**What it does:** The prompt to give Ralph, embedded directly in the config file. This is an alternative to passing `-p` on the command line.

**Default:** `""` (empty — Ralph will ask interactively if no prompt is provided anywhere)

**Example:** `"Build a REST API for todos with CRUD endpoints and tests"`

You can set the prompt in three ways (Ralph checks in this order):
1. `-p` flag on the CLI (text or file path)
2. `prompt_text` in the config file
3. Interactive input (Ralph asks you at runtime)

---

### `ai_tool`

**What it does:** Which AI tool adapter to use. This determines how Ralph invokes the AI.

**Default:** `"claude-code"`

**Options:** `"claude-code"`, `"cursor"`, `"copilot"`, `"generic"`

Each option loads a different adapter from the `adapters/` directory. See [Choosing an AI Tool](04-ai-tools.md) for details.

**CLI override:** `-t cursor` or `--tool cursor`

---

### `ai_tool_command`

**What it does:** The exact shell command used to invoke the AI tool. The prompt is piped to this command via stdin.

**Default:** Depends on the adapter. Examples:
- Claude Code: `"claude --model sonnet -p"`
- Cursor: `"agent --model sonnet -p"`
- Copilot: `"copilot --allow-all --model sonnet -p"`
- Custom: `"./my-ai-wrapper.sh"`

When a built-in adapter exists (claude-code, cursor, copilot), the adapter's `get_adapter_command()` is the canonical source for the runtime command and **replaces** this value at startup. The `ai_tool_command` in config is only used directly when `ai_tool` is set to `"generic"` or when no adapter file is found.

Permission-skipping flags (e.g. `--dangerously-skip-permissions` for Claude Code) are **not** included by default — except for the Copilot adapter, which always includes `--allow-all` because Copilot CLI has no config-file-based permission system. Use `ralph start --allow-all` to add them at runtime for other tools, or configure permissions via the tool's config file. See [Choosing an AI Tool](04-ai-tools.md) for per-tool permission setup.

---

### `model`

**What it does:** Which model to use, passed to the AI tool adapter.

**Default:** `"sonnet"`

This is adapter-specific. For Claude Code, it maps to `--model sonnet`. Other adapters may ignore it or translate it differently.

---

### `manager_model`

**What it does:** Which model to use for the manager AI in interactive session mode. The manager AI approves plans, answers questions, and verifies completion between turns.

**Default:** `"sonnet"`

A cheaper/faster model is recommended here since the manager only needs to make quick approval/rejection decisions, not write code. Even if your main `model` is `opus`, the manager can safely run on `sonnet` or `haiku`.

---

### `turns`

**What it does:** Maximum number of conversation turns per attempt. Each turn is one message exchange between Ralph and the AI.

**Default:** `50`

This is the inner loop bound. If the AI doesn't produce a completion promise within this many turns, the attempt ends and the outer verification loop kicks in.

---

### `team.implementers`

**What it does:** How many implementer agents to run in parallel.

**Default:** `3`

More implementers means more tasks worked on simultaneously, but also more token usage and more potential for file conflicts if tasks touch the same files.

**Recommendation:** Start with 3. Increase to 5 for projects with lots of independent modules. Decrease to 1-2 if tasks are tightly coupled.

**CLI override:** `-n 5` or `--implementers 5`

---

### `team.reviewers`

**What it does:** How many reviewer agents to run in parallel.

**Default:** `2`

Reviewers run after implementers finish. They check code quality, test coverage, and spec compliance.

**CLI override:** `-R 3` or `--reviewers 3`

---

### `loop.max_iterations`

**What it does:** Maximum number of retry attempts if the manager AI determines requirements aren't fully met after reading the git diff.

**Default:** `3`

This is the outer loop bound — each retry starts a fresh session with specific feedback about what's missing.

**CLI override:** `-m 5` or `--max-iterations 5`

---

### `loop.completion_promise`

**What it does:** A text phrase that signals overall completion. Used by the manager-level loop and the Claude Code stop hook.

**Default:** `"ALL_TASKS_COMPLETE"`

**CLI override:** `--completion-promise "FINISHED"`

---

### `claude_teams.teammate_mode`

**What it does:** Display mode for Claude Code Agent Teams.

**Default:** `"in-process"`

**Options:** `"in-process"` (all in one terminal, use Shift+Down to cycle) or `"tmux"` (separate panes per teammate).

## CLI flags quick reference

| Flag | Config key | Example |
|------|-----------|---------|
| `-c, --config` | (file path) | `-c my-config.json` |
| `-r, --repo` | (session override) | `-r /path/to/project` or `--repo` |
| `--cli` | (session override) | `--cli claude-code` or `--cli` |
| `--model` | (session override) | `--model opus` |
| `-t, --tool` | `ai_tool` (permanent) | `-t cursor` |
| `-p, --prompt` | `prompt_file` | `-p PROMPT.md` |
| `-n, --implementers` | `team.implementers` | `-n 5` |
| `-R, --reviewers` | `team.reviewers` | `-R 3` |
| `-m, --max-iterations` | `loop.max_iterations` | `-m 5` |
| `--completion-promise` | `loop.completion_promise` | `--completion-promise DONE` |
| `--allow-all` | `allow_all` | `--allow-all` |

CLI flags override config file values. The effective config is written to the session directory so you can inspect what was actually used.

> **Session-only flags:** `--repo`, `--cli`, and `--model` override the target repo, AI tool, and model for a single session without changing `ralph.config.json`. When `--cli` changes the tool, Ralph auto-prompts for model selection (skip with `--model`).

## Switching tools and models

You can change your AI tool and model without editing the config file manually:

```bash
ralph agent switch
```

This walks you through selecting a new CLI tool (claude-code, cursor, copilot, generic) and optionally a new model, then updates `ralph.config.json` automatically.

## Prompt templates

Ralph uses prompt templates to instruct agents. Editable copies are stored in `state/templates/` and defaults live in `templates/`. Missing templates are auto-copied on `ralph init` and `ralph start`.

```bash
ralph templates              # List all templates
ralph templates prompt-team.md  # Edit a template
ralph templates --reset      # Reset all to defaults
```
