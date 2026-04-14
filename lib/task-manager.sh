#!/usr/bin/env bash
# File-based task management with atomic operations and file locking

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

TASK_DIR=""

init_task_dir() {
  local ralph_root="${1:-$(resolve_ralph_root)}"
  TASK_DIR="${ralph_root}/state/tasks"
  mkdir -p "$TASK_DIR"
}

# Create a new task
# Returns the task ID
task_create() {
  local title="$1"
  local description="${2:-}"
  local depends_on="${3:-}"
  local max_retries="${4:-3}"
  local priority="${5:-medium}"

  [[ -z "$TASK_DIR" ]] && init_task_dir

  local task_id
  task_id=$(generate_id "task")

  local task_file="${TASK_DIR}/${task_id}.json"
  local now
  now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  local task_json
  task_json=$(jq -n \
    --arg id "$task_id" \
    --arg title "$title" \
    --arg desc "$description" \
    --arg status "pending" \
    --arg assignee "" \
    --argjson attempt 0 \
    --argjson max_retries "$max_retries" \
    --arg depends_on "$depends_on" \
    --arg priority "$priority" \
    --arg created "$now" \
    --arg updated "$now" \
    --arg review_feedback "" \
    '{
      id: $id,
      title: $title,
      description: $desc,
      status: $status,
      assignee: $assignee,
      attempt_count: $attempt,
      max_retries: $max_retries,
      depends_on: ($depends_on | split(",") | map(select(. != ""))),
      priority: $priority,
      created_at: $created,
      updated_at: $updated,
      review_feedback: $review_feedback
    }'
  )

  atomic_write "$task_file" "$task_json"
  ralph_log INFO "Created task $task_id: $title"
  echo "$task_id"
}

# Read a task
task_get() {
  local task_id="$1"
  [[ -z "$TASK_DIR" ]] && init_task_dir

  local task_file="${TASK_DIR}/${task_id}.json"
  if [[ ! -f "$task_file" ]]; then
    ralph_log ERROR "Task not found: $task_id"
    return 1
  fi
  cat "$task_file"
}

# Update a task field
task_update() {
  local task_id="$1"
  local field="$2"
  local value="$3"

  [[ -z "$TASK_DIR" ]] && init_task_dir

  local task_file="${TASK_DIR}/${task_id}.json"
  if [[ ! -f "$task_file" ]]; then
    ralph_log ERROR "Task not found: $task_id"
    return 1
  fi

  local lock_file="${task_file}.lock"
  (
    flock -w 5 200 || { ralph_log ERROR "Could not acquire lock for $task_id"; exit 1; }

    local now
    now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local updated
    updated=$(jq --arg field "$field" --arg value "$value" --arg now "$now" \
      '.[$field] = $value | .updated_at = $now' "$task_file")
    atomic_write "$task_file" "$updated"
  ) 200>"$lock_file"
}

# Claim a pending task for a worker (atomic)
# Returns task ID or empty if none available
task_claim() {
  local assignee="$1"
  [[ -z "$TASK_DIR" ]] && init_task_dir

  local claimed=""

  for task_file in "$TASK_DIR"/task-*.json; do
    [[ -f "$task_file" ]] || continue

    local lock_file="${task_file}.lock"
    (
      flock -n 200 || exit 1

      local status assignee_current
      status=$(jq -r '.status' "$task_file")
      assignee_current=$(jq -r '.assignee' "$task_file")

      if [[ "$status" == "pending" ]] && [[ -z "$assignee_current" || "$assignee_current" == "" ]]; then
        # Check dependencies are met
        local deps_met=true
        local deps
        deps=$(jq -r '.depends_on[]?' "$task_file")
        for dep_id in $deps; do
          local dep_file="${TASK_DIR}/${dep_id}.json"
          if [[ -f "$dep_file" ]]; then
            local dep_status
            dep_status=$(jq -r '.status' "$dep_file")
            if [[ "$dep_status" != "completed" ]] && [[ "$dep_status" != "approved" ]]; then
              deps_met=false
              break
            fi
          fi
        done

        if [[ "$deps_met" == "true" ]]; then
          local now
          now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
          local attempt
          attempt=$(jq -r '.attempt_count' "$task_file")
          attempt=$((attempt + 1))

          jq --arg assignee "$assignee" --arg now "$now" --argjson attempt "$attempt" \
            '.status = "in_progress" | .assignee = $assignee | .attempt_count = $attempt | .updated_at = $now' \
            "$task_file" > "${task_file}.tmp.$$"
          mv "${task_file}.tmp.$$" "$task_file"

          local task_id
          task_id=$(jq -r '.id' "$task_file")
          echo "$task_id"
          exit 0
        fi
      fi
      exit 1
    ) 200>"$lock_file" && { claimed=$(cat <(jq -r '.id' "$task_file")); break; } || continue
  done

  # Re-read to get claimed task ID via a simpler approach
  if [[ -z "$claimed" ]]; then
    for task_file in "$TASK_DIR"/task-*.json; do
      [[ -f "$task_file" ]] || continue
      local a
      a=$(jq -r '.assignee' "$task_file" 2>/dev/null)
      local s
      s=$(jq -r '.status' "$task_file" 2>/dev/null)
      if [[ "$a" == "$assignee" ]] && [[ "$s" == "in_progress" ]]; then
        jq -r '.id' "$task_file"
        return 0
      fi
    done
  fi
}

