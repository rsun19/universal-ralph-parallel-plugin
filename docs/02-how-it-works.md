# How It Works

This document explains the full lifecycle of a Ralph run, from the moment you type `ralph start` to the final completion report.

## The Big Picture

```
You provide a prompt (inline, file, or interactive)
        |
        v
  [Worktree created: <repo>-worktrees/ralph-<session_id>]
        |
        v
  [Interactive Session]
        |
        |-- Inner loop (turns)
        |   Ralph sends your prompt to the AI. The AI works on
        |   the task, spawning sub-agents as needed. A manager AI
        |   reads each turn's output and responds — approving
        |   plans, answering questions, providing guidance.
        |
        |-- Outer loop (retries)
        |   After turns are exhausted, the manager AI reads the
        |   git diff and compares against requirements. If
        |   something is missing, a fresh session starts with
        |   specific retry feedback.
        |
        v
  Completion Report
```

## Inner Loop (Turns)

When you run `ralph start -p "your prompt"`, Ralph starts an interactive multi-turn session with the AI tool.

1. **First turn**: Ralph sends your prompt along with a team orchestration template. The AI reads the prompt, proposes a plan, and may spawn sub-agents to work on different parts in parallel.
2. **Manager response**: A lightweight **manager AI** (a separate, cheaper model) reads the AI's output and generates a response — approving the plan, answering questions, or providing guidance.
3. **Resume**: Ralph resumes the session with the manager's response, and the AI continues working.
4. **Repeat**: This continues for up to `turns` conversations (default: 50).

Each turn logs elapsed time so you can distinguish slow turns from stuck ones:

```
[INFO]  Turn 3/10: Manager AI generating response...
[INFO]  Manager (8s): **APPROVED** - Continue with the current plan...
[INFO]  Turn 3/10: Resuming session...
[INFO]  Turn 3/10: Complete (resume: 45s, total turn: 53s)
```

## Outer Loop (Retries)

After the inner loop finishes (turns exhausted or completion detected):

1. The manager AI reads the actual `git diff` from the working directory
2. It compares the diff against the original prompt requirements
3. If all requirements are met, the session is complete
4. If requirements are missing, a **fresh session** starts with a summary of what's incomplete
5. This repeats up to `loop.max_iterations` times (default: 3)

```
Attempt 1:
  Turn 1: AI reads prompt, proposes plan     → Manager approves
  Turn 2: AI implements code                  → Manager: "looks good, continue"
  Turn 3: AI writes tests                     → Manager: "tests passing, complete"
  → Verify git diff → "Missing input validation" → RETRY

Attempt 2:
  Turn 1: Fresh session with: "Add input validation (missing from attempt 1)"
  Turn 2: AI adds validation + tests          → Manager approves
  → Verify git diff → "All requirements met"  → DONE
```

## Session Isolation

Each `ralph start` creates a git worktree at `<repo>-worktrees/ralph-<session_id>` on branch `ralph/<session_id>`. All work happens in this isolated directory. Session state (logs, config) is stored in `state/sessions/<session_id>/`.

## Logs

Every AI turn's output is saved to a log file. Browse them interactively with `ralph sessions`.

```
state/sessions/<id>/logs/agent-teams/<id>/attempt-N/
  turn-01.json        # Raw JSON output from AI
  turn-01.log         # Human-readable output
  manager-02.log      # Manager AI response
  verification.log    # Manager AI diff verdict
```

## The "Ralph Loop" Concept

At its core, every session runs the same basic pattern: send a prompt, read the output, decide what to do next, repeat. The AI sees the codebase change between turns because it modified files in the previous turn. This is the self-referential feedback loop — the AI reads its own past work and improves on it.

The prompt doesn't need to change because the context (the actual code on disk) changes. Ralph relies on the AI's ability to read files, notice what's done vs. what's missing, and make incremental progress.
