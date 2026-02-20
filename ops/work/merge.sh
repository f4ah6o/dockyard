#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_core_deps

repo="${1:-}"
job_id="${2:-}"
slug="${3:-integration}"
shift 3 || true

[[ -n "$repo" && -n "$job_id" ]] || die "Usage: ops/work/merge.sh <repo> <job_id> [slug] <runner_branch...>"
[[ "$#" -gt 0 ]] || die "Provide at least one runner branch to merge"

base_repo="$DOCKYARD_ROOT/repos/$repo"
integration_branch="t/$job_id/$slug"

git -C "$base_repo" checkout -B "$integration_branch"

for runner_branch in "$@"; do
	git -C "$base_repo" merge --no-ff "$runner_branch"
done

log_info "Merged into $integration_branch"
