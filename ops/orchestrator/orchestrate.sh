#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/schema.sh"

require_script_deps
ensure_session_file

mode="once"
repo=""
runners=1
interval=30

while [[ "$#" -gt 0 ]]; do
	case "$1" in
	--once)
		mode="once"
		shift
		;;
	--loop)
		mode="loop"
		shift
		;;
	--repo)
		repo="$2"
		shift 2
		;;
	--runners)
		runners="$2"
		shift 2
		;;
	--interval)
		interval="$2"
		shift 2
		;;
	*)
		die "Unknown option: $1"
		;;
	esac
done

repo="$(resolve_repo "$repo")"
[[ -d "$DOCKYARD_ROOT/repos/$repo/.git" ]] || die "Missing baseline repo: repos/$repo"
validate_session_yaml "$DOCKYARD_ROOT/state/session.yaml" || die "Invalid state/session.yaml"

"$DOCKYARD_ROOT/ops/work/worktree-create.sh" "$repo" "$runners"

session_lock_fd_open

run_with_retry() {
	local phase="$1"
	local actor="$2"
	shift 2

	while true; do
		set +e
		"$@"
		rc=$?
		set -e

		if [[ "$rc" -eq 0 ]]; then
			return 0
		fi

		kind="NONZERO_EXIT"
		if [[ "$rc" -eq 124 ]]; then
			kind="TIMEOUT"
		fi

		status="$("$SCRIPT_DIR"/fail.sh --repo "$repo" --job "$job_id" --phase "$phase" --actor "$actor" --kind "$kind" --detail "$phase failed for $actor (exit=$rc)")"
		if [[ "$status" == "RETRY" ]]; then
			log_warn "$phase failed for $actor; retrying"
			continue
		fi
		return 1
	done
}

while true; do
	job_id="$(job_id_now)"
	ensure_job_dirs "$repo" "$job_id"
	cp "$DOCKYARD_ROOT/state/session.yaml" "$DOCKYARD_ROOT/out/$repo/$job_id/inputs/session.yaml.snapshot"

	"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase PLAN --job "$job_id"
	if ! run_with_retry "PLAN" "strategist" "$SCRIPT_DIR/plan.sh" --repo "$repo" --job "$job_id"; then
		"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase WAIT_HUMAN --job "$job_id" --decision "$DOCKYARD_ROOT/out/$repo/$job_id/decision.yaml"
		"$DOCKYARD_ROOT/ops/progress/render-status.sh" --repo "$repo"
		exit 1
	fi

	"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase DISPATCH --job "$job_id"
	if ! run_with_retry "DISPATCH" "orchestrator" "$SCRIPT_DIR/decide.sh" --repo "$repo" --job "$job_id" --phase DISPATCH --runners "$runners"; then
		"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase WAIT_HUMAN --job "$job_id" --decision "$DOCKYARD_ROOT/out/$repo/$job_id/decision.yaml"
		"$DOCKYARD_ROOT/ops/progress/render-status.sh" --repo "$repo"
		exit 1
	fi

	decision_file="$DOCKYARD_ROOT/out/$repo/$job_id/decision.yaml"
	dispatch_status="$(yq e '.decision.status' "$decision_file")"
	if [[ "$dispatch_status" != "DISPATCH" ]]; then
		"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase "$dispatch_status" --job "$job_id" --decision "$decision_file"
		"$DOCKYARD_ROOT/ops/progress/render-status.sh" --repo "$repo"
		"$DOCKYARD_ROOT/ops/progress/append-journal.sh" --repo "$repo" --job "$job_id"
		if [[ "$dispatch_status" =~ ^(DONE|FAIL|WAIT_HUMAN)$ ]]; then
			exit 0
		fi
		if [[ "$mode" == "once" ]]; then
			exit 0
		fi
		sleep "$interval"
		continue
	fi

	"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase RUNNING --job "$job_id"
	if ! run_with_retry "RUNNING" "runner" "$SCRIPT_DIR/dispatch.sh" --repo "$repo" --job "$job_id"; then
		"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase WAIT_HUMAN --job "$job_id" --decision "$decision_file"
		"$DOCKYARD_ROOT/ops/progress/render-status.sh" --repo "$repo"
		exit 1
	fi

	"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase COLLECT --job "$job_id"
	if ! run_with_retry "COLLECT" "orchestrator" "$SCRIPT_DIR/collect.sh" --repo "$repo" --job "$job_id" --phase COLLECT; then
		"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase WAIT_HUMAN --job "$job_id" --decision "$decision_file"
		"$DOCKYARD_ROOT/ops/progress/render-status.sh" --repo "$repo"
		exit 1
	fi

	"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase REVIEW --job "$job_id"
	if ! run_with_retry "REVIEW" "reviewer" "$SCRIPT_DIR/review.sh" --repo "$repo" --job "$job_id"; then
		"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase WAIT_HUMAN --job "$job_id" --decision "$decision_file"
		"$DOCKYARD_ROOT/ops/progress/render-status.sh" --repo "$repo"
		exit 1
	fi

	if ! run_with_retry "COLLECT" "orchestrator" "$SCRIPT_DIR/collect.sh" --repo "$repo" --job "$job_id" --phase REVIEW --include-required; then
		"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase WAIT_HUMAN --job "$job_id" --decision "$decision_file"
		"$DOCKYARD_ROOT/ops/progress/render-status.sh" --repo "$repo"
		exit 1
	fi

	"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase DECIDE --job "$job_id"
	if ! run_with_retry "DECIDE" "orchestrator" "$SCRIPT_DIR/decide.sh" --repo "$repo" --job "$job_id" --phase DECIDE --runners "$runners"; then
		"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase WAIT_HUMAN --job "$job_id" --decision "$decision_file"
		"$DOCKYARD_ROOT/ops/progress/render-status.sh" --repo "$repo"
		exit 1
	fi

	final_status="$(yq e '.decision.status' "$decision_file")"
	"$SCRIPT_DIR/state-apply.sh" --repo "$repo" --phase "$final_status" --job "$job_id" --decision "$decision_file"
	"$DOCKYARD_ROOT/ops/progress/render-status.sh" --repo "$repo"
	"$DOCKYARD_ROOT/ops/progress/append-journal.sh" --repo "$repo" --job "$job_id"

	if [[ "$mode" == "once" ]]; then
		break
	fi

	if [[ "$final_status" =~ ^(DONE|FAIL|WAIT_HUMAN)$ ]]; then
		break
	fi

	sleep "$interval"
done

log_info "orchestrate complete"
