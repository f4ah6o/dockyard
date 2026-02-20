#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

repo="${1:-}"
job_id="${2:-}"

[[ -n "$repo" && -n "$job_id" ]] || die "Usage: ops/progress/summarize.sh <repo> <job_id>"

job_dir="$DOCKYARD_ROOT/out/$repo/$job_id"
summary_file="$job_dir/summary.md"

status="$(yq e '.decision.status // ""' "$job_dir/decision.yaml" 2>/dev/null || true)"
reason="$(yq e '.decision.reason // ""' "$job_dir/decision.yaml" 2>/dev/null || true)"

cat >"$summary_file" <<MD
# Job Summary: $job_id

- repo: $repo
- decision.status: $status
- reason: $reason

## Files

- plan: $([[ -f "$job_dir/plan.yaml" ]] && echo yes || echo no)
- review: $([[ -f "$job_dir/review.yaml" ]] && echo yes || echo no)
- decision: $([[ -f "$job_dir/decision.yaml" ]] && echo yes || echo no)
- errors: $([[ -f "$job_dir/errors.yaml" ]] && echo yes || echo no)
MD

log_info "Wrote $summary_file"
