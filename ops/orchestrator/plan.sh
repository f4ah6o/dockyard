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
plan_file="$job_dir/plan.yaml"
errors_file="$job_dir/errors.yaml"
session_file="$DOCKYARD_ROOT/state/session.yaml"

prompt_file="$(mktemp)"
raw_file="$(mktemp)"
err_file="$(mktemp)"
trap 'rm -f "$prompt_file" "$raw_file" "$err_file"' EXIT

cat >"$prompt_file" <<PROMPT
あなたは Strategist です。YAML のみを出力してください。

出力スキーマ:
plan:
  summary: "..."
  next_actions:
    - "..."
  parallelizable:
    - runner: run-1
      task_id: t1
      description: "..."
  acceptance_hints:
    - "..."
  scope_boundaries:
    - "..."
  triage_order:
    - "..."

制約:
- state/session.yaml を更新しない
- 提案のみを返す

session.yaml:
$(cat "$session_file")
PROMPT

if [[ "${DOCKYARD_MOCK_LLM:-0}" == "1" ]]; then
	cat >"$plan_file" <<MOCK
plan:
  summary: "Mock plan for $repo"
  next_actions:
    - "調査"
    - "修正"
    - "再テスト"
  parallelizable:
    - runner: run-1
      task_id: t1
      description: "テスト失敗の再現と最小修正"
  acceptance_hints:
    - "テストログを artifacts/test.log に保存"
  scope_boundaries:
    - "不要なリファクタリングはしない"
  triage_order:
    - "失敗テストの原因特定"
MOCK
else
	load_agents_env
	timeout_seconds="$(yq e '.runtime.timeout_seconds.strategist // 300' "$session_file")"
	timeout_cmd="$(require_timeout_cmd)"
	DOCKYARD_PROMPT="$(cat "$prompt_file")" "$timeout_cmd" "$timeout_seconds" \
		bash -lc "${STRATEGIST_CMD:-} \"\$DOCKYARD_PROMPT\"" >"$raw_file" 2>"$err_file"
	cp "$raw_file" "$plan_file"
fi

if ! validate_plan_yaml "$plan_file"; then
	append_error "$errors_file" "PLAN" "strategist" "INVALID_YAML" "Strategist output is not valid plan.yaml" "0"
	die "Invalid plan.yaml generated"
fi

log_info "Generated $plan_file"