# Mark task complete
task_complete() {
  local task_id="$1"
  task_update "$task_id" "status" "completed"
  ralph_log INFO "Task $task_id marked completed"
}

# Mark task for review
task_submit_for_review() {
  local task_id="$1"
  task_update "$task_id" "status" "review"
  ralph_log INFO "Task $task_id submitted for review"
}

# Approve a reviewed task
task_approve() {
  local task_id="$1"
  task_update "$task_id" "status" "approved"
  ralph_log INFO "Task $task_id approved"
}

# Reject a task with feedback
task_reject() {
  local task_id="$1"
  local feedback="$2"

  [[ -z "$TASK_DIR" ]] && init_task_dir

  local task_file="${TASK_DIR}/${task_id}.json"
  local lock_file="${task_file}.lock"

  (
    flock -w 5 200 || { ralph_log ERROR "Could not lock $task_id"; exit 1; }

    local max_retries attempt
    max_retries=$(jq -r '.max_retries' "$task_file")
    attempt=$(jq -r '.attempt_count' "$task_file")

    local now
    now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    if [[ $attempt -ge $max_retries ]]; then
      jq --arg fb "$feedback" --arg now "$now" \
        '.status = "failed" | .review_feedback = $fb | .updated_at = $now' \
        "$task_file" > "${task_file}.tmp.$$"
      mv "${task_file}.tmp.$$" "$task_file"
      ralph_log WARN "Task $task_id permanently failed after $attempt attempts"
    else
      jq --arg fb "$feedback" --arg now "$now" \
        '.status = "pending" | .assignee = "" | .review_feedback = $fb | .updated_at = $now' \
        "$task_file" > "${task_file}.tmp.$$"
      mv "${task_file}.tmp.$$" "$task_file"
      ralph_log INFO "Task $task_id rejected (attempt $attempt/$max_retries), re-queued"
    fi
  ) 200>"$lock_file"
}

# List tasks by status
task_list() {
  local filter_status="${1:-all}"
  [[ -z "$TASK_DIR" ]] && init_task_dir

  for task_file in "$TASK_DIR"/task-*.json; do
    [[ -f "$task_file" ]] || continue
    
    if [[ "$filter_status" == "all" ]]; then
      cat "$task_file"
    else
      local status
      status=$(jq -r '.status' "$task_file")
      if [[ "$status" == "$filter_status" ]]; then
        cat "$task_file"
      fi
    fi
  done | jq -s '.'
}

# Get summary counts
task_summary() {
  [[ -z "$TASK_DIR" ]] && init_task_dir

  local total=0 pending=0 in_progress=0 completed=0 review=0 approved=0 failed=0

  for task_file in "$TASK_DIR"/task-*.json; do
    [[ -f "$task_file" ]] || continue
    total=$((total + 1))
    local status
    status=$(jq -r '.status' "$task_file")
    case "$status" in
      pending) pending=$((pending + 1)) ;;
      in_progress) in_progress=$((in_progress + 1)) ;;
      completed) completed=$((completed + 1)) ;;
      review) review=$((review + 1)) ;;
      approved) approved=$((approved + 1)) ;;
      failed) failed=$((failed + 1)) ;;
    esac
  done

  jq -n \
    --argjson total "$total" \
    --argjson pending "$pending" \
    --argjson in_progress "$in_progress" \
    --argjson completed "$completed" \
    --argjson review "$review" \
    --argjson approved "$approved" \
    --argjson failed "$failed" \
    '{total: $total, pending: $pending, in_progress: $in_progress, completed: $completed, review: $review, approved: $approved, failed: $failed}'
}

# Check if all tasks are done (approved or permanently failed)
all_tasks_done() {
  [[ -z "$TASK_DIR" ]] && init_task_dir

  for task_file in "$TASK_DIR"/task-*.json; do
    [[ -f "$task_file" ]] || continue
    local status
    status=$(jq -r '.status' "$task_file")
    if [[ "$status" != "approved" ]] && [[ "$status" != "failed" ]]; then
      return 1
    fi
  done
  return 0
}
