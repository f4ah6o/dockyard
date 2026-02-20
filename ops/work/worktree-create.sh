#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_core_deps

repo="${1:-}"
runners="${2:-1}"

[[ -n "$repo" ]] || die "Usage: ops/work/worktree-create.sh <repo> [runners]"

base_repo="$DOCKYARD_ROOT/repos/$repo"
[[ -d "$base_repo/.git" ]] || die "Missing baseline repo: $base_repo"

ensure_dir "$DOCKYARD_ROOT/worktrees/$repo"

for ((i = 1; i <= runners; i++)); do
	runner_id="run-$i"
	wt_dir="$DOCKYARD_ROOT/worktrees/$repo/$runner_id"
	if [[ -d "$wt_dir/.git" || -f "$wt_dir/.git" ]]; then
		log_info "Worktree exists: worktrees/$repo/$runner_id"
		continue
	fi

	git -C "$base_repo" worktree add -B "dockyard/$runner_id" "$wt_dir" HEAD
	log_info "Created worktree: worktrees/$repo/$runner_id"
done
