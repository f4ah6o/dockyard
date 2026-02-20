#!/usr/bin/env bash

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCKYARD_ROOT="$(cd "$COMMON_DIR/../.." && pwd)"

log_info() {
	printf '[INFO] %s\n' "$*" >&2
}

log_warn() {
	printf '[WARN] %s\n' "$*" >&2
}

log_error() {
	printf '[ERROR] %s\n' "$*" >&2
}

die() {
	log_error "$*"
	exit 1
}

timestamp_utc() {
	date -u +"%Y-%m-%dT%H:%M:%SZ"
}

job_id_now() {
	date +"%Y%m%d-%H%M%S"
}

today_date() {
	date +"%Y-%m-%d"
}

ensure_dir() {
	mkdir -p "$1"
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_core_deps() {
	local deps=(bash git yq tar)
	local cmd
	for cmd in "${deps[@]}"; do
		require_cmd "$cmd"
	done
	require_timeout_cmd >/dev/null
}

require_timeout_cmd() {
	if command -v timeout >/dev/null 2>&1; then
		echo timeout
		return 0
	fi
	if command -v gtimeout >/dev/null 2>&1; then
		echo gtimeout
		return 0
	fi
	die "Missing timeout command: install GNU timeout (timeout/gtimeout)"
}

require_flock() {
	require_cmd flock
}

require_tmux() {
	require_cmd tmux
}

require_script_deps() {
	require_core_deps
	require_flock
}

load_agents_env() {
	local env_file="$DOCKYARD_ROOT/config/agents.env"
	[[ -f "$env_file" ]] || die "Missing $env_file (copy from config/agents.env.example)"
	# shellcheck disable=SC1090
	source "$env_file"
}

ensure_session_file() {
	local session="$DOCKYARD_ROOT/state/session.yaml"
	[[ -f "$session" ]] || die "Missing $session (copy from state/session.yaml.example)"
}

resolve_repo() {
	local explicit_repo="${1:-}"
	local session="$DOCKYARD_ROOT/state/session.yaml"

	if [[ -n "$explicit_repo" ]]; then
		echo "$explicit_repo"
		return 0
	fi

	if [[ -f "$session" ]]; then
		local repo
		repo="$(yq e '.current_repo // ""' "$session")"
		if [[ -n "$repo" ]]; then
			echo "$repo"
			return 0
		fi
	fi

	die "Repository is not specified. Use --repo <repo> or set state/session.yaml current_repo."
}

latest_job_id() {
	local repo="$1"
	local out_repo="$DOCKYARD_ROOT/out/$repo"
	if [[ ! -d "$out_repo" ]]; then
		echo ""
		return 0
	fi
	find "$out_repo" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sed 's|.*/||' | sort | tail -n 1
}

ensure_job_dirs() {
	local repo="$1"
	local job_id="$2"
	ensure_dir "$DOCKYARD_ROOT/out/$repo/$job_id"
	ensure_dir "$DOCKYARD_ROOT/out/$repo/$job_id/inputs"
	ensure_dir "$DOCKYARD_ROOT/out/$repo/$job_id/runs"
	ensure_dir "$DOCKYARD_ROOT/out/$repo/$job_id/artifacts"
}

init_yaml_array_file() {
	local file="$1"
	local key="$2"
	if [[ ! -f "$file" ]]; then
		printf '%s: []\n' "$key" >"$file"
	fi
}

runner_key_from_actor() {
	local actor="$1"
	case "$actor" in
	run-* | runner)
		echo "runner"
		;;
	strategist)
		echo "strategist"
		;;
	reviewer)
		echo "reviewer"
		;;
	decide | orchestrator)
		echo "decide"
		;;
	*)
		echo "runner"
		;;
	esac
}

retry_counter_key() {
	local phase="$1"
	local actor="$2"
	local kind="$3"
	printf '%s|%s|%s' "$phase" "$actor" "$kind"
}

run_cmd_with_timeout() {
	local timeout_seconds="$1"
	shift
	local timeout_cmd
	timeout_cmd="$(require_timeout_cmd)"
	"$timeout_cmd" "$timeout_seconds" "$@"
}

mtime_epoch() {
	local path="$1"
	if stat -f %m "$path" >/dev/null 2>&1; then
		stat -f %m "$path"
		return 0
	fi
	stat -c %Y "$path"
}

days_since_mtime() {
	local path="$1"
	local now
	now="$(date +%s)"
	local mtime
	mtime="$(mtime_epoch "$path")"
	echo $(((now - mtime) / 86400))
}

sorted_job_dirs() {
	local repo="$1"
	local out_repo="$DOCKYARD_ROOT/out/$repo"
	[[ -d "$out_repo" ]] || return 0
	find "$out_repo" -mindepth 1 -maxdepth 1 -type d -print | sort
}

session_lock_fd_open() {
	local lock_file="$DOCKYARD_ROOT/state/session.lock"
	ensure_dir "$(dirname "$lock_file")"
	exec 9>"$lock_file"
	flock 9
}
