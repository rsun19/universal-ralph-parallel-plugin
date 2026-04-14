---
description: "Start Ralph Wiggum agent team with manager, implementers, and reviewers"
argument-hint: "PROMPT [--max-iterations N] [--completion-promise TEXT] [--implementers N] [--reviewers N] [--mode auto|shell|claude-teams]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-team.sh:*)", "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/team-status.sh:*)"]
hide-from-slash-command-tool: "true"
---

# Ralph Team Command

Execute the setup script to initialize the Ralph agent team:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-team.sh" $ARGUMENTS
```

The script creates a state file at `.claude/ralph-team.local.json` and outputs the team configuration.

## After setup completes

Read the script output carefully. It tells you the execution mode:

### If mode is `shell`

The stop hook will keep this session alive. Work through the task from the prompt iteratively. Each time you try to exit, the stop hook feeds the prompt back. Focus on one task at a time from `fix_plan.md`.

### If mode is `claude-teams`

The script outputs a `TEAM_CONFIG_START` / `TEAM_CONFIG_END` JSON block. Use it to create the agent team:

1. Read the JSON config from the script output
2. Create an agent team matching the `roles` array (spawn each listed teammate using its `agent_type`)
3. Break the prompt into 5-15 subtasks in the shared task list
4. Assign tasks to implementer teammates
5. When implementers finish, assign completed tasks to reviewer teammates
6. If reviewers reject, re-assign to implementers with the feedback
7. Repeat until all tasks are approved

CRITICAL: Only output `<promise>ALL_TASKS_COMPLETE</promise>` when every task is genuinely approved by a reviewer. Do not lie to exit the loop.

## Check status at any time

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/team-status.sh"
```
