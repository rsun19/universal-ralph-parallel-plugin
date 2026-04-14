# Troubleshooting

## Common issues

### "No ralph.config.json found"

Ralph needs a config file before it can run. Create one by running:

```bash
ralph init
```

This walks you through an interactive setup wizard. If you want to skip the wizard and start from the example file, copy it manually:

```bash
cp ralph.config.example.json ralph.config.json
ralph settings  # open in your editor
```

### "Prompt required"

You need to tell Ralph what to work on. Pass it inline or as a file:

```bash
ralph start -p "Build a REST API for todos" -r /path/to/project
ralph start -p PROMPT.md -r /path/to/project
```

Or just omit `-p` and Ralph will ask you interactively.

### "Required command not found: jq"

Install jq:

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

### Agents seem stuck / no progress

Check status:

```bash
ralph status
```

If tasks are `in_progress` but agents are listed as dead, the agent processes crashed. Ralph's manager normally respawns them, but if the manager itself died:

```bash
# Cancel and restart
ralph cancel
ralph start -p PROMPT.md -r /path/to/project
```

### Tasks keep getting rejected

Check the reviewer logs:

```bash
ls state/logs/*-review.log
cat state/logs/<task-id>-review.log
```

Common reasons:
- **Tests don't pass** - the implementer may not have run tests or the tests are broken
- **Placeholder code found** - the AI took a shortcut with TODO/FIXME stubs
- **Missing functionality** - the implementation doesn't match the task description

To fix: improve your prompt to be more specific about what "done" means. Add explicit test instructions.

### The AI keeps doing placeholder implementations

Add stronger language to your prompt:

```markdown
CRITICAL: Do NOT implement placeholders, stubs, or TODO comments.
Every function must have a complete, working implementation.
Every new function must have tests.
```

The prompt templates already include this instruction, but for particularly stubborn models, reinforcing it in your PROMPT.md helps.

### "flock: command not found"

`flock` is used for file locking to prevent race conditions when multiple agents claim tasks simultaneously. It's available on Linux by default but not on macOS.

On macOS, install it via:

```bash
brew install flock
```

Alternatively, if you're on macOS and can't install flock, run with a single implementer (`-n 1`) to avoid the need for file locking.

### Git conflicts between agents

If two implementer agents edit the same file, you can get merge conflicts. Prevent this by:

1. Writing prompts that produce independent tasks (different files)
2. Reducing implementers to 1-2 for tightly-coupled codebases
3. Using `"commit_on_success": false` and committing manually

### High token usage

Each agent runs its own AI session. With 3 implementers + 2 reviewers + 1 manager planning call, a full run can use a significant number of tokens.

To reduce costs:
- Reduce implementers: `-n 1`
- Reduce reviewers: `-R 1`
- Lower max iterations: `-m 10`
- Write very specific prompts (less AI guessing = fewer iterations)
- Use a cheaper model in your config

### AI tool asks for permission during loop

Ralph needs the AI tool to run without interactive approval prompts. You have two options:

1. **Configure permissions via config file** (recommended):
   - Claude Code: `~/.claude/settings.json` — [docs](https://code.claude.com/docs/en/permissions)
   - Cursor: `~/.cursor/cli-config.json` — [docs](https://cursor.com/docs/cli/reference/permissions)
   - Copilot: no config-based option (see below)

2. **Skip all prompts at runtime:**
   ```bash
   ralph start --allow-all -p "your prompt"
   ```

Copilot CLI does not support config-file-based permissions, so `--allow-all` is always included in the Copilot adapter by default.

## Inspecting state

### Task files

```bash
# List all tasks
ls state/tasks/

# View a specific task
cat state/tasks/task-XXXXXXXX.json | jq .

# See all task statuses at once
for f in state/tasks/task-*.json; do
  echo "$(jq -r '.status' "$f")  $(jq -r '.title' "$f")"
done
```

### Agent registry

```bash
# See registered agents
ls state/agents/

# Check a specific agent
cat state/agents/impl-1-XXXXXXXX.json | jq .
```

### Iteration logs

```bash
# List logs for a specific task
ls state/logs/task-XXXXXXXX-iter-*.log

# Read the first iteration's output
cat state/logs/task-XXXXXXXX-iter-1.log

# Read the review log
cat state/logs/task-XXXXXXXX-review.log
```

### Effective config

If you used CLI overrides, the resolved config is at:

```bash
cat state/.ralph-config-effective.json | jq .
```

## Resetting state

To start fresh without reinstalling:

```bash
rm -rf state/tasks/*.json state/agents/*.json state/messages/*.json state/logs/*
```

Or just use `ralph cancel` which cleans up messages and locks but preserves tasks for inspection.

## Getting help

```bash
# CLI help
ralph --help

# Check installed version/structure
ls bin/ lib/ adapters/
```
