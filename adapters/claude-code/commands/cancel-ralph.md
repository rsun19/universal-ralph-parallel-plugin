---
description: "Cancel active Ralph Wiggum agent team and all running agents"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/cancel-team.sh:*)", "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/team-status.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Cancel Ralph

Execute the cancel script to stop all agents and report final status:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/cancel-team.sh"
```

The script will:
1. Read the team state from `.claude/ralph-team.local.json`
2. Kill all shell-mode agent processes (if applicable)
3. Print the final task status summary (pending, completed, approved, failed)
4. Remove the state file
5. Clean up lock files and messages

If using Claude Code Agent Teams (native mode), also ask all teammates to shut down before running the cancel script.

Report the script's output to the user verbatim.
