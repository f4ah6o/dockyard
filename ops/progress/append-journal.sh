#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

require_core_deps
ensure_session_file

repo=""
job_id=""
message=""

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
	--message)
		message="$2"
		shift 2
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
done

repo="$(resolve_repo "$repo")"
if [[ -z "$job_id" ]]; then
	job_id="$(latest_job_id "$repo")"
fi

journal_file="$DOCKYARD_ROOT/journal/$(today_date).md"
ensure_dir "$DOCKYARD_ROOT/journal"

if [[ -z "$message" ]]; then
	if [[ -n "$job_id" && -f "$DOCKYARD_ROOT/out/$repo/$job_id/decision.yaml" ]]; then
		status="$(yq e '.decision.status // ""' "$DOCKYARD_ROOT/out/$repo/$job_id/decision.yaml")"
		reason="$(yq e '.decision.reason // ""' "$DOCKYARD_ROOT/out/$repo/$job_id/decision.yaml")"
		message="status=$status reason=$reason"
	else
		message="manual journal entry"
	fi
fi

{
	echo "## $(timestamp_utc)"
	echo "- repo: $repo"
	echo "- job: ${job_id:-n/a}"
	echo "- note: $message"
	echo
} >>"$journal_file"

log_info "Appended journal: $journal_file"
