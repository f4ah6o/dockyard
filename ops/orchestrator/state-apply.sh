#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/schema.sh"

require_script_deps
ensure_session_file

repo=""
phase=""
job_id=""
decision_file=""

while [[ "$#" -gt 0 ]]; do
	case "$1" in
	--repo)
		repo="$2"
		shift 2
		;;
	--phase)
		phase="$2"
		shift 2
		;;
	--job)
		job_id="$2"
		shift 2
		;;
	--decision)
		decision_file="$2"
		shift 2
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
done

repo="$(resolve_repo "$repo")"
[[ -n "$phase" ]] || die "Missing --phase"

session_file="$DOCKYARD_ROOT/state/session.yaml"
validate_session_yaml "$session_file" || die "Invalid session.yaml"

UPDATED_AT="$(timestamp_utc)"
REPO="$repo"
PHASE="$phase"
JOB_ID="$job_id"

REPO="$REPO" PHASE="$PHASE" JOB_ID="$JOB_ID" UPDATED_AT="$UPDATED_AT" \
	yq -i '.current_repo = strenv(REPO) |
         .phase = strenv(PHASE) |
         .updated_at = strenv(UPDATED_AT) |
         .last_job_id = strenv(JOB_ID)' "$session_file"

if [[ -n "$decision_file" && -f "$decision_file" ]]; then
	validate_decision_yaml "$decision_file" || die "Invalid decision file: $decision_file"
	status="$(yq e '.decision.status' "$decision_file")"
	reason="$(yq e '.decision.reason' "$decision_file")"

	STATUS="$status" REASON="$reason" yq -i '.last_decision.status = strenv(STATUS) |
    .last_decision.reason = strenv(REASON)' "$session_file"

	DECISION_FILE="$decision_file" yq -i '.next_actions = (load(strenv(DECISION_FILE)).decision.next_actions // .next_actions)' "$session_file"
fi
