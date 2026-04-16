#!/usr/bin/env bash
# Git worktree management for parallel Ralph sessions
#
# Each ralph start creates an isolated worktree so multiple sessions
# can run concurrently on different branches without collision.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"

# Create a worktree for a Ralph session.
#   Args: target_repo  session_id
#   Prints the worktree path to stdout.
worktree_create() {
  local target_repo="$1"
  local session_id="$2"

  local repo_name
  repo_name=$(basename "$target_repo")
  local worktree_base
  worktree_base="$(dirname "$target_repo")/${repo_name}-worktrees"
  local worktree_path="${worktree_base}/ralph-${session_id}"
  local branch_name="ralph/${session_id}"

  mkdir -p "$worktree_base"

  if ! git -C "$target_repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ralph_die "target_repo is not a git repository: $target_repo"
  fi

  git -C "$target_repo" worktree add -b "$branch_name" "$worktree_path" HEAD >/dev/null 2>&1 \
    || ralph_die "Failed to create worktree at $worktree_path"

  echo "$worktree_path"
}

# Remove a worktree and its branch.
#   Args: target_repo  worktree_path
worktree_remove() {
  local target_repo="$1"
  local worktree_path="$2"

  if [[ ! -d "$worktree_path" ]]; then
    return 0
  fi

  local branch_name=""
  branch_name=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

  git -C "$target_repo" worktree remove "$worktree_path" --force 2>/dev/null || true

  if [[ -d "$worktree_path" ]]; then
    rm -rf "$worktree_path"
  fi

  if [[ -n "$branch_name" ]] && [[ "$branch_name" == ralph/* ]]; then
    git -C "$target_repo" branch -D "$branch_name" 2>/dev/null || true
  fi
}

# List Ralph-owned worktrees for a repo.
#   Args: target_repo
#   Prints one worktree path per line.
worktree_list() {
  local target_repo="$1"

  git -C "$target_repo" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { path=$2 } /^branch refs\/heads\/ralph\// { print path }'
}
