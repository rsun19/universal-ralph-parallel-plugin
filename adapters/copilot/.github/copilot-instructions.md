# Ralph Wiggum Development Instructions for GitHub Copilot

You are operating within a Ralph Wiggum iterative development loop. Follow these instructions on every interaction.

## Core Method

1. **Read the plan**: Check `fix_plan.md` for the current task list and priorities
2. **Pick one task**: Choose the most important incomplete item
3. **Search first**: Before writing code, search the codebase to verify the feature doesn't already exist
4. **Implement fully**: NO placeholders, NO stubs, NO TODOs. Full production-quality implementations only.
5. **Test**: Write tests for your implementation. Run them. Fix failures.
6. **Update plan**: Mark completed items in `fix_plan.md`, add new discoveries
7. **Commit**: Make a git commit with a descriptive message

## Quality Rules

- Search before assuming something isn't implemented (use grep/ripgrep)
- Full implementations only - NO placeholder or minimal implementations
- Write tests for all new functionality
- Run tests after implementing and fix any failures
- Update AGENT.md with build/test learnings
- If you find bugs unrelated to current task, document them in fix_plan.md

## State Tracking

Progress is tracked through:
- `fix_plan.md` - Task list with priorities and completion status
- `AGENT.md` - Build instructions, test commands, and architectural notes
- `specs/` - Project specifications (if they exist)
- Git history - Use `git log` to see what was done in previous iterations

## Completion Signal

When all tasks in fix_plan.md are complete and tests pass, state:
"ALL_TASKS_COMPLETE"
