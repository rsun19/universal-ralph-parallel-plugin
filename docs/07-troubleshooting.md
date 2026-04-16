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

### The AI keeps doing placeholder implementations

Add stronger language to your prompt:

```markdown
CRITICAL: Do NOT implement placeholders, stubs, or TODO comments.
Every function must have a complete, working implementation.
Every new function must have tests.
```

The prompt templates already include this instruction, but for particularly stubborn models, reinforcing it in your PROMPT.md helps.

### High token usage

Each session runs multiple AI turns plus manager AI calls. To reduce costs:
- Lower max iterations: `-m 1`
- Write very specific prompts (less AI guessing = fewer turns)
- Use a cheaper model for `manager_model` in your config

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

### Session appears stuck (no progress for 10+ minutes)

Each turn now logs elapsed time. If you see "Resuming session..." with no "Complete" line for 10+ minutes, the API call is genuinely hung — not just slow.

**Fix:** `Ctrl-C` the hung session and restart. Normal turns complete in 30-120 seconds.

## Inspecting state

### Sessions

```bash
# List all sessions interactively
ralph sessions

# Browse a specific session's logs
ralph sessions --session <id>

# View session metadata
cat state/sessions/<id>/session.json | jq .
```

### Effective config

Each session stores its resolved config:

```bash
cat state/sessions/<id>/.ralph-config-effective.json | jq .
```

### Worktrees

```bash
# List all Ralph worktrees
git worktree list | grep ralph

# Navigate to a session's worktree
cd <repo>-worktrees/ralph-<session_id>
```

## Resetting state

To clean up a single session (removes worktree, branch, and state):

```bash
ralph prune --session <id>
```

To wipe everything back to factory fresh:

```bash
ralph prune
```

## Getting help

```bash
# CLI help
ralph --help

# Check installed version/structure
ls bin/ lib/ adapters/
```
