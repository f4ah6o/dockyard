#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_core_deps

repo="${1:-}"
runner_id="${2:-}"
job_id="${3:-}"
slug="${4:-task}"

[[ -n "$repo" && -n "$runner_id" && -n "$job_id" ]] || die "Usage: ops/work/ensure-branch.sh <repo> <runner_id> <job_id> [slug]"

wt_dir="$DOCKYARD_ROOT/worktrees/$repo/$runner_id"
[[ -d "$wt_dir" ]] || die "Missing worktree: $wt_dir"

branch="r/$job_id/$runner_id/$slug"
git -C "$wt_dir" checkout -B "$branch"

echo "$branch"
