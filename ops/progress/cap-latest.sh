#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_tmux

repo="${1:-}"
[[ -n "$repo" ]] || die "Usage: ops/progress/cap-latest.sh <repo>"

job_id="$(latest_job_id "$repo")"
[[ -n "$job_id" ]] || die "No job found for repo: $repo"

out_dir="$DOCKYARD_ROOT/out/$repo/$job_id/artifacts"
ensure_dir "$out_dir"

"$DOCKYARD_ROOT/ops/tmux/capture.sh" orch "$out_dir/orch-pane.log"
"$DOCKYARD_ROOT/ops/tmux/capture.sh" strat "$out_dir/strat-pane.log"
"$DOCKYARD_ROOT/ops/tmux/capture.sh" review "$out_dir/review-pane.log"

log_info "Captured latest panes into $out_dir"
