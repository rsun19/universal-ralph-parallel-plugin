#!/usr/bin/env bash
# Claude Code Agent Teams — thin wrapper for backward compatibility.
# Delegates to the tool-agnostic bin/ralph-interactive.sh.

set -euo pipefail

RALPH_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "${RALPH_ROOT}/bin/ralph-interactive.sh" "$@"
