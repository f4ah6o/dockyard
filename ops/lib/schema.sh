#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"

_validate_yaml_parseable() {
	local file="$1"
	yq e '.' "$file" >/dev/null 2>&1
}

validate_session_yaml() {
	local file="$1"
	_validate_yaml_parseable "$file" || return 1
	yq e 'has("current_repo") and has("goal") and has("runtime") and has("retention") and has("worktrees")' "$file" | grep -q '^true$'
}

validate_plan_yaml() {
	local file="$1"
	_validate_yaml_parseable "$file" || return 1
	yq e 'has("plan") and (.plan | type == "!!map") and (.plan | has("summary")) and (.plan | has("next_actions"))' "$file" | grep -q '^true$'
}

validate_review_yaml() {
	local file="$1"
	_validate_yaml_parseable "$file" || return 1
	yq e 'has("review") and (.review | type == "!!map") and (.review | has("verdict")) and (.review | has("issues"))' "$file" | grep -q '^true$'
}

validate_decision_yaml() {
	local file="$1"
	_validate_yaml_parseable "$file" || return 1

	yq e 'has("decision") and (.decision | type == "!!map") and (.decision | has("status")) and (.decision | has("reason"))' "$file" | grep -q '^true$' || return 1

	local status
	status="$(yq e '.decision.status' "$file")"
	case "$status" in
	DISPATCH | RETRY | FAIL | DONE | WAIT_HUMAN) ;;
	*)
		return 1
		;;
	esac

	if [[ "$status" == "DISPATCH" ]]; then
		yq e 'has("dispatch") and (.dispatch | has("runners")) and (.dispatch.runners | type == "!!seq") and (.dispatch.runners | length > 0)' "$file" | grep -q '^true$' || return 1

		local count i
		count="$(yq e '.dispatch.runners | length' "$file")"
		for ((i = 0; i < count; i++)); do
			yq e "(.dispatch.runners[$i] | has(\"id\")) and
            (.dispatch.runners[$i] | has(\"task_id\")) and
            (.dispatch.runners[$i] | has(\"worktree\")) and
            (.dispatch.runners[$i] | has(\"branch\")) and
            (.dispatch.runners[$i] | has(\"command\"))" "$file" | grep -q '^true$' || return 1
		done
	fi
}
