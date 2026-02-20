#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/errors.sh"

require_script_deps
ensure_session_file

repo=""
job_id=""
phase="COLLECT"
include_required=0

while [[ "$#" -gt 0 ]]; do
	case "$1" in
	--repo)
		repo="$2"
		shift 2
		;;
	--job)
		job_id="$2"
		shift 2
		;;
	--phase)
		phase="$2"
		shift 2
		;;
	--include-required)
		include_required=1
		shift
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
done

repo="$(resolve_repo "$repo")"
[[ -n "$job_id" ]] || die "Missing --job"

session_file="$DOCKYARD_ROOT/state/session.yaml"
job_dir="$DOCKYARD_ROOT/out/$repo/$job_id"
decision_file="$job_dir/decision.yaml"
errors_file="$job_dir/errors.yaml"

missing=0

check_artifact() {
	local rel_path="$1"
	local actor="$2"
	local full_path
	if [[ "$rel_path" == /* ]]; then
		full_path="$rel_path"
	else
		full_path="$job_dir/$rel_path"
	fi

	if [[ ! -e "$full_path" ]]; then
		append_error "$errors_file" "$phase" "$actor" "MISSING_ARTIFACT" "Missing artifact: $rel_path" "0"
		missing=1
	fi
}

if [[ -f "$decision_file" ]]; then
	status="$(yq e '.decision.status // ""' "$decision_file")"
	if [[ "$status" == "DISPATCH" ]]; then
		runner_count="$(yq e '.dispatch.runners | length' "$decision_file")"
		for ((i = 0; i < runner_count; i++)); do
			rid="$(yq e ".dispatch.runners[$i].id" "$decision_file")"
			expected_count="$(yq e ".dispatch.runners[$i].expected_artifacts | length" "$decision_file" 2>/dev/null || echo 0)"
			for ((j = 0; j < expected_count; j++)); do
				artifact="$(yq e ".dispatch.runners[$i].expected_artifacts[$j]" "$decision_file")"
				check_artifact "$artifact" "$rid"
			done
		done
	fi
fi

if [[ "$include_required" -eq 1 ]]; then
	req_count="$(yq e '.runtime.required_artifacts | length' "$session_file")"
	for ((i = 0; i < req_count; i++)); do
		artifact="$(yq e ".runtime.required_artifacts[$i]" "$session_file")"
		check_artifact "$artifact" "orchestrator"
	done
fi

if [[ "$missing" -ne 0 ]]; then
	die "Artifact collection failed"
fi

log_info "Artifact collection passed"
