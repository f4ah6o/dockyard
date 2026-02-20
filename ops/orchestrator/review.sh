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
review_file="$job_dir/review.yaml"
errors_file="$job_dir/errors.yaml"
session_file="$DOCKYARD_ROOT/state/session.yaml"

prompt_file="$(mktemp)"
raw_file="$(mktemp)"
err_file="$(mktemp)"
trap 'rm -f "$prompt_file" "$raw_file" "$err_file"' EXIT

cat >"$prompt_file" <<PROMPT
あなたは Reviewer です。YAML のみを出力してください。

出力スキーマ:
review:
  verdict: APPROVE | REQUEST_CHANGES | BLOCK
  issues:
    - severity: HIGH | MED | LOW
      title: "..."
      detail: "..."
      suggestion: "..."
  additional_tests:
    - "..."
  risks:
    - "..."

session.yaml:
$(cat "$session_file")

plan.yaml:
$(cat "$job_dir/plan.yaml" 2>/dev/null || echo "(missing)")
PROMPT

if [[ "${DOCKYARD_MOCK_LLM:-0}" == "1" ]]; then
	cat >"$review_file" <<MOCK
review:
  verdict: APPROVE
  issues: []
  additional_tests:
    - "主要テストの再実行"
  risks:
    - "mock mode review"
MOCK
else
	load_agents_env
	timeout_seconds="$(yq e '.runtime.timeout_seconds.reviewer // 300' "$session_file")"
	timeout_cmd="$(require_timeout_cmd)"
	DOCKYARD_PROMPT="$(cat "$prompt_file")" "$timeout_cmd" "$timeout_seconds" \
		bash -lc "${REVIEWER_CMD:-} \"\$DOCKYARD_PROMPT\"" >"$raw_file" 2>"$err_file"
	cp "$raw_file" "$review_file"
fi

if ! validate_review_yaml "$review_file"; then
	append_error "$errors_file" "REVIEW" "reviewer" "INVALID_YAML" "Reviewer output is not valid review.yaml" "0"
	die "Invalid review.yaml generated"
fi

log_info "Generated $review_file"
