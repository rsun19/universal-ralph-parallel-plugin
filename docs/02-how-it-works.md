# How It Works

This document explains the full lifecycle of a Ralph run, from the moment you type `ralph start` to the final completion report.

> **Note:** The phase-based architecture described below (planning, implementation, review) applies to the **legacy bash orchestration mode**, which is not actively maintained and may be broken. Agent teams (`agent_teams: true`) is the recommended and actively maintained mode. See [Agent Teams](06-claude-teams.md) for details.

## The Big Picture

```
You provide a prompt (inline, file, or interactive)
        |
        v
  [Worktree created: <repo>-worktrees/ralph-<session_id>]
        |
        v
  [Manager Agent]
        |
        |-- Phase 1: PLANNING
        |   Sends your prompt to the AI, asks it to break the
        |   work into 5-15 discrete tasks.
        |
        |-- Phase 2: IMPLEMENTATION
        |   Spawns N implementer agents in parallel.
        |   Each one claims a task, runs an AI loop on it,
        |   and marks it done when finished.
        |
        |-- Phase 3: REVIEW
        |   Spawns M reviewer agents in parallel.
        |   Each one picks up a completed task, asks the AI
        |   to review it, and approves or rejects it.
        |
        |-- Phase 4: RETRY or COMPLETE
        |   Rejected tasks go back to pending with feedback.
        |   If tasks remain, loop back to Phase 2.
        |   If all tasks are approved (or permanently failed),
        |   generate a completion report and stop.
        v
  Completion Report
```

## Phase 1: Planning

When you run `ralph start -p "your prompt"` (or `-p spec.md` for a file), the manager agent starts first. It reads your prompt and sends it to the AI tool with instructions to break the work into a JSON array of tasks.

The AI returns something like:

```json
[
  {"title": "Set up project structure", "description": "...", "priority": "high"},
  {"title": "Create database schema", "description": "...", "priority": "high"},
  {"title": "Implement GET /books endpoint", "description": "...", "priority": "medium"}
]
```

The manager turns each of these into a **task file** stored in the session's `state/sessions/<id>/tasks/` directory and writes a human-readable `fix_plan.md` in the session state.

## Phase 2: Implementation

The manager spawns implementer agents as background processes. By default, 3 run in parallel.

Each implementer does this in a loop:

1. **Claim a task** - looks through the session's task directory for a `pending` task with no unresolved dependencies, atomically marks it `in_progress` (using file locking so two agents can't grab the same task)
2. **Build a prompt** - takes the task title and description, wraps it in the implementation prompt template, and appends any previous review feedback if this is a retry
3. **Run the AI** - pipes the prompt to whatever AI tool is configured (Claude Code, Cursor, Copilot, etc.)
4. **Check for completion** - looks for the text `TASK_DONE` in the AI's output
5. **Report back** - marks the task as `completed` and optionally commits to git
6. **Repeat** - goes back to step 1 to claim the next task

If the AI doesn't output `TASK_DONE` within the max iterations, the task is still marked completed (the manager and reviewers will catch quality issues).

When there are no more tasks to claim, the implementer shuts itself down.

## Phase 3: Review

After all implementers finish, the manager moves `completed` tasks to `review` status and spawns reviewer agents.

Each reviewer:

1. **Claims a review task** - same file-locking mechanism as implementers
2. **Builds a review prompt** - asks the AI to check recent git changes, run tests, look for placeholders
3. **Runs the AI** - the reviewer AI examines the code and outputs a JSON verdict:
   ```json
   {"decision": "approve", "summary": "Tests pass, implementation complete", "issues": []}
   ```
4. **Updates the task** - either marks it `approved` or sends it back to `pending` with the rejection feedback attached

## Phase 4: Retry or Complete

After reviewers finish, the manager checks the task list:

- If all tasks are `approved` or permanently `failed` (exceeded max retries), it's done
- If there are tasks back in `pending` status (rejected by reviewers), the manager loops back to Phase 2, spawning new implementers. These implementers will see the previous review feedback in their prompt, so they know what to fix.

The default max retries per task is 3. After 3 failed attempts, a task is marked `failed` permanently.

## File-Based Coordination

Everything is coordinated through files on disk. No network servers, no databases, no message queues.

### Session isolation

Each `ralph start` creates a git worktree at `<repo>-worktrees/ralph-<session_id>` on branch `ralph/<session_id>`. All work happens in this isolated directory. Session state (tasks, logs, config) is stored in `state/sessions/<session_id>/`.

### Task files (`state/sessions/<id>/tasks/task-XXXX.json`)

Each task is a JSON file:

```json
{
  "id": "task-a1b2c3d4",
  "title": "Implement GET /books endpoint",
  "description": "Create a GET endpoint at /books that returns all books...",
  "status": "pending",
  "assignee": "",
  "attempt_count": 0,
  "max_retries": 3,
  "depends_on": [],
  "priority": "medium",
  "created_at": "2025-01-15T10:30:00Z",
  "updated_at": "2025-01-15T10:30:00Z",
  "review_feedback": ""
}
```

Task status flow:

```
pending --> in_progress --> completed --> review --> approved
                                           |
                                           v
                                       (rejected)
                                           |
                                           v
                                        pending  (with review_feedback set)
                                           |
                                         ... retry up to max_retries ...
                                           |
                                           v
                                        failed  (permanently)
```

### Agent registry (`state/sessions/<id>/agents/`)

Each running agent registers itself with its process ID, role, and current task. The manager uses this to detect dead agents and respawn replacements.

### Messages (`state/sessions/<id>/messages/`)

Agents can send messages to each other (e.g., "Task X completed" or "Task Y rejected"). The manager reads these to stay informed, though the primary coordination happens through task file status changes.

### Logs (`state/sessions/<id>/logs/`)

Every AI call's output is saved to a log file for debugging. Browse them interactively with `ralph sessions`.

## The "Ralph Loop" Concept

At its core, every agent runs the same basic pattern:

```bash
while not_done; do
  cat prompt.md | ai_tool > output.log
  check_if_done output.log
  sleep 2
done
```

The AI sees the same prompt each time, but the **codebase changes** between iterations because the AI modified files in the previous iteration. This is the self-referential feedback loop: the AI reads its own past work from the filesystem and improves on it.

The prompt doesn't need to change because the context (the actual code on disk) changes. Ralph relies on the AI's ability to read files, notice what's done vs. what's missing, and make incremental progress.
