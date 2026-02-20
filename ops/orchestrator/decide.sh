#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/schema.sh"
source "$SCRIPT_DIR/../lib/errors.sh"

require_script_deps
ensure_session_file

repo=""
job_id=""
phase="DECIDE"
runners=1

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
	--runners)
		runners="$2"
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
session_file="$DOCKYARD_ROOT/state/session.yaml"

make_wait_human_decision() {
	local reason="$1"
	cat >"$decision_file" <<YAML
decision:
  status: WAIT_HUMAN
  reason: "$reason"
  next_actions:
    - "errors.yaml を確認"
YAML
}

generate_mock_dispatch() {
	local timeout_runner
	timeout_runner="$(yq e '.runtime.timeout_seconds.runner // 900' "$session_file")"

	cat >"$decision_file" <<YAML
decision:
  status: DISPATCH
  reason: "Mock dispatch generated"
  next_actions:
    - "runner 実行待ち"

dispatch:
  runners:
YAML

	local i
	for ((i = 1; i <= runners; i++)); do
		local rid="run-$i"
		local branch="r/$job_id/$rid/mock-task"
		local wt="worktrees/$repo/$rid"
		cat >>"$decision_file" <<YAML
    - id: $rid
      task_id: t$i
      worktree: $wt
      branch: $branch
      timeout_seconds: $timeout_runner
      expected_artifacts:
        - artifacts/$rid.diff.patch
        - artifacts/$rid.test.log
      command: |-
        set -euo pipefail
        mkdir -p "$DOCKYARD_ROOT/out/$repo/$job_id/artifacts"
        git diff > "$DOCKYARD_ROOT/out/$repo/$job_id/artifacts/$rid.diff.patch" || true
        echo "mock test log $rid" > "$DOCKYARD_ROOT/out/$repo/$job_id/artifacts/$rid.test.log"
        if [[ "$rid" == "run-1" ]]; then
          cp "$DOCKYARD_ROOT/out/$repo/$job_id/artifacts/$rid.diff.patch" "$DOCKYARD_ROOT/out/$repo/$job_id/artifacts/diff.patch"
          cp "$DOCKYARD_ROOT/out/$repo/$job_id/artifacts/$rid.test.log" "$DOCKYARD_ROOT/out/$repo/$job_id/artifacts/test.log"
        fi
        echo "$rid done"
YAML
	done

	cat >>"$decision_file" <<YAML
acceptance_check:
  command: "echo mock acceptance"
notes:
  risks: []
  requires_human: []
YAML
}

generate_mock_decide() {
	local verdict="REQUEST_CHANGES"
	if [[ -f "$job_dir/review.yaml" ]]; then
		verdict="$(yq e '.review.verdict // "REQUEST_CHANGES"' "$job_dir/review.yaml")"
	fi

	if [[ "$verdict" == "APPROVE" ]]; then
		cat >"$decision_file" <<YAML
decision:
  status: DONE
  reason: "Reviewer approved in mock mode"
  next_actions:
    - "完了を記録"
YAML
	else
		generate_mock_dispatch
	fi
}

prompt_file="$(mktemp)"
raw_file="$(mktemp)"
err_file="$(mktemp)"
trap 'rm -f "$prompt_file" "$raw_file" "$err_file"' EXIT

if [[ "${DOCKYARD_MOCK_LLM:-0}" == "1" ]]; then
	if [[ "$phase" == "DISPATCH" ]]; then
		generate_mock_dispatch
	else
		generate_mock_decide
	fi
else
	load_agents_env
	cat >"$prompt_file" <<PROMPT
You are the Orchestrator decision model. Output YAML only.

Schema:
decision:
  status: DISPATCH | RETRY | FAIL | DONE | WAIT_HUMAN
  reason: "..."
  next_actions:
    - "..."
dispatch:
  runners:
    - id: run-1
      task_id: t1
      worktree: worktrees/$repo/run-1
      branch: r/$job_id/run-1/task
      timeout_seconds: 900
      expected_artifacts:
        - artifacts/diff.patch
      command: |-
        <full command>
acceptance_check:
  command: "..."
notes:
  risks: []
  requires_human: []

Rules:
- YAML only, no markdown fences.
- state/session.yaml is SSOT and must not be mutated directly.
- command must be fully executable by dispatch.
- No push.

phase: $phase
session.yaml:
$(cat "$session_file")

plan.yaml:
$(cat "$job_dir/plan.yaml" 2>/dev/null || echo "(missing)")

review.yaml:
$(cat "$job_dir/review.yaml" 2>/dev/null || echo "(missing)")
PROMPT

	timeout_seconds="$(yq e '.runtime.timeout_seconds.decide // 180' "$session_file")"
	timeout_cmd="$(require_timeout_cmd)"
	if ! DOCKYARD_PROMPT="$(cat "$prompt_file")" "$timeout_cmd" "$timeout_seconds" \
		bash -lc "${ORCH_DECIDE_CMD:-} \"\$DOCKYARD_PROMPT\"" >"$raw_file" 2>"$err_file"; then
		append_error "$errors_file" "$phase" "orchestrator" "NONZERO_EXIT" "decide command failed" "0"
		die "decide command failed"
	fi
	cp "$raw_file" "$decision_file"
fi

if ! validate_decision_yaml "$decision_file"; then
	append_error "$errors_file" "$phase" "orchestrator" "INVALID_DECISION_YAML" "Invalid decision.yaml generated" "0"
	make_wait_human_decision "Invalid decision.yaml generated"
fi

log_info "Generated $decision_file"
