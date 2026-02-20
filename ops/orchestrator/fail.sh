#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/errors.sh"

require_script_deps
ensure_session_file

repo=""
job_id=""
phase=""
actor=""
kind="NONZERO_EXIT"
detail="command failed"

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
	--actor)
		actor="$2"
		shift 2
		;;
	--kind)
		kind="$2"
		shift 2
		;;
	--detail)
		detail="$2"
		shift 2
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
done

repo="$(resolve_repo "$repo")"
[[ -n "$job_id" && -n "$phase" && -n "$actor" ]] || die "Usage: fail.sh --repo <repo> --job <job> --phase <phase> --actor <actor> [--kind <kind>] [--detail <detail>]"

session_file="$DOCKYARD_ROOT/state/session.yaml"
job_dir="$DOCKYARD_ROOT/out/$repo/$job_id"
errors_file="$job_dir/errors.yaml"
decision_file="$job_dir/decision.yaml"

yq -i '.retries = (.retries // {})' "$session_file"

counter_key="$(retry_counter_key "$phase" "$actor" "$kind")"
current_retry="$(COUNTER_KEY="$counter_key" yq e '.retries[strenv(COUNTER_KEY)] // 0' "$session_file")"
next_retry=$((current_retry + 1))

COUNTER_KEY="$counter_key" NEXT_RETRY="$next_retry" yq -i '.retries[strenv(COUNTER_KEY)] = (strenv(NEXT_RETRY) | tonumber)' "$session_file"

retry_key="$(runner_key_from_actor "$actor")"
max_retry="$(yq e ".runtime.max_retries.$retry_key // 0" "$session_file")"
fail_policy="$(yq e '.runtime.fail_policy // "WAIT_HUMAN"' "$session_file")"

status="RETRY"
if [[ "$next_retry" -gt "$max_retry" ]]; then
	status="$fail_policy"
fi

append_error "$errors_file" "$phase" "$actor" "$kind" "$detail" "$current_retry"

cat >"$decision_file" <<YAML
decision:
  status: $status
  reason: "$detail"
  next_actions:
    - "errors.yaml を確認"
YAML

echo "$status"
