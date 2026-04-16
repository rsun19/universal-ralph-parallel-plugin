Create an agent team for a Ralph Wiggum iterative development session.

## The Task
{{PROMPT_CONTENT}}

## Team Structure
Create the following teammates:

### Implementers ({{NUM_IMPLEMENTERS}})
{{IMPLEMENTER_LIST}}
### Reviewers ({{NUM_REVIEWERS}})
{{REVIEWER_LIST}}
## Workflow
1. Break the task into 5-15 discrete subtasks in the shared task list
2. Assign tasks to implementers
3. Implementers plan their approach (you must approve before they code)
4. Once implemented, assign the task to a reviewer
5. If rejected, update the task with feedback and reassign to an implementer
6. Max retries per task: {{MAX_RETRIES}}
7. When all tasks are approved, output: <promise>ALL_TASKS_COMPLETE</promise>

## Quality Standards
- No placeholder or stub implementations
- All code must have tests
- Tests must pass
- Reviewers verify spec compliance

## Target Repository
{{TARGET_REPO}}

## Manager Rules
- Wait for teammates to complete their tasks before proceeding
- If a task is stuck, provide specific guidance
- Track progress against the plan and broadcast updates
- Broadcast progress updates periodically
- Only approve implementer plans that include test coverage
