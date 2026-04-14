# Writing Good Prompts

The quality of Ralph's output depends almost entirely on the quality of your prompt. This guide covers what works and what doesn't.

## The basics

Your prompt is passed to Ralph via the `-p` flag — either as inline text or a file path. Ralph's planning agent reads it and breaks it into subtasks. Each subtask becomes a task that an implementer agent works on.

```bash
# Inline (quick tasks)
ralph start -p "Build a REST API for todos with CRUD, validation, and tests"

# From a file (complex tasks where you want to write a detailed spec)
ralph start -p PROMPT.md

# Interactive (Ralph asks you)
ralph start -r ./my-project
```

A good prompt tells the AI **what to build**, **how to verify it works**, and **when it's done**.

## Structure of a good prompt

```markdown
Build [thing].

## Requirements
- Specific requirement 1
- Specific requirement 2
- Specific requirement 3

## Technical Details
- Language/framework: X
- Database: Y
- File structure: describe expected layout

## Acceptance Criteria
- All tests pass
- No placeholder implementations
- [Specific measurable criteria]
```

## Examples

### Good: specific, testable, scoped

```markdown
Build a REST API for managing a book inventory.

## Requirements
- Express.js with TypeScript
- SQLite database using better-sqlite3
- Endpoints:
  - GET /books - list all books (supports ?author= query param)
  - GET /books/:id - get a single book
  - POST /books - create a book (requires: title, author, isbn, price)
  - PUT /books/:id - update a book
  - DELETE /books/:id - delete a book
- Input validation: title and author are required strings, isbn must be
  13 digits, price must be a positive number
- Error responses: 400 for validation errors, 404 for not found, 500 for
  server errors, all as JSON with an "error" field

## Technical Details
- Project structure: src/ for source, tests/ for tests
- Use express-validator for input validation
- Database file: data/books.db (auto-created on first run)

## Tests
- Jest with supertest for API testing
- Test each endpoint's happy path and error cases
- Test input validation edge cases

## Acceptance Criteria
- All tests pass with `npm test`
- Server starts with `npm start` on port 3000
- No TODO or placeholder code
```

### Bad: vague, no verification criteria

```markdown
Build a bookstore app. Make it good and use best practices.
```

This is bad because:
- "bookstore app" could mean anything (frontend? backend? both?)
- "good" and "best practices" are subjective and unverifiable
- No specification of endpoints, data model, or behavior
- No way for the AI (or reviewers) to know when it's done

### Good: incremental phases

For larger projects, break work into phases:

```markdown
Build a user authentication system for an Express.js API.

## Phase 1: Core Auth
- User model with email, hashed password, created_at
- POST /auth/register - create account with email + password
- POST /auth/login - return JWT token
- Middleware to verify JWT on protected routes
- Password hashing with bcrypt
- Tests for register, login, and middleware

## Phase 2: Session Management
- Token refresh endpoint: POST /auth/refresh
- Token expiry (1 hour access, 7 day refresh)
- Logout endpoint that invalidates refresh token
- Tests for token refresh and expiry

## Phase 3: Password Reset
- POST /auth/forgot-password - sends reset token (log to console, no email)
- POST /auth/reset-password - accepts token + new password
- Reset tokens expire after 1 hour
- Tests for the full reset flow

Each phase should have passing tests before moving to the next.
```

## Key principles

### 1. Be specific about file paths and technology choices

The AI needs to know where to put things. "Create an API" leaves too many decisions open. "Create an Express.js API in `src/server.ts` with routes in `src/routes/`" gives it a clear target.

### 2. Define "done" concretely

"All tests pass" is concrete. "Works well" is not. The reviewer agent needs measurable criteria to decide approve vs. reject.

### 3. Include test instructions

Tell the AI what testing framework to use and what to test. This creates backpressure - the tests act as a verification mechanism that keeps the AI honest.

### 4. One scope of work per prompt

Don't ask for a full-stack application in one prompt. Break it up:
- Prompt 1: Backend API
- Prompt 2: Database migrations
- Prompt 3: Frontend
- Prompt 4: Integration tests

### 5. Reference specs if they exist

If you created spec files in `specs/`, reference them:

```markdown
Implement the API as specified in specs/api-spec.md.
Implement the database schema as specified in specs/schema-spec.md.
```

The AI will read these files from disk.

## Anti-patterns to avoid

| Don't | Do instead |
|-------|-----------|
| "Make it production-ready" | List specific production requirements (error handling, logging, etc.) |
| "Use best practices" | Name the specific practices you want (input validation, error handling, etc.) |
| "Fix the bugs" | Describe the specific bug or reference a failing test |
| "Refactor the code" | Describe what the refactored code should look like |
| "Build a complete X" | Break X into phases with specific deliverables per phase |

## Using specs

The Ralph approach recommends having a conversation with the AI about your requirements *before* starting the loop. Use `ralph plan` to generate a task breakdown, then review and refine it.

You can also create spec files manually:

```bash
mkdir -p specs
# Write specs/api-spec.md, specs/schema-spec.md, etc.
```

Then reference them in your prompt. The AI reads these from disk each iteration, so they act as a stable reference that doesn't consume context window space.
