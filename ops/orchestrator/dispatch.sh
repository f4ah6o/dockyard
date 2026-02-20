#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/schema.sh"
source "$SCRIPT_DIR/../lib/errors.sh"

require_script_deps

repo=""
job_id=""

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
	*)
		die "Unknown option: $1"
		;;
	esac
done

repo="$(resolve_repo "$repo")"
[[ -n "$job_id" ]] || die "Missing --job"

job_dir="$DOCKYARD_ROOT/out/$repo/$job_id"
decision_file="$job_dir/decision.yaml"
errors_file="$job_dir/errors.yaml"

[[ -f "$decision_file" ]] || die "Missing decision.yaml"
validate_decision_yaml "$decision_file" || die "Invalid decision.yaml"

status="$(yq e '.decision.status' "$decision_file")"
if [[ "$status" != "DISPATCH" ]]; then
	log_info "decision.status=$status, skipping dispatch"
	exit 0
fi

runner_count="$(yq e '.dispatch.runners | length' "$decision_file")"
[[ "$runner_count" -gt 0 ]] || die "No runners in dispatch.runners"

declare -a pids
declare -a runner_ids

run_one_runner() {
	local idx="$1"
	local rid
	rid="$(yq e ".dispatch.runners[$idx].id" "$decision_file")"
	local worktree
	worktree="$(yq e ".dispatch.runners[$idx].worktree" "$decision_file")"
	local branch
	branch="$(yq e ".dispatch.runners[$idx].branch" "$decision_file")"
	local timeout_seconds
	timeout_seconds="$(yq e ".dispatch.runners[$idx].timeout_seconds // 900" "$decision_file")"
	local command
	command="$(yq e ".dispatch.runners[$idx].command" "$decision_file")"

	if [[ "$worktree" != /* ]]; then
		worktree="$DOCKYARD_ROOT/$worktree"
	fi
	[[ -d "$worktree" ]] || die "Missing worktree: $worktree"

	ensure_claude_settings_for_dir "$worktree"

	local run_dir="$job_dir/runs/$rid"
	ensure_dir "$run_dir"
	printf '%s\n' "$(timestamp_utc)" >"$run_dir/started_at.txt"

	if [[ -d "$worktree/.git" || -f "$worktree/.git" ]]; then
		git -C "$worktree" checkout -B "$branch" >/dev/null 2>&1 || true
	fi

	local stdout_log="$run_dir/stdout.log"
	local stderr_log="$run_dir/stderr.log"
	local exit_code_file="$run_dir/exit_code.txt"

	set +e
	(
		cd "$worktree"
		run_cmd_with_timeout "$timeout_seconds" bash -lc "$command"
	) >"$stdout_log" 2>"$stderr_log"
	rc=$?
	set -e

	printf '%s\n' "$rc" >"$exit_code_file"
	printf '%s\n' "$(timestamp_utc)" >"$run_dir/finished_at.txt"

	if [[ "$rc" -eq 124 ]]; then
		printf '%s\n' "TIMEOUT" >"$run_dir/error_kind.txt"
	elif [[ "$rc" -ne 0 ]]; then
		printf '%s\n' "NONZERO_EXIT" >"$run_dir/error_kind.txt"
	fi
}

for ((i = 0; i < runner_count; i++)); do
	rid="$(yq e ".dispatch.runners[$i].id" "$decision_file")"
	runner_ids+=("$rid")
	run_one_runner "$i" &
	pids+=("$!")
done

for pid in "${pids[@]}"; do
	wait "$pid"
done

all_ok=0
for rid in "${runner_ids[@]}"; do
	run_dir="$job_dir/runs/$rid"
	rc="$(cat "$run_dir/exit_code.txt")"
	if [[ "$rc" -ne 0 ]]; then
		all_ok=1
		kind="NONZERO_EXIT"
		if [[ -f "$run_dir/error_kind.txt" ]]; then
			kind="$(cat "$run_dir/error_kind.txt")"
		fi
		append_error "$errors_file" "RUNNING" "$rid" "$kind" "Runner $rid exited with $rc" "0"
	fi
done

if [[ "$all_ok" -ne 0 ]]; then
	die "One or more runners failed"
fi

log_info "Dispatch complete"
