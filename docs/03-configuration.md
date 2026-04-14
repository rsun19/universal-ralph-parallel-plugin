# Configuration

Settings live in `ralph.config.json`, which is created when you run `ralph init`. You can also override most settings via CLI flags. A reference example is shipped as `ralph.config.example.json`.

## Full configuration reference

```json
{
  "version": "1.0.0",
  "target_repo": ".",
  "prompt_text": "",
  "ai_tool": "claude-code",
  "ai_tool_command": "claude --dangerously-skip-permissions -p",
  "model": "sonnet",
  "team": {
    "implementers": 3,
    "reviewers": 2,
    "max_retries_per_task": 3
  },
  "loop": {
    "max_iterations": 50,
    "completion_promise": "ALL_TASKS_COMPLETE",
    "commit_on_success": true,
    "pause_between_iterations_sec": 2
  },
  "claude_teams": {
    "enabled": false,
    "teammate_mode": "in-process"
  },
  "review": {
    "check_tests": true,
    "check_placeholders": true,
    "check_spec_compliance": true,
    "auto_approve_on_pass": false
  }
}
```

## Settings explained

### `target_repo`

**What it does:** The path to the project repository that Ralph will work on.

**Default:** `"."` (current directory)

**Example:** `"/Users/me/projects/my-app"`

All AI agents `cd` into this directory before running. This is where code gets written, tests get run, and git commits happen.

**CLI override:** `-r /path/to/repo` or `--repo /path/to/repo`

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

**Default:** Depends on the adapter, but for Claude Code it's `"claude --dangerously-skip-permissions -p"`

**Examples:**
- Claude Code: `"claude --dangerously-skip-permissions -p"`
- Aider: `"aider --message"`
- Custom: `"./my-ai-wrapper.sh"`

If an adapter is loaded (via `ai_tool`), the adapter may override this command. If you set `ai_tool` to `"generic"`, this command is used directly.

---

### `model`

**What it does:** Which model to use, passed to the AI tool adapter.

**Default:** `"sonnet"`

This is adapter-specific. For Claude Code, it maps to `--model sonnet`. Other adapters may ignore it or translate it differently.

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

### `team.max_retries_per_task`

**What it does:** Maximum number of times a task can be retried after being rejected by a reviewer.

**Default:** `3`

When a reviewer rejects a task, it goes back to `pending` with the rejection feedback attached. The next implementer that picks it up will see the feedback. After this many total attempts, the task is marked `failed` permanently.

---

### `loop.max_iterations`

**What it does:** Maximum number of AI calls per agent per task.

**Default:** `50`

This is a safety limit. Each implementer will run at most this many AI iterations on a single task before giving up. This prevents infinite loops on impossible tasks.

**CLI override:** `-m 30` or `--max-iterations 30`

---

### `loop.completion_promise`

**What it does:** A text phrase that signals overall completion. Used by the manager-level loop and the Claude Code stop hook.

**Default:** `"ALL_TASKS_COMPLETE"`

Individual task completions use `"TASK_DONE"` instead (hardcoded in the worker).

**CLI override:** `--completion-promise "FINISHED"`

---

### `loop.commit_on_success`

**What it does:** Whether to automatically `git add -A && git commit` after each task is completed.

**Default:** `true`

Each commit message includes the task title and ID, making it easy to trace which Ralph task produced which changes.

---

### `loop.pause_between_iterations_sec`

**What it does:** Seconds to pause between AI iterations within a single task loop.

**Default:** `2`

Prevents hammering the AI API too aggressively. Increase if you're hitting rate limits.

---

### `claude_teams.enabled`

**What it does:** Whether to use Claude Code's native Agent Teams feature instead of shell-based parallelism.

**Default:** `false`

When `true`, Ralph delegates to Claude Code's built-in team system where the manager becomes a "team lead" and implementers/reviewers become "teammates" communicating through Claude's native mailbox. See [Claude Code Agent Teams](06-claude-teams.md).

**CLI override:** `--claude-teams`

---

### `claude_teams.teammate_mode`

**What it does:** Display mode for Claude Code Agent Teams.

**Default:** `"in-process"`

**Options:** `"in-process"` (all in one terminal, use Shift+Down to cycle) or `"tmux"` (separate panes per teammate).

---

### `review.check_tests`

**What it does:** Whether reviewers should verify that tests exist and pass.

**Default:** `true`

---

### `review.check_placeholders`

**What it does:** Whether reviewers should search for TODO, FIXME, stub, and placeholder patterns.

**Default:** `true`

---

### `review.check_spec_compliance`

**What it does:** Whether reviewers should verify the implementation matches the task description.

**Default:** `true`

---

### `review.auto_approve_on_pass`

**What it does:** If `true`, tasks that pass all automated checks are approved without a full AI review.

**Default:** `false`

## CLI flags quick reference

| Flag | Config key | Example |
|------|-----------|---------|
| `-c, --config` | (file path) | `-c my-config.json` |
| `-r, --repo` | `target_repo` | `-r /path/to/project` |
| `-t, --tool` | `ai_tool` | `-t cursor` |
| `-p, --prompt` | `prompt_file` | `-p PROMPT.md` |
| `-n, --implementers` | `team.implementers` | `-n 5` |
| `-R, --reviewers` | `team.reviewers` | `-R 3` |
| `-m, --max-iterations` | `loop.max_iterations` | `-m 30` |
| `--completion-promise` | `loop.completion_promise` | `--completion-promise DONE` |
| `--claude-teams` | `claude_teams.enabled` | `--claude-teams` |

CLI flags override config file values. The effective config is written to `state/.ralph-config-effective.json` so you can inspect what was actually used.
