#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_core_deps
ensure_session_file

repo=""
while [[ "$#" -gt 0 ]]; do
	case "$1" in
	--repo)
		repo="$2"
		shift 2
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
done

repo="$(resolve_repo "$repo")"
session_file="$DOCKYARD_ROOT/state/session.yaml"
status_file="$DOCKYARD_ROOT/STATUS.md"

phase="$(yq e '.phase // "UNKNOWN"' "$session_file")"
updated_at="$(yq e '.updated_at // ""' "$session_file")"
goal="$(yq e '.goal // ""' "$session_file")"
acceptance="$(yq e '.acceptance[]' "$session_file" 2>/dev/null || true)"
last_job_id="$(latest_job_id "$repo")"
if [[ -z "$last_job_id" ]]; then
	last_job_id="$(yq e '.last_job_id // ""' "$session_file")"
fi

last_status="$(yq e '.last_decision.status // ""' "$session_file")"
last_reason="$(yq e '.last_decision.reason // ""' "$session_file")"

errors_summary=""
if [[ -n "$last_job_id" && -f "$DOCKYARD_ROOT/out/$repo/$last_job_id/errors.yaml" ]]; then
	errors_summary="$(yq e '.errors[] | "- [" + .phase + "/" + .actor + "] " + .kind + ": " + .detail' "$DOCKYARD_ROOT/out/$repo/$last_job_id/errors.yaml" 2>/dev/null || true)"
fi

next_actions="$(yq e '.next_actions[]' "$session_file" 2>/dev/null || true)"

cat >"$status_file" <<MD
# STATUS

- current_repo: $repo
- updated_at: $updated_at
- phase: $phase
- latest_job_id: $last_job_id

## Goal

$goal

## Acceptance

$acceptance

## Last Decision

- status: $last_status
- reason: $last_reason

## Errors

${errors_summary:-"- none"}

## Next Actions

${next_actions:-"- none"}
MD

log_info "Rendered STATUS.md"
